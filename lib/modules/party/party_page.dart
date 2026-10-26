import "dart:async";

import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/party/party_roster.dart";
import "package:bobomusic/modules/party/party_service.dart";
import "package:bobomusic/modules/party/party_tone.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

/// 一起听会话：把本机播放状态广播出去，并跟随远端状态
class PartySession {
  PartySession._();

  static final PartySession instance = PartySession._();

  final PartyService _party = PartyService.instance;

  PlayerModel? _player;
  Timer? _broadcastTimer;
  StreamSubscription<PartyState>? _stateSub;
  StreamSubscription<PartyNotice>? _noticeSub;
  StreamSubscription? _refreshSub;

  final _changes = StreamController<void>.broadcast();

  /// 房间 / 权限变化（页面据此刷新）
  Stream<void> get changes => _changes.stream;

  bool get isHost => _party.isHost;
  bool get isGuest => _party.isGuest;
  bool get inRoom => _party.inRoom;
  bool get connected => _party.connected;
  String get roomId => _party.roomId;
  Map<String, String> get members => _party.members;
  Stream<Map<String, String>> get memberStream => _party.membersStream;

  /// 只能听、不能自己操作
  bool get isLocked => _party.isLocked;

  /// 我能控制播放（房主 / 共管）
  bool get canControl => _party.allowLocalControl;

  /// 最近一次收到的远端歌曲
  MusicItem? remoteMusic;

  void attach(PlayerModel player) {
    _player = player;

    _stateSub?.cancel();
    _stateSub = _party.states.listen((state) {
      _onRemoteState(state);
    });

    _noticeSub?.cancel();
    _noticeSub = _party.notices.listen(_onNotice);

    _party.onSyncRequested = () {
      if (_canBroadcast) _broadcastNow();
    };

    // 本机切歌 / 暂停立刻广播，避免等下一次 tick
    _refreshSub?.cancel();
    _refreshSub = eventBus.on<RefreshPlayerCard>().listen((_) {
      if (_canBroadcast) _broadcastNow();
    });
  }

  bool get _canBroadcast => inRoom && _party.allowLocalControl;

  /// 上线：用自己房间号开房并开始广播
  ///
  /// 只有一起听名单里的人能进来；名单里点红心的人可以和我一起控制播放。
  Future<bool> goOnline() async {
    if (_party.inRoom) return true;

    await PartyRoster.instance.init();
    final id = await selfPartyRoomId();

    final ok = await _party.createRoom(
      name: selfPartyName(),
      id: id,
      allowed: PartyRoster.instance.uids,
      controllers: PartyRoster.instance.controllerUids,
    );

    if (ok) startBroadcasting();
    _notify();
    return ok;
  }

  /// 打开 App 时自动上线
  ///
  /// 该行为**默认开启**，可在设置里关掉。
  Future<void> autoOnlineIfEnabled() async {
    if (!await PartyRoster.isAutoOnline()) return;
    // 没登录就没有 UID，别人也认不出你，上线没意义
    if (!BiliAuth.instance.isLogin) return;
    await goOnline();
  }

  /// 名单变了：同步给服务层，被移出名单的人会被请出房间
  void refreshPermissions() {
    if (!isHost) return;
    _party.updatePermissions(
      allowed: PartyRoster.instance.uids,
      controllers: PartyRoster.instance.controllerUids,
    );
    _notify();
  }

  /// 加入别人的房间
  Future<bool> join(String roomId) async {
    _stopBroadcast();
    final ok = await _party.joinRoom(id: roomId, name: selfPartyName());
    _notify();
    return ok;
  }

  /// 下线 / 退出房间
  Future<void> goOffline() async {
    _stopBroadcast();
    remoteMusic = null;
    await _party.leaveRoom();
    _notify();
  }

  Future<void> leave() => goOffline();

