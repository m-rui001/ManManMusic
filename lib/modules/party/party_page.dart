import "dart:async";

import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/bili_account/bili_login_gate.dart";
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
  StreamSubscription? _playerStateSub;
  StreamSubscription? _seekSub;
  PartyState? _pendingState;
  bool _following = false;
  StreamSubscription<PartyState>? _stateSub;
  StreamSubscription<PartyNotice>? _noticeSub;
  StreamSubscription? _refreshSub;

  final _changes = StreamController<void>.broadcast();

  /// 房间 / 权限变化（页面据此刷新）
  Stream<void> get changes => _changes.stream;

  bool get isHost => _party.isHost;
  bool get isGuest => _party.isGuest;
  bool get inRoom => _party.inRoom;
  bool get connected => _party.connected && (!isGuest || _party.admitted);
  String get roomId => _party.roomId;
  Map<String, String> get members => _party.members;
  Map<String, int> get memberUids => _party.memberUids;
  Set<int> get controlUids => _party.controlUids;
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

    _party.onSyncRequested = ({String toClient = "", int toUid = 0}) {
      _broadcastNow(toClient: toClient, toUid: toUid);
    };
    _party.onConnectionChanged = (online) {
      if (!online) {
        _pendingState = null;
        if (!inRoom) remoteMusic = null;
      } else if (isHost) {
        _broadcastNow();
      }
      _notify();
    };
    _refreshSub?.cancel();
    _refreshSub =
        eventBus.on<RefreshPlayerCard>().listen((_) => _scheduleBroadcast());
    _seekSub?.cancel();
    _seekSub =
        eventBus.on<PartyPlaybackChanged>().listen((_) => _scheduleBroadcast());
    _playerStateSub?.cancel();
    _playerStateSub = player.playerStates?.listen((_) => _scheduleBroadcast());
  }

  void _scheduleBroadcast() {
    if (_following || !inRoom || !_party.allowLocalControl) return;
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer(const Duration(milliseconds: 350), _broadcastNow);
  }

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
    _broadcastTimer?.cancel();
    _pendingState = null;
    remoteMusic = null;
    final ok = await _party.joinRoom(id: roomId, name: selfPartyName());
    _notify();
    return ok;
  }

  Future<void> goOffline() async {
    _broadcastTimer?.cancel();
    _pendingState = null;
    remoteMusic = null;
    await _party.leaveRoom();
    _notify();
  }

  Future<void> leave() => goOffline();

  Future<bool> retryConnection() async {
    final ok = await _party.retryNow();
    _notify();
    return ok;
  }

  String get connectionHint => _party.connectionHint;
  String get joinHint => _party.joinHint;

  void _broadcastNow({String toClient = "", int toUid = 0}) {
    if (!inRoom || !_party.connected || !_party.allowLocalControl) return;
    if (_following && toClient.isEmpty) return;
    final player = _player;
    _party.broadcast(
      music: player?.current,
      position: player?.currentPosition ?? Duration.zero,
      playing: player?.isPlaying ?? false,
      toClient: toClient,
      toUid: toUid,
    );
  }

  Future<void> _onRemoteState(PartyState state) async {
    _pendingState = state;
    if (_following) return;
    _following = true;
    _broadcastTimer?.cancel();
    PartyState? applied;
    try {
      while (_pendingState != null) {
        final next = _pendingState!;
        _pendingState = null;
        final player = _player;
        if (player == null || !inRoom || next.roomId != roomId) continue;
        final client = _party.myId;
        bool isCurrent() =>
            inRoom &&
            _party.connected &&
            _party.myId == client &&
            next.roomId == roomId &&
            (!isGuest || _party.admitted);
        final music = next.toMusicItem();
        if (isGuest) remoteMusic = music;
        _notify();
        try {
          await player.followRoom(
            music: music,
            playing: next.playing,
            position: (duration) => next.positionAt(
              DateTime.now().millisecondsSinceEpoch,
              duration: duration,
            ),
            isCurrent: isCurrent,
          );
          if (isCurrent()) applied = next;
        } catch (_) {
          if (isCurrent()) {
            BotToast.showText(text: "同步音频失败，应用会在收到下一次状态时重试");
          }
        }
      }
    } finally {
      _following = false;
    }
    if (applied != null && isHost && applied.roomId == roomId) {
      _broadcastNow();
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
        break;
      case PartyNoticeKind.denied:
        BotToast.showText(
          text: "房主没把你加进一起听名单，进不去这个房间",
          duration: const Duration(seconds: 4),
        );
        break;
      case PartyNoticeKind.hostLeft:
        BotToast.showText(
          text: "房主下线了，一起听结束",
          duration: const Duration(seconds: 4),
        );
        break;
      case PartyNoticeKind.blocked:
        // 房主这边：有人在敲门，但不在名单里
        BotToast.showText(
          text: "${_displayName(notice.name)} 想加入，但不在名单里。在「一起听名单」里加上他，他就能进",
          duration: const Duration(seconds: 5),
        );
        break;
    }

    _notify();
  }

  String _displayName(String name) => name.trim().isEmpty ? "好友" : name;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() {
    _broadcastTimer?.cancel();
    _playerStateSub?.cancel();
    _seekSub?.cancel();
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
    // 没登录就没有 UID，房主认不出你，一定会被拒绝
    if (!BiliAuth.instance.isLogin) {
      final logged = await BiliLoginGate.ensureLoggedIn(context);
      if (!logged) {
        if (!mounted) return;
        setState(() {
          busy = false;
          ok = false;
        });
        return;
      }
    }

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
                        ok ? "房主切歌或拖动进度时，你会自动同步" : session.joinHint,
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
