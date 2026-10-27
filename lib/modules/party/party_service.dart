import "dart:async";
import "dart:convert";
import "dart:math";

import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:dio/dio.dart";

/// 一起听同步消息类型
enum PartyMessageType {
  /// 控制端广播当前状态
  state("state"),

  /// 有人加入
  join("join"),

  /// 请求一次状态
  sync("sync"),

  /// 心跳（成员在线）
  ping("ping"),

  /// 成员离开
  bye("bye"),

  /// 房主拒绝某人加入（不在一起听名单里）
  deny("deny");

  const PartyMessageType(this.value);

  final String value;

  static PartyMessageType tryParse(String v) {
    for (final t in values) {
      if (t.value == v) return t;
    }
    return PartyMessageType.state;
  }
}

/// 房间同步状态
class PartyState {
  final PartyMessageType type;
  final String roomId;

  /// 成员随机 ID（一次连接一个）
  final String from;

  /// 成员的 B 站 UID（未登录为 0）
  final int uid;
  final String fromName;

  /// 当前歌曲
  final String musicId;
  final String origin;
  final String name;
  final String author;
  final String cover;
  final int duration;

  /// 播放位置（毫秒）
  final int position;

  /// 是否正在播放
  final bool playing;

  /// 状态发出的本机时间戳（毫秒）
  final int at;

  /// 有控制权的人（房主 + 被点红心的名单成员）
  final List<int> controlUids;

  /// 定向消息的接收者 UID（0 表示广播）
  final int toUid;

  const PartyState({
    required this.type,
    required this.roomId,
    required this.from,
    this.uid = 0,
    this.fromName = "",
    this.musicId = "",
    this.origin = "bili",
    this.name = "",
    this.author = "",
    this.cover = "",
    this.duration = 0,
    this.position = 0,
    this.playing = false,
    required this.at,
    this.controlUids = const [],
    this.toUid = 0,
  });

  MusicItem? toMusicItem() {
    if (musicId.isEmpty) return null;
    return MusicItem(
      id: musicId,
      cover: cover,
      name: name,
      duration: duration,
      author: author,
      origin: OriginType.getByValue(origin),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "ty": type.value,
      "r": roomId,
      "f": from,
      "u": uid,
      "fn": fromName,
      "i": musicId,
      "o": origin,
      "n": name,
      "a": author,
      "c": cover,
      "d": duration,
      "p": position,
      "pl": playing ? 1 : 0,
      "at": at,
      "cc": controlUids,
      "to": toUid,
    };
  }

  factory PartyState.fromJson(Map<String, dynamic> json) {
    final cc = json["cc"];
    return PartyState(
      type: PartyMessageType.tryParse("${json["ty"]}"),
      roomId: "${json["r"] ?? ""}",
      from: "${json["f"] ?? ""}",
      uid: json["u"] is int ? json["u"] : int.tryParse("${json["u"] ?? 0}") ?? 0,
      fromName: "${json["fn"] ?? ""}",
      musicId: "${json["i"] ?? ""}",
      origin: "${json["o"] ?? "bili"}",
      name: "${json["n"] ?? ""}",
      author: "${json["a"] ?? ""}",
      cover: "${json["c"] ?? ""}",
      duration: json["d"] is int ? json["d"] : 0,
      position: json["p"] is int ? json["p"] : 0,
      playing: json["pl"] == 1,
      at: json["at"] is int ? json["at"] : 0,
      controlUids: cc is List
          ? cc.whereType<num>().map((e) => e.toInt()).toList()
          : const [],
      toUid: json["to"] is int ? json["to"] : 0,
    );
  }
}

/// 一起听角色
enum PartyRole { none, host, guest }

/// 房间里的动态（用来弹提示、放音效）
enum PartyNoticeKind {
  /// 有人进来了
  joined,

  /// 有人退出了
  left,

  /// 房主没让进（不在名单里）
  denied,

  /// 房主下线，房间结束
  hostLeft,
}

class PartyNotice {
  final PartyNoticeKind kind;
  final String name;

  const PartyNotice({required this.kind, this.name = ""});
}

/// 基于 ntfy.sh 公共推送服务的「一起听」同步
///
/// 权限模型：
/// - 只有房主「一起听名单」里的人能加入（房主本地校验 UID）
/// - 名单里点过红心的人 = 共管，可以换歌 / 拖进度
/// - 其他人只能听，本地播放控制会被锁住，想自己操作必须先退出房间
class PartyService {
  /// 中继服务地址（可自行替换为自建 ntfy 实例）
  static const String relayBase = "https://ntfy.sh";

