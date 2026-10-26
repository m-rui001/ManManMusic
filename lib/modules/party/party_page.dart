import "dart:async";

import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/party/party_service.dart";
import "package:bobomusic/modules/player/model.dart";
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
  StreamSubscription? _refreshSub;

  bool get isHost => _party.role == PartyRole.host;
  bool get inRoom => _party.role != PartyRole.none;
  bool get connected => _party.connected;
  String get roomId => _party.roomId;
  Map<String, String> get members => _party.members;
  Stream<Map<String, String>> get memberStream => _party.memberStream;

  /// 最近一次收到的远端歌曲
  MusicItem? remoteMusic;

  void attach(PlayerModel player) {
    _player = player;

    _stateSub?.cancel();
    _stateSub = _party.states.listen(_onRemoteState);

    _party.onSyncRequested = () {
      if (isHost) _broadcastNow();
    };

    // 本机切歌立刻广播，避免等下一次 tick
    _refreshSub?.cancel();
    _refreshSub = eventBus.on<RefreshPlayerCard>().listen((_) {
      if (isHost) _broadcastNow();
    });
  }

  /// 加入房间后开始周期广播（仅房主）
  void startBroadcasting() {
    _broadcastTimer?.cancel();
    if (!isHost) return;
    _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _broadcastNow();
    });
    _broadcastNow();
  }

  void _broadcastNow() {
    final player = _player;
    final music = player?.current;
    if (player == null || music == null) return;
    if (!isHost || !_party.connected) return;
    _party.broadcast(
      music: music,
      position: player.currentPosition,
      playing: player.isPlaying,
    );
  }

  void _onRemoteState(PartyState state) {
    // 房主不跟随任何人
    if (isHost) return;

    final player = _player;
    if (player == null) return;

    if (state.type == PartyMessageType.join) {
      BotToast.showText(text: "${state.fromName} 加入了一起听");
      return;
    }

    if (state.type == PartyMessageType.ping) return;

    final music = state.toMusicItem();
    if (music == null) return;

    final current = player.current;
    final sameMusic = current != null && current.id == music.id;

    // 补偿网络延迟
    final elapsed = state.at > 0
        ? DateTime.now().millisecondsSinceEpoch - state.at
        : 0;
    var target = Duration(milliseconds: state.position + elapsed);
    final total = Duration(seconds: music.duration);
    if (total > Duration.zero && target > total) target = total;

    if (!sameMusic) {
      remoteMusic = music;
      player.play(music: music).then((_) {
        Future.delayed(const Duration(milliseconds: 700), () {
          player.seek(target);
          if (!state.playing) player.pause();
        });
      });
      BotToast.showText(text: "已同步：${music.name}");
      return;
    }

    // 同一首歌：偏差超过 1.5 秒才纠正，避免抖动
    final drift = (player.currentPosition - target).abs();
    if (drift.inMilliseconds > 1500) {
      player.seek(target);
    }

    if (state.playing && !player.isPlaying) {
      player.play();
    } else if (!state.playing && player.isPlaying) {
      player.pause();
    }
  }

  Future<void> leave() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    remoteMusic = null;
    await _party.leaveRoom();
  }
}

/// 一起听面板（设置页入口）
class PartyPage extends StatefulWidget {
  const PartyPage({super.key});

  @override
  State<PartyPage> createState() => _PartyPageState();
}

class _PartyPageState extends State<PartyPage> {
  final _roomCtrl = TextEditingController();
  final PartySession session = PartySession.instance;
  StreamSubscription<Map<String, String>>? _sub;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _sub = session.memberStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _roomCtrl.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    setState(() => busy = true);
    final ok = await PartyService.instance.createRoom(name: "房主");
    if (ok) session.startBroadcasting();
    if (!mounted) return;
    setState(() => busy = false);
    BotToast.showText(
      text: ok ? "房间已创建：${session.roomId}" : "创建失败，请检查网络",
    );
  }

  Future<void> _joinRoom() async {
    final id = _roomCtrl.text.trim();
    if (id.length < 4) {
      BotToast.showText(text: "请输入正确的房间号");
      return;
    }

    setState(() => busy = true);
    final ok = await PartyService.instance.joinRoom(id: id, name: "听众");
    if (!mounted) return;
    setState(() => busy = false);
    BotToast.showText(text: ok ? "已加入房间 $id" : "加入失败，请检查网络");
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final player = Provider.of<PlayerModel>(context);

    return Scaffold(
      appBar: AppBar(title: const Text("一起听", style: TextStyle(fontSize: 18))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.headphones, size: 18, color: primaryColor),
                        const SizedBox(width: 8),
                        const Text(
                          "和朋友听同一首歌",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "不需要注册、也不需要自建服务器：创建房间后把 6 位房间号发给好友，"
                      "对方输入房间号即可同步播放。房主切歌、暂停、拖动进度，好友会自动跟随。",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (!session.inRoom)
                ..._buildJoinArea(primaryColor)
              else
                ..._buildRoomArea(primaryColor, player),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildJoinArea(Color primaryColor) {
    return [
      ElevatedButton.icon(
        onPressed: busy ? null : _createRoom,
        icon: const Icon(Icons.add, size: 18),
        label: const Text("创建房间（我做房主）"),
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(44),
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              "或者",
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _roomCtrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: "输入好友的房间号",
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: busy ? null : _joinRoom,
        icon: const Icon(Icons.login, size: 18),
        label: const Text("加入房间"),
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          minimumSize: const Size.fromHeight(44),
        ),
      ),
    ];
  }

  List<Widget> _buildRoomArea(Color primaryColor, PlayerModel player) {
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  session.connected
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  size: 18,
                  color: session.connected ? primaryColor : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  session.isHost ? "房主" : "听众",
                  style: const TextStyle(fontSize: 13),
                ),
                const Spacer(),
                Text(
                  session.connected ? "已连接" : "连接中…",
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              session.roomId,
              style: TextStyle(
                fontSize: 32,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "把房间号发给好友，对方在「一起听」里输入即可",
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text("在线成员：", style: TextStyle(fontSize: 11)),
                Text(
                  "${session.members.length + 1} 人",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _MemberChip(
                  name: session.isHost ? "我（房主）" : "我",
                  color: primaryColor,
                ),
                ...session.members.entries.map(
                  (e) => _MemberChip(
                    name: e.value.isEmpty ? "好友" : e.value,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            if (player.current != null) ...[
              const SizedBox(height: 14),
              Text(
                "当前：${player.current!.name}",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () async {
          await session.leave();
          if (mounted) setState(() {});
        },
        icon: const Icon(Icons.logout, size: 18),
        label: const Text("退出房间"),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.redAccent,
          minimumSize: const Size.fromHeight(44),
        ),
      ),
    ];
  }
}

class _MemberChip extends StatelessWidget {
  final String name;
  final Color color;

  const _MemberChip({required this.name, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(name, style: TextStyle(fontSize: 10, color: color)),
    );
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
    ok = await PartyService.instance.joinRoom(
      id: widget.roomId.trim(),
      name: "听众",
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) {
      BotToast.showText(text: "已加入房间 ${widget.roomId}");
    } else {
      BotToast.showText(text: "加入失败，请检查网络");
    }
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
                            : "请检查网络后重试，或让好友重新发送邀请",
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
