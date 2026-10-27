import "dart:async";

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
  static const int _maxProbe = 8;

  static const Duration _interval = Duration(seconds: 60);

  bool enabled = false;

  Timer? _timer;
  bool _busy = false;
  bool _started = false;

  /// 上一轮谁在听
  Set<int> _lastOnline = {};
  bool _hasBaseline = false;

  Future<void> init() async {
    final storage = await SharedPreferences.getInstance();
    enabled = storage.getBool(_kEnabled) ?? false;
    WidgetsBinding.instance.addObserver(this);
    if (enabled) _start();
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    final storage = await SharedPreferences.getInstance();
    await storage.setBool(_kEnabled, value);

    if (value) {
      _start();
    } else {
      _stop();
      _hasBaseline = false;
      _lastOnline = {};
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
    final members = PartyRoster.instance.members.take(_maxProbe).toList();
    if (members.isEmpty) return;

    _busy = true;
    final online = <int>{};
    try {
      await Future.wait(
        members.map((m) async {
          final probe = await PartyService.instance.probeRoom(m.roomId);
          if (probe != null && probe.isFresh) online.add(m.mid);
        }),
      );
    } catch (_) {
      // 网络抖动就跳过这一轮，不重试、不堆积
    } finally {
      _busy = false;
    }

    if (!_hasBaseline) {
      _lastOnline = online;
      _hasBaseline = true;
      return;
    }

    final fresh = online.difference(_lastOnline);
    _lastOnline = online;
    if (fresh.isEmpty) return;

    final names = members
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