  static final PartyService instance = PartyService._();

  PartyService._();

  /// 房主多久没动静就认为下线了
  static const int hostTimeoutMs = 45000;

  /// 成员多久没心跳就认为掉线了
  ///
  /// 心跳 10 秒一次，容忍丢两次；太长会在房主那边留下"幽灵成员"。
  static const int memberTimeoutMs = 25000;

  PartyRole role = PartyRole.none;
  String roomId = "";
  String myId = "";
  String myName = "";
  int myUid = 0;
  int hostUid = 0;
  bool connected = false;

  /// 在线成员（clientId -> 名字）
  final Map<String, String> members = {};
  final Map<String, int> _memberUids = {};
  final Map<String, int> _memberSeen = {};

  /// 有控制权的 UID（房主广播下来）
  final Set<int> controlUids = {};

  /// 成员 clientId -> B 站 UID（用来在成员列表里标出谁是共管）
  Map<String, int> get memberUids => Map.unmodifiable(_memberUids);

  /// 房主：谁被允许进房间（来自一起听名单）
  final Set<int> allowedUids = {};

  /// 正在应用远端状态时不要拦截本机播放控制
  bool applyingRemote = false;

  final _stateController = StreamController<PartyState>.broadcast();
  final _membersController = StreamController<Map<String, String>>.broadcast();
  final _noticeController = StreamController<PartyNotice>.broadcast();

  Stream<PartyState> get states => _stateController.stream;
  Stream<Map<String, String>> get membersStream => _membersController.stream;
  Stream<PartyNotice> get notices => _noticeController.stream;

  /// 房主需要广播状态时（被请求 / 名单变化）的回调
  ///
  /// [force] 为 true 时表示「就算现在没在放歌也要回一条」——
  /// 新成员加入时必须这样，否则他拿不到 controlUids，
  /// 名单里点了红心的共管会一直被锁着。
  void Function(bool force)? onSyncRequested;

  /// 连接状态变化
  void Function(bool connected)? onConnectionChanged;

  CancelToken? _cancelToken;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _pruneTimer;
  Timer? _reconnectTimer;
  int _lastHostSeen = 0;
  String _buf = "";

  bool get inRoom => role != PartyRole.none;

  bool get isHost => role == PartyRole.host;

  bool get isGuest => role == PartyRole.guest;

  /// 本机能不能自己换歌 / 拖进度
  ///
  /// 房主永远可以；被点红心的共管也可以；普通听众不行。
  bool get allowLocalControl {
    if (applyingRemote) return true;
    if (role != PartyRole.guest) return true;
    return controlUids.contains(myUid);
  }

  /// 当前是否处于「只能听」的状态
  bool get isLocked => inRoom && isGuest && !allowLocalControl;

  static String genRoomId() {
    final rnd = Random.secure();
    return "${rnd.nextInt(900000) + 100000}";
  }

  static String genClientId() {
    final rnd = Random.secure();
    return "${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${rnd.nextInt(9999)}";
  }

  /// 从房间号里解析房主 UID（房间号形如 bili_123456）
  static int hostUidFromRoom(String id) {
    final text = id.trim();
    if (!text.startsWith("bili_")) return 0;
    return int.tryParse(text.substring(5)) ?? 0;
  }

