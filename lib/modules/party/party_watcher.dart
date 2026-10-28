import "dart:async";

import "package:bobomusic/modules/party/party_background.dart";
import "package:bobomusic/modules/party/party_roster.dart";
import "package:bobomusic/modules/party/party_service.dart";
import "package:bobomusic/modules/party/party_tone.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/widgets.dart";
import "package:shared_preferences/shared_preferences.dart";

/// 好友上线提醒
///
/// 省电优先的设计：
/// - 只在 App 前台（resumed）时轮询，切到后台立刻停
/// - 60 秒一次，一次最多探 8 个人
/// - 自己已经在房间里就不探（已经在听歌了，没必要提醒）
/// - 不做常驻后台服务，不申请前台服务权限
class PartyWatcher with WidgetsBindingObserver {
  PartyWatcher._();

  static final PartyWatcher instance = PartyWatcher._();

  static const String _kEnabled = "manman_party_watch_friends";

  /// 一轮最多探几个人，名单再长也不会把请求数堆上去
  ///
  /// ntfy.sh 按 IP 限流（60 次突发，之后每 5 秒回 1 次 ≈ 12 次/分钟），
  /// 这个额度要留给房间里的同步。一轮探 4 个、名单轮着来，
  /// 十分钟的名单两分半就能全部过一遍。
  static const int _probePerRound = 4;

  static const Duration _interval = Duration(seconds: 60);

  bool enabled = false;

  Timer? _timer;
  bool _busy = false;
  bool _started = false;

  /// 轮询游标：每轮从名单的不同位置开始探
  int _cursor = 0;

  /// 上次探测时各自在不在听（null = 还没探过）
  final Map<int, bool> _online = {};

  Future<void> init() async {
    final storage = await SharedPreferences.getInstance();
    enabled = storage.getBool(_kEnabled) ?? false;
    WidgetsBinding.instance.addObserver(this);
    if (enabled) {
      _start();
      await PartyBackground.enable();
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    final storage = await SharedPreferences.getInstance();
    await storage.setBool(_kEnabled, value);

    if (value) {
      _start();
      // 后台交给系统按 15 分钟一次的节奏唤醒，省电优先
      await PartyBackground.enable();
    } else {
      _stop();
      await PartyBackground.disable();
      _online.clear();
      _cursor = 0;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!enabled) return;
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _stop();
    }
  }

  void _start() {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(_interval, (_) => _tick());
    // 刚打开开关时先跑一次，只用来建立基线，不提醒
    Future.microtask(_tick);
  }

  void _stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (!enabled || _busy) return;
    // 自己就在房间里，正在听歌，不用提醒
    if (PartyService.instance.inRoom) return;

    await PartyRoster.instance.init();
    final all = PartyRoster.instance.members;
    if (all.isEmpty) return;

    // 名单里删掉的人也跟着清掉，免得残留记录
    final mids = all.map((m) => m.mid).toSet();
    _online.removeWhere((mid, _) => !mids.contains(mid));

    // 轮着探：每轮只碰几个，把中继额度留给房间
    final batch = <RosterMember>[];
    for (var i = 0; i < _probePerRound && i < all.length; i++) {
      batch.add(all[(_cursor + i) % all.length]);
    }
    _cursor = (_cursor + _probePerRound) % all.length;

    _busy = true;
    final fresh = <int>[];
    try {
      await PartyService.forEachLimited(batch, (m) async {
        final probe = await PartyService.instance.probeRoom(m.roomId);
        final online = probe != null && probe.isFresh;
        // 只有「确定上次没在听 → 现在在听」才提醒；
        // 没探过的人（null）只记状态，不提醒
        if (_online[m.mid] == false && online) fresh.add(m.mid);
        _online[m.mid] = online;
      }, limit: 2, gap: const Duration(milliseconds: 400));
    } catch (_) {
      // 网络抖动就跳过这一轮，不重试、不堆积
    } finally {
      _busy = false;
    }

    if (fresh.isEmpty) return;

    final names = batch
        .where((m) => fresh.contains(m.mid))
        .map((m) => m.uname.isEmpty ? "好友" : m.uname)
        .toList();

    BotToast.showText(
      text: names.length == 1
          ? "${names.first} 开始听歌了，点「一起听」就能加进去"
          : "${names.join("、")} 都开始听歌了",
      duration: const Duration(seconds: 4),
    );
    PartyTone.instance.playJoin();
  }
}