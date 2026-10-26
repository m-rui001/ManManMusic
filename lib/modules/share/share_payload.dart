import "dart:convert";

import "package:bobomusic/origin_sdk/origin_types.dart";

/// 分享出去的载荷类型
enum SharePayloadType {
  /// 单曲
  music("music"),

  /// 一起听房间
  party("party");

  const SharePayloadType(this.value);

  final String value;

  static SharePayloadType? tryParse(String? v) {
    for (final t in values) {
      if (t.value == v) return t;
    }
    return null;
  }
}

/// 分享载荷。整包 base64url 编码后塞进链接，不依赖任何服务器。
class SharePayload {
  final SharePayloadType type;

  /// 歌曲 ID（origin_id_cid 形式）
  final String musicId;
  final String origin;
  final String name;
  final String author;
  final String cover;
  final int duration;

  /// 分享时的播放进度（毫秒），用于「一起听」对齐
  final int position;

  /// 房间号（一起听时存在）
  final String roomId;

  /// 分享者昵称
  final String from;

  const SharePayload({
    required this.type,
    this.musicId = "",
    this.origin = "bili",
    this.name = "",
    this.author = "",
    this.cover = "",
    this.duration = 0,
    this.position = 0,
    this.roomId = "",
    this.from = "",
  });

  factory SharePayload.song({
    required MusicItem music,
    required int position,
    String from = "",
  }) {
    return SharePayload(
      type: SharePayloadType.music,
      musicId: music.id,
      origin: music.origin.value,
      name: music.name,
      author: music.author,
      cover: music.cover,
      duration: music.duration,
      position: position,
      from: from,
    );
  }

  factory SharePayload.party({
    required MusicItem music,
    required int position,
    required String roomId,
    String from = "",
  }) {
    return SharePayload(
      type: SharePayloadType.party,
      musicId: music.id,
      origin: music.origin.value,
      name: music.name,
      author: music.author,
      cover: music.cover,
      duration: music.duration,
      position: position,
      roomId: roomId,
      from: from,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "t": type.value,
      if (musicId.isNotEmpty) "i": musicId,
      if (origin.isNotEmpty) "o": origin,
      if (name.isNotEmpty) "n": name,
      if (author.isNotEmpty) "a": author,
      if (cover.isNotEmpty) "c": cover,
      if (duration > 0) "d": duration,
      if (position > 0) "p": position,
      if (roomId.isNotEmpty) "r": roomId,
      if (from.isNotEmpty) "f": from,
    };
  }

  factory SharePayload.fromJson(Map<String, dynamic> json) {
    return SharePayload(
      type: SharePayloadType.tryParse("${json["t"]}") ?? SharePayloadType.music,
      musicId: "${json["i"] ?? ""}",
      origin: "${json["o"] ?? "bili"}",
      name: "${json["n"] ?? ""}",
      author: "${json["a"] ?? ""}",
      cover: "${json["c"] ?? ""}",
      duration: json["d"] is int ? json["d"] : 0,
      position: json["p"] is int ? json["p"] : 0,
      roomId: "${json["r"] ?? ""}",
      from: "${json["f"] ?? ""}",
    );
  }

  /// 还原成可播放的 [MusicItem]
  MusicItem toMusicItem() {
    return MusicItem(
      id: musicId,
      cover: cover,
      name: name,
      duration: duration,
      author: author,
      origin: OriginType.getByValue(origin),
    );
  }

  /// 编码成链接安全的字符串
  String encode() {
    final raw = utf8.encode(jsonEncode(toJson()));
    return base64Url.encode(raw).replaceAll("=", "");
  }

  /// 从编码还原
  static SharePayload? decode(String code) {
    try {
      var normalized = code.replaceAll("-", "+").replaceAll("_", "/");
      while (normalized.length % 4 != 0) {
        normalized += "=";
      }
      final raw = utf8.decode(base64Decode(normalized));
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      return SharePayload.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }
}

/// 深度链接 scheme
const String manmanScheme = "manman";

/// 网页兜底前缀（无服务器时仅用于拼出可读链接，不一定能打开）
const String manmanWebHost = "manman.music";

/// 生成「满满音乐」自己的分享链接
String buildManmanLink(SharePayload payload) {
  final code = payload.encode();
  return "$manmanScheme://play?d=$code";
}

/// 生成给人看的分享文本（QQ / 微信里点不开自定义 scheme，所以附带说明）
String buildShareText(SharePayload payload) {
  final link = buildManmanLink(payload);
  final who = payload.from.isNotEmpty ? "${payload.from} " : "";

  if (payload.type == SharePayloadType.party) {
    return "🎧 $who邀请你一起听《${payload.name}》\n"
        "打开「满满音乐」→ 设置 → 一起听，输入房间号 ${payload.roomId} 即可同步播放\n"
        "$link";
  }

  return "🎵 $who在「满满音乐」分享了《${payload.name}》"
      "${payload.author.isNotEmpty ? " - ${payload.author}" : ""}\n"
      "复制这条消息打开满满音乐即可播放：\n$link";
}

/// 从任意文本里找出满满音乐链接
String? extractManmanLink(String text) {
  final lower = text.toLowerCase();
  final idx = lower.indexOf("$manmanScheme://");
  if (idx < 0) return null;
  var end = text.length;
  for (final ch in [" ", "\n", "\t", "，", ",", "。", "；", ")", "）"]) {
    final i = text.indexOf(ch, idx);
    if (i > 0 && i < end) end = i;
  }
  return text.substring(idx, end);
}

/// 解析任意文本中的满满音乐分享
SharePayload? parseManmanShareText(String text) {
  final link = extractManmanLink(text);
  if (link == null) return null;
  final uri = Uri.tryParse(link);
  if (uri == null) return null;
  final code = uri.queryParameters["d"];
  if (code == null || code.isEmpty) return null;
  return SharePayload.decode(code);
}

/// 解析深度链接
SharePayload? parseManmanUri(Uri uri) {
  if (uri.scheme != manmanScheme) return null;
  if (uri.host != "play" && uri.pathSegments.isNotEmpty == false) {
    // 仍尝试从 query 里取
  }
  final code = uri.queryParameters["d"];
  if (code == null || code.isEmpty) return null;
  return SharePayload.decode(code);
}