  /// topic 名（加前缀避免与其它人冲突）
  String get topic => "manman_party_$roomId";

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      // 不设 receiveTimeout：订阅流本来就可能几十秒没消息，
      // 一旦超时断开就会陷入「连接中 → 断 → 重连」的死循环
      receiveTimeout: null,
      headers: {"User-Agent": "manman-music/party"},
      validateStatus: (_) => true,
      responseType: ResponseType.stream,
    ),
  );

  final Dio _pubDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      validateStatus: (_) => true,
    ),
  );

  void _readIdentity() {
    final auth = BiliAuth.instance;
    myUid = auth.isLogin ? auth.mid : 0;
    myName = auth.isLogin && auth.uname.isNotEmpty ? auth.uname : "我";
  }

  /// 房主开房
  ///
  /// [allowed] 是允许进房间的 UID 列表（一起听名单），
  /// [controllers] 是其中有控制权的人（名单里点红心的）。
  Future<bool> createRoom({
    required String name,
    String? id,
    Iterable<int> allowed = const [],
    Iterable<int> controllers = const [],
  }) async {
    _readIdentity();
    if (name.trim().isNotEmpty) myName = name.trim();

    roomId = (id != null && id.trim().isNotEmpty) ? id.trim() : genRoomId();
    role = PartyRole.host;
    myId = genClientId();
    hostUid = myUid;

    members.clear();
    _memberUids.clear();
    _memberSeen.clear();

    allowedUids
      ..clear()
      ..addAll(allowed.where((e) => e > 0));
    controlUids
      ..clear()
      ..addAll(controllers.where((e) => e > 0));
    if (myUid > 0) {
      allowedUids.add(myUid);
      controlUids.add(myUid);
    }

    return _connect();
  }

  /// 更新房主的名单 / 共管名单（改了名单后立刻生效）
  void updatePermissions({
    required Iterable<int> allowed,
    required Iterable<int> controllers,
  }) {
    if (!isHost) return;

    allowedUids
      ..clear()
      ..addAll(allowed.where((e) => e > 0));
    controlUids
      ..clear()
      ..addAll(controllers.where((e) => e > 0));
    if (myUid > 0) {
      allowedUids.add(myUid);
      controlUids.add(myUid);
    }

    // 把被移出名单的人请出去
    final kicked = _memberUids.entries
        .where((e) => !allowedUids.contains(e.value))
        .map((e) => e.key)
        .toList();
    for (final clientId in kicked) {
      final uid = _memberUids[clientId] ?? 0;
      members.remove(clientId);
      _memberUids.remove(clientId);
      _memberSeen.remove(clientId);
      if (uid > 0) _publish(PartyMessageType.deny, toUid: uid);
    }
    if (kicked.isNotEmpty) _emitMembers();

    // 权限变了立刻广播：新点红心的人不用等房主下次切歌
    _broadcastNow(force: true);
  }

  /// 作为听众加入别人的房间
  Future<bool> joinRoom({required String id, required String name}) async {
    _readIdentity();
    if (name.trim().isNotEmpty) myName = name.trim();

    // 已经在自己的房间里就先退出（发 bye，别让房间里的人干等）
    if (inRoom) await leaveRoom();

    roomId = id.trim();
    role = PartyRole.guest;
    myId = genClientId();
    hostUid = hostUidFromRoom(roomId);

    members.clear();
    _memberUids.clear();
    _memberSeen.clear();
    controlUids.clear();
    allowedUids.clear();
    _lastHostSeen = DateTime.now().millisecondsSinceEpoch;

    final ok = await _connect();
    if (!ok) return false;

    _publish(PartyMessageType.join);
    // 稍等让房主收到 join，再请求一次完整状态
    await Future.delayed(const Duration(milliseconds: 400));
    _publish(PartyMessageType.sync);
    return true;
  }

  Future<bool> _connect() async {
    await _disconnect();

    final token = CancelToken();
    _cancelToken = token;
    _buf = "";

    try {
      final resp = await _dio.get<ResponseBody>(
        "$relayBase/$topic/json",
        cancelToken: token,
        options: Options(
          headers: {"Accept": "application/json"},
          responseType: ResponseType.stream,
        ),
      );

      // 被中继限流了：退到最长间隔再试，越急越连不上
      if (resp.statusCode == 429) {
        _reconnectAttempt = 3;
        _scheduleReconnect();
        return false;
      }

      if (resp.statusCode != 200 || resp.data == null) {
        _scheduleReconnect();
        return false;
      }

      _reconnectAttempt = 0;
      connected = true;
      onConnectionChanged?.call(true);

      _sub = resp.data!.stream.listen(
        _onBytes,
        onDone: _onClosed,
        onError: (_) => _onClosed(),
        cancelOnError: false,
      );

      _startTimers();
      // 重连后听众要重新报个到，房主才知道你还在
      if (isGuest) _publish(PartyMessageType.join);
      return true;
    } catch (_) {
      _scheduleReconnect();
      return false;
    }
  }

  /// 处理 SSE 数据流
  void _onBytes(List<int> bytes) {
    _buf += utf8.decode(bytes, allowMalformed: true);

    // 按行解析 NDJSON（ntfy 的 /json 端点每行一条）
    while (true) {
      final idx = _buf.indexOf("\n");
      if (idx < 0) break;
      final line = _buf.substring(0, idx).trim();
      _buf = _buf.substring(idx + 1);
      if (line.isEmpty) continue;
      _handleLine(line);
    }
  }

  void _handleLine(String line) {
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return;
      json = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }

    // 只处理 message 事件
    if (json["event"] != null && json["event"] != "message") return;

    final message = json["message"];
    if (message is! String || message.isEmpty) return;

    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) return;
      payload = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }

    final state = PartyState.fromJson(payload);
    if (state.roomId != roomId) return;
    if (state.from == myId) return;
    if (state.toUid != 0 && state.toUid != myUid) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // 房主发的任何消息都算「房主还在」
    if (hostUid > 0 && state.uid == hostUid) _lastHostSeen = now;

    switch (state.type) {
      case PartyMessageType.deny:
        // 只认发给自己的拒绝（toUid 为空的是广播，别跟着瞎退）
        if (myUid <= 0 || state.toUid != myUid) return;
        _emitNotice(PartyNotice(kind: PartyNoticeKind.denied, name: state.fromName));
        Future.microtask(() => leaveRoom(silent: true));
        return;

      case PartyMessageType.bye:
        final wasHost = hostUid > 0 && state.uid == hostUid;
        _removeMember(state.from);
        _removeMemberByUid(state.uid);
        if (wasHost) {
          _emitNotice(PartyNotice(kind: PartyNoticeKind.hostLeft, name: state.fromName));
          Future.microtask(() => leaveRoom(silent: true));
        } else {
          _emitNotice(PartyNotice(kind: PartyNoticeKind.left, name: state.fromName));
        }
        return;

      case PartyMessageType.join:
        if (isHost) {
          // 认不出是谁（没登录）就直接不理，避免误伤其他听众
          if (state.uid <= 0) return;
          // 名单外的人不许进
          if (!allowedUids.contains(state.uid)) {
            _publish(PartyMessageType.deny, toUid: state.uid);
            return;
          }
          final isNew = _touchMember(state.from, state.uid, state.fromName);
          // 断线重连会再发一次 join，别重复弹「加入了一起听」
          if (isNew) {
            _emitNotice(
              PartyNotice(kind: PartyNoticeKind.joined, name: state.fromName),
            );
          }
          // 必须回一条，哪怕房主现在没在放歌：
          // 新成员要靠这条消息拿到 controlUids（红心共管）。
          _broadcastNow(force: true);
          return;
        }
        _touchMember(state.from, state.uid, state.fromName);
        _emitNotice(PartyNotice(kind: PartyNoticeKind.joined, name: state.fromName));
        return;

      case PartyMessageType.ping:
        if (state.from.isNotEmpty) {
          _touchMember(state.from, state.uid, state.fromName);
        }
        if (isGuest && state.controlUids.isNotEmpty) {
          _applyControlList(state.controlUids);
        }
        return;

      case PartyMessageType.sync:
        if (!isHost) return;
        if (state.uid > 0 && !allowedUids.contains(state.uid)) {
          _publish(PartyMessageType.deny, toUid: state.uid);
          return;
        }
        if (state.uid <= 0) return;
        if (state.from.isNotEmpty) {
          _touchMember(state.from, state.uid, state.fromName);
        }
        _broadcastNow(force: true);
        return;

      case PartyMessageType.state:
        if (state.from.isNotEmpty) {
          _touchMember(state.from, state.uid, state.fromName);
        }

        if (isGuest) {
          _applyControlList(state.controlUids);
          // 只有控制端的状态才跟随
          if (!state.controlUids.contains(state.uid)) return;
        } else {
          // 房主只跟随「有控制权的人」（共管）
          if (!controlUids.contains(state.uid)) return;
        }

        if (!_stateController.isClosed) _stateController.add(state);
        return;
    }
  }

  void _applyControlList(List<int> uids) {
    if (uids.isEmpty) return;
    controlUids
      ..clear()
      ..addAll(uids);
  }

  /// 记录一个成员
  ///
  /// 同一个 UID 换了连接（断线重连、切网、重进房间）时，
  /// 旧 clientId 的记录要顶掉，否则房主会看到好几个同名的人。
  /// 返回 true 表示这是一个之前没出现过的人。
  bool _touchMember(String clientId, int uid, String name) {
    if (clientId.isEmpty) return false;

    var isNew = !members.containsKey(clientId);
    var changed = false;

    if (uid > 0) {
      final stale = _memberUids.entries
          .where((e) => e.value == uid && e.key != clientId)
          .map((e) => e.key)
          .toList();
      for (final old in stale) {
        members.remove(old);
        _memberUids.remove(old);
        _memberSeen.remove(old);
        isNew = false;
        changed = true;
      }
    }

    if (!members.containsKey(clientId)) changed = true;
    members[clientId] = name.isEmpty ? "好友" : name;
    if (uid > 0) _memberUids[clientId] = uid;
    _memberSeen[clientId] = DateTime.now().millisecondsSinceEpoch;

    if (changed) _emitMembers();
    return isNew;
  }

  /// 按 UID 移除（bye 里的 clientId 对不上时兜底）
  void _removeMemberByUid(int uid) {
    if (uid <= 0) return;
    final hits = _memberUids.entries
        .where((e) => e.value == uid)
        .map((e) => e.key)
        .toList();
    for (final id in hits) {
      members.remove(id);
      _memberUids.remove(id);
      _memberSeen.remove(id);
    }
    if (hits.isNotEmpty) _emitMembers();
  }

  void _removeMember(String clientId) {
    final removed = members.remove(clientId) != null;
    _memberUids.remove(clientId);
    _memberSeen.remove(clientId);
    if (removed) _emitMembers();
  }

  void _emitMembers() {
    if (!_membersController.isClosed) {
      _membersController.add(Map.from(members));
    }
  }

  void _emitNotice(PartyNotice notice) {
    if (!_noticeController.isClosed) _noticeController.add(notice);
  }

  void _onClosed() {
    final wasConnected = connected;
    connected = false;
    if (wasConnected) onConnectionChanged?.call(false);
    _pingTimer?.cancel();
    _pruneTimer?.cancel();
    if (role != PartyRole.none) _scheduleReconnect();
  }

  Future<void> _disconnect() async {
    _pingTimer?.cancel();
    _pruneTimer?.cancel();
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
    _cancelToken?.cancel();
    _cancelToken = null;
    _buf = "";
    connected = false;
  }

  /// 连续重连次数，用来做退避
  int _reconnectAttempt = 0;

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (role == PartyRole.none) return;

    _reconnectAttempt += 1;
    // 4s → 8s → 16s → 20s：网络差的时候别一直捶中继（会被限流）
    final shift = (_reconnectAttempt - 1).clamp(0, 3);
    final seconds = (4 * (1 << shift)).clamp(4, 20);

    _reconnectTimer = Timer(Duration(seconds: seconds), () async {
      if (role == PartyRole.none) return;
      await _connect();
    });
  }

  void _startTimers() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _publish(PartyMessageType.ping);
    });

    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _pruneMembers();

      // 听众：房主很久没动静 → 房间已经结束了
      if (isGuest && _lastHostSeen > 0) {
        final silent = DateTime.now().millisecondsSinceEpoch - _lastHostSeen;
        if (silent > hostTimeoutMs) {
          _emitNotice(const PartyNotice(kind: PartyNoticeKind.hostLeft));
          Future.microtask(() => leaveRoom(silent: true));
        }
      }
    });
  }

  /// 广播播放状态
  ///
  /// [music] 可以为空：房主暂时没放歌时也要能把 controlUids 发出去，
  /// 否则刚加入的共管会以为自己没有权限。
  void broadcast({
    MusicItem? music,
    Duration position = Duration.zero,
    bool playing = false,
  }) {
    _publish(
      PartyMessageType.state,
      music: music,
      position: position.inMilliseconds,
      playing: playing,
    );
  }

  void _broadcastNow({bool force = false}) {
    onSyncRequested?.call(force);
  }

  /// 发布一条消息
  Future<void> _publish(
    PartyMessageType type, {
    MusicItem? music,
    int position = 0,
    bool playing = false,
    int toUid = 0,
  }) async {
    if (!connected || roomId.isEmpty) return;

    final state = PartyState(
      type: type,
      roomId: roomId,
      from: myId,
      uid: myUid,
      fromName: myName,
      musicId: music?.id ?? "",
      origin: music?.origin.value ?? "bili",
      name: music?.name ?? "",
      author: music?.author ?? "",
      cover: music?.cover ?? "",
      duration: music?.duration ?? 0,
      position: position,
      playing: playing,
      at: DateTime.now().millisecondsSinceEpoch,
      controlUids: controlUids.toList(),
      toUid: toUid,
    );

    try {
      await _pubDio.post<String>(
        "$relayBase/$topic",
        data: jsonEncode(state.toJson()),
        options: Options(
          contentType: "text/plain",
          headers: {"User-Agent": "manman-music/party"},
        ),
      );
    } catch (_) {
      // 单条失败无需处理，下一次心跳会自动补上
    }
  }

  /// 清理超时没心跳的成员
  void _pruneMembers() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stale = _memberSeen.entries
        .where((e) => now - e.value > memberTimeoutMs)
        .map((e) => e.key)
        .toList();
    if (stale.isEmpty) return;

    for (final id in stale) {
      members.remove(id);
      _memberUids.remove(id);
      _memberSeen.remove(id);
    }
    _emitMembers();
  }

  /// 退出 / 下线
  ///
  /// [silent] 为 true 时不发 bye（被踢、房主已走这类情况没必要再喊一声）。
  Future<void> leaveRoom({bool silent = false}) async {
    if (inRoom && connected && !silent) {
      await _publish(PartyMessageType.bye);
      // 给这条 bye 一点时间发出去
      await Future.delayed(const Duration(milliseconds: 120));
    }

    role = PartyRole.none;
    roomId = "";
    hostUid = 0;
    members.clear();
    _memberUids.clear();
    _memberSeen.clear();
    controlUids.clear();
    allowedUids.clear();
    _lastHostSeen = 0;

    if (!_membersController.isClosed) _membersController.add({});

    await _disconnect();
    onConnectionChanged?.call(false);
  }

  void dispose() {
    _pingTimer?.cancel();
    _pruneTimer?.cancel();
    _reconnectTimer?.cancel();
    _stateController.close();
    _membersController.close();
    _noticeController.close();
    _disconnect();
  }

  /// 探测某房间最近是否有人在听（一次性拉取，不建长连接）
  ///
  /// 用 ntfy 的 poll 参数只拿最近 60 秒的历史消息，避免长连接开销，
  /// 也不会对免费公共中继造成压力。
  /// 如果房主发过 bye，就认为房间已经关了，返回 null。
  Future<PartyProbe?> probeRoom(String targetRoom) async {
    if (targetRoom.trim().isEmpty) return null;
    final targetTopic = "manman_party_${targetRoom.trim()}";

    try {
      final resp = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          validateStatus: (_) => true,
          responseType: ResponseType.plain,
          headers: {"User-Agent": "manman-music/party"},
        ),
      ).get<String>("$relayBase/$targetTopic/json?poll=1&since=60s");

      if (resp.statusCode != 200) return null;
      final text = resp.data ?? "";
      if (text.isEmpty) return null;

      PartyProbe? latest;
      int lastByeAt = 0;

      for (final line in text.split("\n")) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        Map<String, dynamic> json;
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is! Map) continue;
          json = Map<String, dynamic>.from(decoded);
        } catch (_) {
          continue;
        }

        if (json["event"] != null && json["event"] != "message") continue;

        final message = json["message"];
        if (message is! String || message.isEmpty) continue;

        Map<String, dynamic> payload;
        try {
          final decoded = jsonDecode(message);
          if (decoded is! Map) continue;
          payload = Map<String, dynamic>.from(decoded);
        } catch (_) {
          continue;
        }

        final state = PartyState.fromJson(payload);
        if (state.roomId != targetRoom.trim()) continue;

        if (state.type == PartyMessageType.bye) {
          if (state.at > lastByeAt) lastByeAt = state.at;
          continue;
        }

        if (state.type != PartyMessageType.state) continue;
        if (state.musicId.isEmpty) continue;

        // 只保留最新的一条
        if (latest == null || state.at > latest.at) {
          latest = PartyProbe(
            nick: state.fromName,
            musicName: state.name,
            author: state.author,
            cover: state.cover,
            playing: state.playing,
            at: state.at,
          );
        }
      }

      // 房主已经说了拜拜
      if (latest != null && lastByeAt > latest.at) return null;

      return latest;
    } catch (_) {
      return null;
    }
  }
}

/// 房间探测结果
class PartyProbe {
  final String nick;
  final String musicName;
  final String author;
  final String cover;
  final bool playing;

  /// 对方发出状态的本机时间戳（毫秒）
  final int at;

  const PartyProbe({
    required this.nick,
    required this.musicName,
    this.author = "",
    this.cover = "",
    this.playing = true,
    required this.at,
  });

  /// 超过这个时长没更新就当作没在听
  bool get isFresh => DateTime.now().millisecondsSinceEpoch - at < 60000;
}
