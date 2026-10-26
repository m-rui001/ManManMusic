import "dart:convert";

import "package:dio/dio.dart";

/// 解析结果：一个 B 站视频（可能带分 P）
class BiliLinkInfo {
  final String bvid;
  final String aid;

  /// 分 P 序号，从 1 开始
  final int page;

  const BiliLinkInfo({
    required this.bvid,
    required this.aid,
    this.page = 1,
  });

  String get key => bvid.isNotEmpty ? bvid : aid;
}

final RegExp _urlReg = RegExp(
  r'''https?://[^\s，,。；;、！!？?）)】》”"'…]+''',
  caseSensitive: false,
);

/// 去掉链接尾部常见的标点
String _trimUrl(String url) {
  var s = url;
  const tails = ['，', ',', '。', '；', ';', ')', '）', '】', '』', '”', '》', '"', "'"];
  while (s.isNotEmpty && tails.contains(s[s.length - 1])) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

const List<String> _biliHosts = [
  "b23.tv",
  "bili2233.cn",
  "bilibili.com",
  "bili.com",
];

/// 从一段分享文本中提取 B 站链接（微信/QQ 分享常常是一大段文字）
String? extractBiliUrl(String text) {
  final matches = _urlReg.allMatches(text);
  for (final m in matches) {
    final raw = m.group(0);
    if (raw == null) continue;
    final url = _trimUrl(raw);
    final lower = url.toLowerCase();
    if (_biliHosts.any(lower.contains)) {
      return url;
    }
  }
  return null;
}

/// 跟随短链跳转，拿到真实地址
Future<String> resolveBiliUrl(String url) async {
  final lower = url.toLowerCase();
  // 已经是完整视频地址，不必再发请求
  if (!lower.contains("b23.tv") && !lower.contains("bili2233.cn")) {
    return url;
  }

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (_) => true,
      headers: {
        "User-Agent":
            "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
      },
    ),
  );

  try {
    final resp = await dio.get(url);
    // dio 会把最终地址放在 realUri
    final finalUrl = resp.realUri.toString();
    if (finalUrl.contains("bilibili.com")) return finalUrl;
    // 部分情况会返回一个跳转 HTML
    final location = resp.headers.value("location");
    if (location != null && location.isNotEmpty) return location;
  } catch (_) {
    // 解析失败就退回原地址
  }

  return url;
}

/// 从 B 站视频地址里解析出 bvid / aid / 分 P
BiliLinkInfo? parseBiliUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;

  String bvid = "";
  String aid = "";
  int page = 1;

  // 路径中的 BV 号：/video/BV1xx411c7mD
  final segs = uri.pathSegments;
  for (final s in segs) {
    if (s.startsWith("BV") && s.length >= 10) {
      bvid = s;
      break;
    }
    if (s.startsWith("av") && s.length > 2) {
      aid = s.substring(2);
      break;
    }
  }

  // 查询参数中的 bvid / aid / p
  final q = uri.queryParameters;
  if (bvid.isEmpty && q["bvid"] != null) bvid = q["bvid"]!;
  if (aid.isEmpty && q["aid"] != null) aid = q["aid"]!;
  final p = int.tryParse(q["p"] ?? "");
  if (p != null && p > 0) page = p;

  // 番剧 / 音频等其它形态暂不支持
  if (bvid.isEmpty && aid.isEmpty) return null;

  return BiliLinkInfo(bvid: bvid, aid: aid, page: page);
}

/// 把分享文本解析成链接信息，失败返回 null
Future<BiliLinkInfo?> parseBiliShareText(String text) async {
  final raw = extractBiliUrl(text);
  if (raw == null) return null;
  final resolved = await resolveBiliUrl(raw);
  return parseBiliUrl(resolved);
}

/// 视频详情（用于分享/导入时补全封面、标题、cid）
class BiliVideoDetail {
  final String aid;
  final String bvid;
  final String title;
  final String cover;
  final String author;
  final int pageCount;

  /// 每个分 P 的 cid / 标题 / 时长
  final List<BiliVideoPage> pages;

  const BiliVideoDetail({
    required this.aid,
    required this.bvid,
    required this.title,
    required this.cover,
    required this.author,
    required this.pageCount,
    required this.pages,
  });

  factory BiliVideoDetail.fromJson(Map<String, dynamic> json) {
    final pages = <BiliVideoPage>[];
    final rawPages = json["pages"];
    if (rawPages is List) {
      for (final p in rawPages) {
        if (p is Map) {
          pages.add(BiliVideoPage.fromJson(Map<String, dynamic>.from(p)));
        }
      }
    }
    final owner = json["owner"];
    return BiliVideoDetail(
      aid: "${json["aid"] ?? ""}",
      bvid: "${json["bvid"] ?? ""}",
      title: "${json["title"] ?? ""}",
      cover: "${json["pic"] ?? ""}",
      author: owner is Map ? "${owner["name"] ?? ""}" : "",
      pageCount: json["videos"] ?? pages.length,
      pages: pages,
    );
  }
}

class BiliVideoPage {
  final String cid;
  final String part;
  final int duration;

  const BiliVideoPage({
    required this.cid,
    required this.part,
    required this.duration,
  });

  factory BiliVideoPage.fromJson(Map<String, dynamic> json) {
    return BiliVideoPage(
      cid: "${json["cid"] ?? ""}",
      part: "${json["part"] ?? ""}",
      duration: json["duration"] is int ? json["duration"] : 0,
    );
  }
}

/// 直接用 bvid / aid 拉视频详情（走 web 接口，只读，不会触发风控）
Future<BiliVideoDetail?> fetchBiliVideoDetail(BiliLinkInfo info) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (_) => true,
      headers: {
        "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://www.bilibili.com/",
      },
    ),
  );

  try {
    final resp = await dio.get(
      "https://api.bilibili.com/x/web-interface/view",
      queryParameters: {
        if (info.bvid.isNotEmpty) "bvid": info.bvid,
        if (info.bvid.isEmpty) "aid": info.aid,
      },
    );
    final body = resp.data is String ? jsonDecode(resp.data) : resp.data;
    if (body is! Map) return null;
    final data = body["data"];
    if (data is! Map) return null;
    return BiliVideoDetail.fromJson(Map<String, dynamic>.from(data));
  } catch (_) {
    return null;
  }
}
