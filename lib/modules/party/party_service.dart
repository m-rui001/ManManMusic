import "dart:async";
import "dart:convert";
import "dart:math";

import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:dio/dio.dart";
import "package:flutter/foundation.dart";

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
  final String toClient;
  final int receivedAt;

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
    this.toClient = "",
    this.receivedAt = 0,
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
      if (toClient.isNotEmpty) "tc": toClient,
    };
  }

  factory PartyState.fromJson(Map<String, dynamic> json, {int receivedAt = 0}) {
    final cc = json["cc"];
    return PartyState(
      type: PartyMessageType.tryParse("${json["ty"]}"),
      roomId: "${json["r"] ?? ""}",
      from: "${json["f"] ?? ""}",
      uid:
          json["u"] is int ? json["u"] : int.tryParse("${json["u"] ?? 0}") ?? 0,
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
      toClient: "${json["tc"] ?? ""}",
      receivedAt: receivedAt,
    );
  }

  Duration positionAt(int now, {Duration? duration}) {
    // 只用本机计时补偿取流耗时，避免把房主手机的时钟偏差算进进度。
    final elapsed = playing && receivedAt > 0 ? max(0, now - receivedAt) : 0;
    final target = Duration(milliseconds: max(0, position + elapsed));
    return duration != null && duration > Duration.zero && target > duration
        ? duration
        : target;
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

  /// 房主这边发现有人想进房间但不在名单里
  blocked,
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
  final String relayBase;
  final int? _testUid;

  static final PartyService instance = PartyService._();

  PartyService._()
      : relayBase = "https://ntfy.sh",
        _testUid = null;

  @visibleForTesting
  PartyService.withRelay(this.relayBase, int uid) : _testUid = uid;

  /// 房主多久没动静就认为下线了
  ///
  static const int hostTimeoutMs = 95000;

  /// 成员多久没心跳就认为掉线了
  ///
  static const int memberTimeoutMs = 95000;

  PartyRole role = PartyRole.none;
  String roomId = "";
  String myId = "";
  String myName = "";
  int myUid = 0;
  int hostUid = 0;
  bool connected = false;
  bool admitted = false;
  String joinHint = "";
  Completer<bool>? _admission;
  String _hostClient = "";
  final Map<String, int> _lastStateAt = {};

  /// 连不上时给用户看的原因，别让人干等着「连接中…」
  String connectionHint = "";

  /// 连续失败次数
  int _connectAttempts = 0;

  /// 正在连接（防止 onClosed 和重连定时器同时再连一条）
  bool _connecting = false;

  /// 连接代数：只有最新一条订阅流的关闭才算掉线，
  /// 主动断开时旧流迟到的 onDone / onError 不能触发重连
  int _connGen = 0;

  /// 正在探测中继是否可达
  bool _diagnosing = false;

  /// 被中继限流后暂停发布到这个时间点（毫秒）
  int _publishPausedUntil = 0;

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

  /// 已经提示过「被名单拦下」的 UID（重连会反复敲门，别反复弹）
  final Set<int> _deniedUids = {};

  final _stateController = StreamController<PartyState>.broadcast();
  final _membersController = StreamController<Map<String, String>>.broadcast();
  final _noticeController = StreamController<PartyNotice>.broadcast();

  Stream<PartyState> get states => _stateController.stream;
  Stream<Map<String, String>> get membersStream => _membersController.stream;
  Stream<PartyNotice> get notices => _noticeController.stream;

  /// 房主回复指定听众，或定期向房间广播播放快照。
  void Function({String toClient, int toUid})? onSyncRequested;

  /// 连接状态变化
  void Function(bool connected)? onConnectionChanged;

  CancelToken? _cancelToken;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _pruneTimer;
  Timer? _reconnectTimer;
  int _lastHostSeen = 0;

  bool get inRoom => role != PartyRole.none;

  bool get isHost => role == PartyRole.host;

  bool get isGuest => role == PartyRole.guest;

  /// 本机能不能自己换歌 / 拖进度
  ///
  /// 房主永远可以；被点红心的共管也可以；普通听众不行。
  bool get allowLocalControl {
    if (role != PartyRole.guest) return true;
    return admitted && controlUids.contains(myUid);
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
    myUid = _testUid ?? (auth.isLogin ? auth.mid : 0);
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
    _deniedUids.clear();

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

    _resetConnectionState();
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
    onSyncRequested?.call();
  }

  /// 作为听众加入别人的房间
  Future<bool> joinRoom({required String id, required String name}) async {
    if (inRoom) await leaveRoom();
    _readIdentity();
    if (name.trim().isNotEmpty) myName = name.trim();

    joinHint = "";
    hostUid = hostUidFromRoom(id);
    if (myUid <= 0 || hostUid <= 0 || hostUid == myUid) {
      joinHint = "请用哔哩哔哩账号加入好友的房间";
      return false;
    }
    roomId = id.trim();
    role = PartyRole.guest;
    myId = genClientId();
    final client = myId;
    final admission = _admission = Completer<bool>();
    _lastHostSeen = DateTime.now().millisecondsSinceEpoch;
    _resetConnectionState();
    final ready = await _connect();
    if (myId != client || !isGuest) return false;
    final joined = ready &&
        await admission.future
            .timeout(const Duration(seconds: 14), onTimeout: () => false);
    if (!joined && myId == client && isGuest) {
      if (joinHint.isEmpty) {
        joinHint = connectionHint.isNotEmpty
            ? connectionHint
            : "房主未确认加入，请确认房主在线且两端已升级";
      }
      await leaveRoom(silent: true);
    }
    return joined;
  }

  Future<bool> _connect() async {
    if (_connecting || !inRoom) return false;
    _connecting = true;
    final client = myId;
    try {
      await _disconnect();
      if (!inRoom || myId != client) return false;

      final token = CancelToken();
      _cancelToken = token;

      final Response<ResponseBody> resp;
      try {
        resp = await _dio
            .get<ResponseBody>(
              "$relayBase/$topic/json",
              cancelToken: token,
              options: Options(
                headers: {"Accept": "application/json"},
                responseType: ResponseType.stream,
              ),
            )
            // 网络差的时候 TLS 握手 / 等响应头能挂很久，
            // 界面就永远停在「连接中」。这里强制给一个期限。
            .timeout(const Duration(seconds: 15));
      } on TimeoutException {
        token.cancel("connect timeout");
        if (!inRoom || myId != client) return false;
        _fail("连接超时，网络好像不通");
        _scheduleReconnect();
        return false;
      }

      // 被中继限流了：退到最长间隔再试，越急越连不上
      if (token.isCancelled || !inRoom || myId != client) return false;
      if (resp.statusCode == 429) {
        final wait = _retryAfter(resp) ?? 20;
        _fail("中继限流，$wait 秒后自动重连");
        _reconnectAttempt = 3;
        _scheduleReconnect(seconds: wait);
        return false;
      }

      if (resp.statusCode != 200 || resp.data == null) {
        _fail("中继返回 ${resp.statusCode}，正在重试");
        _scheduleReconnect();
        return false;
      }

      final gen = ++_connGen;
      _lastRelayActivity = DateTime.now().millisecondsSinceEpoch;
      _sub = resp.data!.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => _handleLine(line, gen),
            onDone: () => _onClosed(gen),
            onError: (_) => _onClosed(gen),
            cancelOnError: true,
          );
      _reconnectAttempt = 0;
      _connectAttempts = 0;
      connectionHint = "";
      connected = true;
      _startTimers();
      onConnectionChanged?.call(true);
      if (isGuest) {
        unawaited(_publish(PartyMessageType.join));
        _joinRetry = Timer(const Duration(seconds: 5), () {
          if (connected && isGuest && !admitted) {
            unawaited(_publish(PartyMessageType.join));
          }
        });
      }
      return true;
    } catch (_) {
      if (!inRoom || myId != client) return false;
      _fail("连接出错，正在重试");
      _scheduleReconnect();
      return false;
    } finally {
      _connecting = false;
    }
  }

  /// 手动重连：清掉退避立刻再连一次
  Future<bool> retryNow() async {
    if (!inRoom) return false;
    if (_connecting) return connected;
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;
    _connectAttempts = 0;
    connectionHint = "";
    onConnectionChanged?.call(false);
    return _connect();
  }

  void _fail(String hint) {
    connectionHint = hint;
    _connectAttempts += 1;
    connected = false;
    onConnectionChanged?.call(false);
    // 连着几次都不行，确认一下中继是不是压根连不上（限流还是断网）
    if (_connectAttempts >= 3) _diagnoseRelay();
  }

  Future<void> _diagnoseRelay() async {
    if (_diagnosing) return;
    _diagnosing = true;
    try {
      final resp = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          validateStatus: (_) => true,
        ),
      ).get<String>("$relayBase/v1/health");

      if (role == PartyRole.none) return;
      if (resp.statusCode == 200) {
        if (!connectionHint.contains("限流")) connectionHint = "中继正常，正在重连";
      } else {
        connectionHint = "连不上 ntfy.sh（HTTP ${resp.statusCode}），可能要挂代理";
      }
    } catch (_) {
      if (role == PartyRole.none) return;
      connectionHint = "连不上 ntfy.sh，检查网络或代理";
    } finally {
      _diagnosing = false;
      if (role != PartyRole.none) onConnectionChanged?.call(false);
    }
  }

  void _resetConnectionState() {
    connectionHint = "";
    _connectAttempts = 0;
    _reconnectAttempt = 0;
  }

  int? _retryAfter(Response<dynamic> resp) {
    final raw = resp.headers.value("retry-after");
    if (raw == null) return null;
    final secs = int.tryParse(raw.trim());
    if (secs == null) return null;
    return secs.clamp(5, 120).toInt();
  }

  void _handleLine(String line, int gen) {
    if (gen != _connGen || !connected) return;
    _lastRelayActivity = DateTime.now().millisecondsSinceEpoch;
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

    final now = DateTime.now().millisecondsSinceEpoch;
    final state = PartyState.fromJson(payload, receivedAt: now);
    if (state.roomId != roomId || state.from.isEmpty || state.from == myId) {
      return;
    }
    if (state.toUid != 0 && state.toUid != myUid) return;
    if (state.toClient.isNotEmpty && state.toClient != myId) return;

    final fromHost = isGuest && state.uid == hostUid;
    if (fromHost && state.type != PartyMessageType.bye) {
      if (_hostClient.isNotEmpty && _hostClient != state.from) {
        admitted = false;
        controlUids.clear();
        _lastStateAt.clear();
        _lastHostSeen = now;
        unawaited(_publish(PartyMessageType.join));
        onConnectionChanged?.call(true);
      }
      _hostClient = state.from;
      _lastHostSeen = now;
    }
    final allowed = allowedUids.contains(state.uid);
    switch (state.type) {
      case PartyMessageType.deny:
        if (!fromHost || state.toUid != myUid) return;
        joinHint = "房主未将你列入一起听名单";
        _emitNotice(
            PartyNotice(kind: PartyNoticeKind.denied, name: state.fromName));
        unawaited(leaveRoom(silent: true));
        return;

      case PartyMessageType.bye:
        if (fromHost && state.from == _hostClient) {
          _emitNotice(PartyNotice(
              kind: PartyNoticeKind.hostLeft, name: state.fromName));
          unawaited(leaveRoom(silent: true));
        } else if (members.containsKey(state.from)) {
          _removeMember(state.from);
          _emitNotice(
              PartyNotice(kind: PartyNoticeKind.left, name: state.fromName));
        }
        return;

      case PartyMessageType.join:
      case PartyMessageType.sync:
        if (!isHost || state.uid <= 0) return;
        if (!allowed) {
          _publish(PartyMessageType.deny,
              toUid: state.uid, toClient: state.from);
          if (_deniedUids.add(state.uid)) {
            _emitNotice(PartyNotice(
                kind: PartyNoticeKind.blocked, name: state.fromName));
          }
          return;
        }
        if (_touchMember(state.from, state.uid, state.fromName)) {
          _emitNotice(
              PartyNotice(kind: PartyNoticeKind.joined, name: state.fromName));
        }
        onSyncRequested?.call(toClient: state.from, toUid: state.uid);
        return;

      case PartyMessageType.ping:
        if ((isHost && allowed) || (isGuest && admitted)) {
          _touchMember(state.from, state.uid, state.fromName);
        }
        return;

      case PartyMessageType.state:
        if (state.at < (_lastStateAt[state.from] ?? 0)) return;
        if (isGuest) {
          if (!fromHost) return;
          if (!admitted) {
            if (state.toClient != myId || state.toUid != myUid) return;
            admitted = true;
            _joinRetry?.cancel();
            final admission = _admission;
            if (admission != null && !admission.isCompleted) {
              admission.complete(true);
            }
          }
          _applyControlList(state.controlUids);
        } else if (!allowed ||
            !controlUids.contains(state.uid) ||
            _memberUids[state.from] != state.uid) {
          return;
        }
        _lastStateAt[state.from] = state.at;
        _touchMember(state.from, state.uid, state.fromName);
        _stateController.add(state);
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
        _lastStateAt.remove(old);
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

  void _removeMember(String clientId) {
    final removed = members.remove(clientId) != null;
    _memberUids.remove(clientId);
    _memberSeen.remove(clientId);
    _lastStateAt.remove(clientId);
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

  void _onClosed(int gen) {
    if (gen != _connGen) return;
    _connGen++;
    _cancelToken?.cancel();
    _joinRetry?.cancel();
    if (isGuest) admitted = false;
    final wasConnected = connected;
    connected = false;
    if (wasConnected) onConnectionChanged?.call(false);
    _pingTimer?.cancel();
    _pruneTimer?.cancel();
    if (role != PartyRole.none) {
      if (connectionHint.isEmpty) connectionHint = "连接断开，正在重连";
      _scheduleReconnect();
    }
  }

  Future<void> _disconnect() async {
    _joinRetry?.cancel();
    if (isGuest) admitted = false;
    connected = false;
    // 作废旧连接：之后旧流再报 onDone / onError 都不算掉线
    _connGen++;
    _pingTimer?.cancel();
    _pruneTimer?.cancel();
    _reconnectTimer?.cancel();
    // 先取消 token 再取消订阅：订阅流 cancel 有时候会卡着等 socket，
    // 顺序反了会让 _connect 永远停在第一步，表现就是一直「连接中」
    _cancelToken?.cancel();
    _cancelToken = null;
    try {
      await _sub?.cancel().timeout(const Duration(seconds: 2));
    } catch (_) {
      // 卡住就放弃这一条，反正 token 已经取消了
    }
    _sub = null;
    connected = false;
  }

  /// 连续重连次数，用来做退避
  int _reconnectAttempt = 0;

  void _scheduleReconnect({int? seconds}) {
    _reconnectTimer?.cancel();
    if (role == PartyRole.none) return;

    int delay;
    if (seconds != null) {
      delay = seconds;
    } else {
      _reconnectAttempt += 1;
      // 4s → 8s → 16s → 20s：网络差的时候别一直捶中继（会被限流）
      final shift = (_reconnectAttempt - 1).clamp(0, 3);
      delay = (4 * (1 << shift)).clamp(4, 20);
    }

    _reconnectTimer = Timer(Duration(seconds: delay), () async {
      if (role == PartyRole.none) return;
      await _connect();
    });
  }

  Timer? _joinRetry;
  int _lastRelayActivity = 0;

  void _startTimers() {
    _pingTimer?.cancel();
    // 房主的播放快照也承担心跳。
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (isHost) {
        onSyncRequested?.call();
      } else {
        _publish(admitted ? PartyMessageType.ping : PartyMessageType.join);
      }
    });

    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _pruneMembers();
      final now = DateTime.now().millisecondsSinceEpoch;
      if (isGuest && now - _lastHostSeen > hostTimeoutMs) {
        _emitNotice(const PartyNotice(kind: PartyNoticeKind.hostLeft));
        unawaited(leaveRoom(silent: true));
        return;
      }
      if (now - _lastRelayActivity > 90000) _onClosed(_connGen);
    });
  }

  void broadcast({
    MusicItem? music,
    Duration position = Duration.zero,
    bool playing = false,
    String toClient = "",
    int toUid = 0,
  }) {
    _publish(
      PartyMessageType.state,
      music: music,
      position: position.inMilliseconds,
      playing: playing,
      toClient: toClient,
      toUid: toUid,
    );
  }

  /// 发布一条消息
  Future<void> _publish(
    PartyMessageType type, {
    MusicItem? music,
    int position = 0,
    bool playing = false,
    int toUid = 0,
    String toClient = "",
  }) async {
    if (!connected || roomId.isEmpty) return;

    // 刚被限流过：别继续往额度里灌，等它自己回血
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < _publishPausedUntil) return;

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
      toClient: toClient,
    );

    try {
      final resp = await _pubDio.post<String>(
        "$relayBase/$topic",
        data: jsonEncode(state.toJson()),
        options: Options(
          contentType: "text/plain",
          headers: {"User-Agent": "manman-music/party"},
        ),
      );
      if (resp.statusCode == 429 && state.from == myId && inRoom) {
        final wait = _retryAfter(resp) ?? 30;
        _publishPausedUntil =
            DateTime.now().millisecondsSinceEpoch + wait * 1000;
      }
    } catch (_) {
      // 单条失败无需处理，下一次心跳会自动补上
    }
  }

  /// 并发受限地跑一批任务
  ///
  /// ntfy.sh 公共中继按 IP 限流（60 次突发，之后每 5 秒回 1 次），
  /// 探测名单时一把全发出去会把额度瞬间打空，之后建房、发消息都会被 429。
  static Future<void> forEachLimited<T>(
    List<T> items,
    Future<void> Function(T item) task, {
    int limit = 3,
    Duration gap = const Duration(milliseconds: 200),
  }) async {
    if (items.isEmpty) return;
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        final item = items[next++];
        await task(item);
        if (gap > Duration.zero) await Future.delayed(gap);
      }
    }

    final workers = <Future<void>>[];
    for (var i = 0; i < limit && i < items.length; i++) {
      workers.add(worker());
    }
    await Future.wait(workers);
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
      _lastStateAt.remove(id);
    }
    _emitMembers();
  }

  /// 退出 / 下线
  ///
  /// [silent] 为 true 时不发 bye（被踢、房主已走这类情况没必要再喊一声）。
  Future<void> leaveRoom({bool silent = false}) async {
    if (inRoom && connected && !silent) {
      await _publish(PartyMessageType.bye).timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    }

    final admission = _admission;
    if (admission != null && !admission.isCompleted) admission.complete(false);
    _admission = null;
    admitted = false;
    _hostClient = "";
    _lastStateAt.clear();
    role = PartyRole.none;
    roomId = "";
    hostUid = 0;
    members.clear();
    _memberUids.clear();
    _memberSeen.clear();
    _deniedUids.clear();
    controlUids.clear();
    allowedUids.clear();
    _lastHostSeen = 0;
    _resetConnectionState();

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

  /// 探测某房间最近是否还开着（一次性拉取，不建长连接）
  ///
  /// 用 ntfy 的 poll 参数只拿最近两分钟的历史消息。这个窗口是服务端按自己的
  /// 时钟筛的，所以「窗口里有房主的消息」就等于「房间还开着」，不受两台手机
  /// 时间不准的影响。房主没在放歌也算在线：能进房间，只是没有歌可显示。
  /// 如果房主最后一句是 bye，就认为房间已经关了。
  Future<PartyProbe?> probeRoom(String targetRoom) async {
    if (targetRoom.trim().isEmpty) return null;
    final room = targetRoom.trim();
    final targetTopic = "manman_party_$room";

    final resp = await _probeDio.get<String>(
      "$relayBase/$targetTopic/json",
      queryParameters: {"poll": "1", "since": "100s"},
      options: Options(headers: {"Cache-Control": "no-cache"}),
    );
    if (resp.statusCode != 200) {
      throw StateError("中继暂时不可用（HTTP ${resp.statusCode}）");
    }
    return parseProbe(
      (resp.data ?? "").split("\n"),
      room: room,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  final Dio _probeDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 6),
    validateStatus: (_) => true,
    responseType: ResponseType.plain,
    headers: {"User-Agent": "manman-music/party"},
  ));

  /// 从 poll 回来的 NDJSON 里挑出房间状态
  ///
  /// 纯函数，方便单测：窗口是服务端给的（since=100s），
  /// 所以「窗口里有房主的消息」就等于「房间还开着」。
  @visibleForTesting
  static PartyProbe? parseProbe(
    Iterable<String> lines, {
    required String room,
    required int nowMs,
  }) {
    final hostUid = hostUidFromRoom(room);

    PartyState? latestHost;
    PartyState? latestPlayback;
    int relayTime = -1;

    for (final line in lines) {
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
      if (state.roomId != room) continue;
      // 只认房主的消息：房间号里就写着房主 UID
      if (hostUid > 0 && state.uid != hostUid) continue;

      if (state.type != PartyMessageType.state &&
          state.type != PartyMessageType.ping &&
          state.type != PartyMessageType.bye) {
        continue;
      }
      // ntfy 按服务端时间返回历史。同秒内以投递顺序为准。
      final timestamp = json["time"];
      final time = timestamp is num ? timestamp.toInt() : 0;
      if (time < relayTime) continue;
      relayTime = time;
      if (latestHost?.from != state.from ||
          state.type == PartyMessageType.bye) {
        latestPlayback = null;
      }
      if (state.type == PartyMessageType.state) latestPlayback = state;
      latestHost = state;
    }

    if (latestHost == null || latestHost.type == PartyMessageType.bye) {
      return null;
    }
    return PartyProbe(
      nick: latestHost.fromName,
      musicName: latestPlayback?.name ?? "",
      author: latestPlayback?.author ?? "",
      cover: latestPlayback?.cover ?? "",
      playing: latestPlayback?.playing ?? false,
      at: latestPlayback?.at ?? 0,
      seenAt: nowMs,
    );
  }
}

/// 房间探测结果
class PartyProbe {
  final String nick;
  final String musicName;
  final String author;
  final String cover;
  final bool playing;

  /// 房主发出这条状态的时间（房主手机的时钟）
  final int at;

  /// 本机看到房主动静的本地时间（毫秒）
  final int seenAt;

  const PartyProbe({
    required this.nick,
    this.musicName = "",
    this.author = "",
    this.cover = "",
    this.playing = true,
    this.at = 0,
    int? seenAt,
  }) : seenAt = seenAt ?? at;

  /// 知道在放什么歌（只知道房间开着但没在放歌时为 false）
  bool get hasMusic => musicName.isNotEmpty;

  /// 列表中的探测结果最多保留 70 秒。
  bool get isFresh => DateTime.now().millisecondsSinceEpoch - seenAt < 70000;
}
