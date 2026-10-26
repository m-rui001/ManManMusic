import "dart:async";
import "dart:convert";
import "dart:math";

import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:dio/dio.dart";

/// 一起听同步消息类型
enum PartyMessageType {
  /// 房主广播当前状态
  state("state"),

  /// 有人加入
  join("join"),

  /// 请求一次状态
  sync("sync"),

  /// 心跳（成员在线）
  ping("ping"),

  /// 成员离开
  bye("bye");

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

  /// 成员随机 ID
  final String from;
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

  const PartyState({
    required this.type,
    required this.roomId,
    required this.from,
    required this.fromName,
    this.musicId = "",
    this.origin = "bili",
    this.name = "",
    this.author = "",
    this.cover = "",
    this.duration = 0,
    this.position = 0,
    this.playing = false,
    required this.at,
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
    };
  }

  factory PartyState.fromJson(Map<String, dynamic> json) {
    return PartyState(
      type: PartyMessageType.tryParse("${json["ty"]}"),
      roomId: "${json["r"] ?? ""}",
      from: "${json["f"] ?? ""}",
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
    );
  }
}

/// 一起听角色
enum PartyRole { none, host, guest }

/// 基于 ntfy.sh 公共推送服务的「一起听」同步
///
/// 不依赖自建服务器：ntfy.sh 是免费、免注册的公共 pub/sub 服务，
/// 房间号即 topic，客户端用 SSE 订阅、用 HTTP POST 发布。
/// 消息不做持久化（默认缓存 12 小时），也不上传播放历史以外的东西。
class PartyService {
  /// 中继服务地址（可自行替换为自建 ntfy 实例）
  static const String relayBase = "https://ntfy.sh";

  static final PartyService instance = PartyService._();

  PartyService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {"User-Agent": "manman-music/party"},
      validateStatus: (_) => true,
      responseType: ResponseType.stream,
    ),
  );

  PartyRole role = PartyRole.none;
  String roomId = "";
  String myId = "";
  String myName = "";
  bool connected = false;

  /// 在线成员（id -> 名字）
  final Map<String, String> members = {};
  final Map<String, int> _memberSeen = {};

  final _stateController = StreamController<PartyState>.broadcast();
  final _membersController = StreamController<Map<String, String>>.broadcast();

  Stream<PartyState> get states => _stateController.stream;
  Stream<Map<String, String>> get memberStream => _membersController.stream;

  /// 房主收到同步请求时的回调
  void Function()? onSyncRequested;

  /// 连接状态变化
  void Function(bool connected)? onConnectionChanged;

  CancelToken? _cancelToken;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  String _buf = "";

  static String genRoomId() {
    final rnd = Random.secure();
    return "${rnd.nextInt(900000) + 100000}";
  }

  static String genClientId() {
    final rnd = Random.secure();
    return "${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${rnd.nextInt(9999)}";
  }

  /// topic 名（加前缀避免与其它人冲突）
  String get topic => "manman_party_$roomId";

  Future<bool> createRoom({required String name, String? id}) async {
    roomId = (id != null && id.trim().isNotEmpty) ? id.trim() : genRoomId();
    role = PartyRole.host;
    myName = name;
    myId = genClientId();
    members.clear();
    _memberSeen.clear();
    return _connect();
  }

  Future<bool> joinRoom({required String id, required String name}) async {
    roomId = id.trim();
    role = PartyRole.guest;
    myName = name;
    myId = genClientId();
    members.clear();
    _memberSeen.clear();

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

      if (resp.statusCode != 200 || resp.data == null) {
        _scheduleReconnect();
        return false;
      }

      connected = true;
      onConnectionChanged?.call(true);

      _sub = resp.data!.stream.listen(
        _onBytes,
        onDone: _onClosed,
        onError: (_) => _onClosed(),
        cancelOnError: false,
      );

      _startPing();
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

    // 成员表
    if (state.from.isNotEmpty) {
      if (state.type == PartyMessageType.bye) {
        members.remove(state.from);
        _memberSeen.remove(state.from);
      } else {
        members[state.from] = state.fromName;
        _memberSeen[state.from] = DateTime.now().millisecondsSinceEpoch;
      }
      _pruneMembers();
      if (!_membersController.isClosed) {
        _membersController.add(Map.from(members));
      }
    }

    if (state.type == PartyMessageType.sync) {
      if (role == PartyRole.host) onSyncRequested?.call();
      return;
    }

    if (state.type == PartyMessageType.ping) return;

    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  void _onClosed() {
    final wasConnected = connected;
    connected = false;
    if (wasConnected) onConnectionChanged?.call(false);
    _pingTimer?.cancel();
    if (role != PartyRole.none) _scheduleReconnect();
  }

  Future<void> _disconnect() async {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
    _cancelToken?.cancel();
    _cancelToken = null;
    _buf = "";
    connected = false;
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (role == PartyRole.none) return;
    _reconnectTimer = Timer(const Duration(seconds: 4), () async {
      if (role == PartyRole.none) return;
      await _connect();
    });
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _publish(PartyMessageType.ping);
    });
  }

  /// 广播播放状态
  void broadcast({
    required MusicItem music,
    required Duration position,
    required bool playing,
  }) {
    _publish(
      PartyMessageType.state,
      music: music,
      position: position.inMilliseconds,
      playing: playing,
    );
  }

  /// 发布一条消息
  Future<void> _publish(
    PartyMessageType type, {
    MusicItem? music,
    int position = 0,
    bool playing = false,
  }) async {
    if (!connected || roomId.isEmpty) return;

    final state = PartyState(
      type: type,
      roomId: roomId,
      from: myId,
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
    );

    try {
      await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          validateStatus: (_) => true,
        ),
      ).post<String>(
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

  /// 清理 90 秒没动静的成员
  void _pruneMembers() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stale = _memberSeen.entries
        .where((e) => now - e.value > 90000)
        .map((e) => e.key)
        .toList();
    if (stale.isEmpty) return;
    for (final id in stale) {
      members.remove(id);
      _memberSeen.remove(id);
    }
  }

  Future<void> leaveRoom() async {
    if (role != PartyRole.none && connected) {
      await _publish(PartyMessageType.bye);
    }
    role = PartyRole.none;
    roomId = "";
    members.clear();
    _memberSeen.clear();
    if (!_membersController.isClosed) {
      _membersController.add({});
    }
    await _disconnect();
    onConnectionChanged?.call(false);
  }

  void dispose() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _stateController.close();
    _membersController.close();
    _disconnect();
  }
}