  /// 开始周期广播（只有房主需要定时广播，共管改歌时按事件广播）
  void startBroadcasting() {
    _broadcastTimer?.cancel();
    if (!isHost) {
      _broadcastNow();
      return;
    }
    _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _broadcastNow();
    });
    _broadcastNow();
  }

  void _stopBroadcast() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
  }

  void _broadcastNow() {
    final player = _player;
    final music = player?.current;
    if (player == null || music == null) return;
    if (!inRoom || !_party.connected) return;
    if (!_party.allowLocalControl) return;

    _party.broadcast(
      music: music,
      position: player.currentPosition,
      playing: player.isPlaying,
    );
  }

  Future<void> _apply(Future<void> Function() action) async {
    _party.applyingRemote = true;
    try {
      await action();
    } finally {
      _party.applyingRemote = false;
    }
  }

  Future<void> _onRemoteState(PartyState state) async {
    if (!inRoom) return;

    final player = _player;
    if (player == null) return;

    final music = state.toMusicItem();
    if (music == null) return;

    final current = player.current;
    final sameMusic = current != null && current.id == music.id;

    // 补偿网络延迟（最多补偿 5 秒，防止对方手机时间不准）
    final elapsed = state.at > 0
        ? (DateTime.now().millisecondsSinceEpoch - state.at).clamp(0, 5000)
        : 0;
    var target = Duration(milliseconds: state.position + elapsed);
    final total = Duration(seconds: music.duration);
    if (total > Duration.zero && target > total) target = total;

    if (!sameMusic) {
      remoteMusic = music;
      await _apply(() async {
        await player.play(music: music);
        await Future.delayed(const Duration(milliseconds: 600));
        await player.seek(target);
        if (!state.playing) await player.pause();
      });
      if (!isLocked) {
        BotToast.showText(text: "已同步：${music.name}");
      }
      return;
    }

    // 同一首歌：偏差超过 1.5 秒才纠正，避免抖动
    final drift = (player.currentPosition - target).abs();
    if (drift.inMilliseconds > 1500) {
      await _apply(() async {
        await player.seek(target);
      });
    }

    if (state.playing && !player.isPlaying) {
      await _apply(() async {
        await player.play();
      });
    } else if (!state.playing && player.isPlaying) {
      await _apply(() async {
        await player.pause();
      });
    }
  }

  void _onNotice(PartyNotice notice) {
    switch (notice.kind) {
      case PartyNoticeKind.joined:
        BotToast.showText(text: "${_displayName(notice.name)} 加入了一起听");
        PartyTone.instance.playJoin();
        break;
      case PartyNoticeKind.left:
        BotToast.showText(text: "${_displayName(notice.name)} 离开了一起听");
        PartyTone.instance.playLeave();
        break;
      case PartyNoticeKind.denied:
        BotToast.showText(
          text: "房主没把你加进一起听名单，进不去这个房间",
          duration: const Duration(seconds: 4),
        );
        PartyTone.instance.playLeave();
        break;
      case PartyNoticeKind.hostLeft:
        BotToast.showText(
          text: "房主下线了，一起听结束",
          duration: const Duration(seconds: 4),
        );
        PartyTone.instance.playLeave();
        break;
    }

    _notify();
  }

  String _displayName(String name) => name.trim().isEmpty ? "好友" : name;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() {
    _stopBroadcast();
    _stateSub?.cancel();
    _noticeSub?.cancel();
    _refreshSub?.cancel();
    _changes.close();
  }
}

/// 从「一起听邀请」进入，自动加入房间
class PartyJoinPage extends StatefulWidget {
  final String roomId;

  const PartyJoinPage({super.key, required this.roomId});

  @override
  State<PartyJoinPage> createState() => _PartyJoinPageState();
}

class _PartyJoinPageState extends State<PartyJoinPage> {
  final PartySession session = PartySession.instance;
  bool busy = true;
  bool ok = false;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    final result = await session.join(widget.roomId.trim());
    if (!mounted) return;
    setState(() {
      busy = false;
      ok = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final player = Provider.of<PlayerModel>(context);

    return Scaffold(
      appBar: AppBar(title: const Text("一起听", style: TextStyle(fontSize: 18))),
      body: SafeArea(
        child: Center(
          child: busy
              ? const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        ok ? Icons.headphones : Icons.cloud_off_outlined,
                        size: 44,
                        color: ok ? primaryColor : Colors.grey,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        ok ? "已加入房间 ${session.roomId}" : "加入失败",
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ok
                            ? "房主切歌或拖动进度时，你会自动同步"
                            : "房间号不对，或者房主没把你加进一起听名单",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          height: 1.7,
                        ),
                      ),
                      if (ok && player.current != null) ...[
                        const SizedBox(height: 18),
                        Text(
                          "当前：${player.current!.name}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await session.leave();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.logout, size: 17),
                        label: const Text("退出房间"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
