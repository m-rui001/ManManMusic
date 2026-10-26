import "dart:async";
import "dart:convert";

import "package:dio/dio.dart";
import "package:shared_preferences/shared_preferences.dart";

/// 与 [BiliClient] 共用的 UA / Referer
const String biliUserAgent =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
const String biliReferer = "https://www.bilibili.com/";

const String _kCookie = "bili_login_cookie";
const String _kMid = "bili_login_mid";
const String _kUname = "bili_login_uname";
const String _kFace = "bili_login_face";
const String _kVip = "bili_login_vip";
const String _kLevel = "bili_login_level";

/// 二维码登录状态
enum BiliQrStatus {
  waiting("等待扫码", "请使用哔哩哔哩客户端扫码登录"),
  scanned("已扫码", "请在手机端确认登录"),
  expired("已失效", "二维码已失效，请刷新"),
  success("登录成功", "欢迎回来"),
  failed("登录失败", "请稍后重试");

  const BiliQrStatus(this.title, this.tip);

  final String title;
  final String tip;
}

/// 二维码登录信息
class BiliQrCode {
  final String key;
  final String url;

  const BiliQrCode({required this.key, required this.url});
}

/// 轮询结果
class BiliQrPollResult {
  final BiliQrStatus status;

  /// 仅 [BiliQrStatus.success] 时有值
  final Map<String, String>? cookies;

  const BiliQrPollResult({required this.status, this.cookies});
}

/// B 站收藏夹
class BiliFavFolder {
  final int id;
  final String title;
  final int mediaCount;
  final String cover;

  const BiliFavFolder({
    required this.id,
    required this.title,
    required this.mediaCount,
    required this.cover,
  });

  factory BiliFavFolder.fromJson(Map<String, dynamic> json) {
    return BiliFavFolder(
      id: json["id"] ?? 0,
      title: json["title"] ?? "未命名收藏夹",
      mediaCount: json["media_count"] ?? 0,
      cover: json["cover"] ?? "",
    );
  }
}

/// 收藏夹里的一个视频
class BiliFavMedia {
  final String aid;
  final String bvid;
  final String title;
  final String cover;
  final int duration;
  final String upper;

  const BiliFavMedia({
    required this.aid,
    required this.bvid,
    required this.title,
    required this.cover,
    required this.duration,
    required this.upper,
  });

  factory BiliFavMedia.fromJson(Map<String, dynamic> json) {
    final upper = json["upper"];
    return BiliFavMedia(
      aid: "${json["id"] ?? json["aid"] ?? ""}",
      bvid: "${json["bvid"] ?? ""}",
      title: "${json["title"] ?? ""}",
      cover: "${json["cover"] ?? ""}",
      duration: (json["duration"] is int) ? json["duration"] : 0,
      upper: (upper is Map ? "${upper["name"] ?? ""}" : ""),
    );
  }
}

/// B 站登录态管理（纯客户端，无服务器）
///
/// 只使用官方 web 端接口，且仅在用户主动操作时发起请求，
/// 尽量降低触发风控、导致账号受限的概率。
class BiliAuth {
  BiliAuth._();

  static final BiliAuth instance = BiliAuth._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        "User-Agent": biliUserAgent,
        "Referer": biliReferer,
        "Origin": "https://www.bilibili.com",
      },
      validateStatus: (_) => true,
    ),
  );

  /// 登录产生的 Cookie（SESSDATA / bili_jct / DedeUserID ...）
  final Map<String, String> cookies = {};

  bool _inited = false;

  int mid = 0;
  String uname = "";
  String face = "";
  int vipStatus = 0;
  int level = 0;

  bool get isLogin => cookies["SESSDATA"]?.isNotEmpty == true;

  /// CSRF token
  String get csrf => cookies["bili_jct"] ?? "";

  /// 拼成请求头用的 Cookie 字符串
  String get cookieHeader {
    if (cookies.isEmpty) return "";
    return cookies.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => "${e.key}=${e.value}")
        .join("; ");
  }

  /// 冷启动时读取本地登录态
  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    final storage = await SharedPreferences.getInstance();
    final raw = storage.getString(_kCookie);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((k, v) {
        if (v is String && v.isNotEmpty) cookies[k] = v;
      });
    } catch (_) {
      return;
    }

    mid = storage.getInt(_kMid) ?? 0;
    uname = storage.getString(_kUname) ?? "";
    face = storage.getString(_kFace) ?? "";
    vipStatus = storage.getInt(_kVip) ?? 0;
    level = storage.getInt(_kLevel) ?? 0;
  }

  Future<void> _save() async {
    final storage = await SharedPreferences.getInstance();
    await storage.setString(_kCookie, jsonEncode(cookies));
    await storage.setInt(_kMid, mid);
    await storage.setString(_kUname, uname);
    await storage.setString(_kFace, face);
    await storage.setInt(_kVip, vipStatus);
    await storage.setInt(_kLevel, level);
  }

  /// 申请二维码
  Future<BiliQrCode> qrGenerate() async {
    final resp = await _dio.get(
      "https://passport.bilibili.com/x/passport-login/web/qrcode/generate",
      queryParameters: {"source": "main-fe-header"},
    );
    final data = _pick(resp.data);
    if (data == null || data["url"] == null) {
      throw Exception("获取登录二维码失败");
    }
    return BiliQrCode(key: "${data["qrcode_key"]}", url: "${data["url"]}");
  }

  /// 轮询扫码结果
  Future<BiliQrPollResult> qrPoll(String key) async {
    final resp = await _dio.get(
      "https://passport.bilibili.com/x/passport-login/web/qrcode/poll",
      queryParameters: {"qrcode_key": key, "source": "main-fe-header"},
    );

    final body = resp.data is String ? jsonDecode(resp.data) : resp.data;
    if (body is! Map) {
      return const BiliQrPollResult(status: BiliQrStatus.failed);
    }
    final data = body["data"];
    if (data is! Map) {
      return const BiliQrPollResult(status: BiliQrStatus.failed);
    }

    final code = data["code"];
    if (code == 86101) {
      return const BiliQrPollResult(status: BiliQrStatus.waiting);
    }
    if (code == 86090) {
      return const BiliQrPollResult(status: BiliQrStatus.scanned);
    }
    if (code == 86038) {
      return const BiliQrPollResult(status: BiliQrStatus.expired);
    }
    if (code != 0) {
      return const BiliQrPollResult(status: BiliQrStatus.failed);
    }

    // 登录成功，从回调 URL 中提取 Cookie
    final url = "${data["url"] ?? ""}";
    final parsed = Uri.tryParse(url);
    final result = <String, String>{};
    if (parsed != null) {
      parsed.queryParameters.forEach((k, v) => result[k] = v);
    }

    // 部分字段为空时用 refresh_token 兜底场景不发请求，直接返回
    if (result["SESSDATA"] == null) {
      return const BiliQrPollResult(status: BiliQrStatus.failed);
    }

    return BiliQrPollResult(status: BiliQrStatus.success, cookies: result);
  }

  /// 登录成功后落地
  Future<bool> applyLogin(Map<String, String> newCookies) async {
    cookies.clear();
    newCookies.forEach((k, v) {
      // 只保留有意义的字段
      if (v.isEmpty) return;
      if (k == "gourl" || k == "Expires" || k == "first_domain") return;
      cookies[k] = v;
    });
    cookies.remove("gourl");

    final ok = await refreshUserInfo();
    await _save();
    return ok;
  }

  /// 拉取/刷新用户信息
  Future<bool> refreshUserInfo() async {
    if (!isLogin) return false;
    try {
      final resp = await _dio.get(
        "https://api.bilibili.com/x/web-interface/nav",
        options: Options(headers: {"Cookie": cookieHeader}),
      );
      final body = resp.data is String ? jsonDecode(resp.data) : resp.data;
      if (body is! Map) return false;
      final data = body["data"];
      if (data is! Map) return false;

      if (data["isLogin"] != true) {
        return false;
      }

      mid = data["mid"] ?? 0;
      uname = "${data["uname"] ?? ""}";
      face = "${data["face"] ?? ""}";
      vipStatus = data["vipStatus"] ?? 0;
      final lvl = data["level_info"];
      level = (lvl is Map ? (lvl["current_level"] ?? 0) : 0);
      await _save();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 退出登录
  Future<void> logout() async {
    cookies.clear();
    mid = 0;
    uname = "";
    face = "";
    vipStatus = 0;
    level = 0;
    final storage = await SharedPreferences.getInstance();
    await storage.remove(_kCookie);
    await storage.remove(_kMid);
    await storage.remove(_kUname);
    await storage.remove(_kFace);
    await storage.remove(_kVip);
    await storage.remove(_kLevel);
  }

  /// 获取收藏夹列表（需要登录）
  Future<List<BiliFavFolder>> fetchFavFolders() async {
    if (!isLogin) throw Exception("请先登录哔哩哔哩账号");
    if (mid == 0) await refreshUserInfo();

    final resp = await _dio.get(
      "https://api.bilibili.com/x/v3/fav/folder/created/list-all",
      queryParameters: {
        "up_mid": "$mid",
        "web_location": "333.1387",
      },
      options: Options(headers: {"Cookie": cookieHeader}),
    );

    final data = _pick(resp.data);
    if (data == null) return [];

    final list = data["list"];
    if (list is! List) return [];

    return list
        .whereType<Map>()
        .map((e) => BiliFavFolder.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 获取某个收藏夹的内容（分页）
  Future<List<BiliFavMedia>> fetchFavMedias({
    required int mediaId,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (!isLogin) throw Exception("请先登录哔哩哔哩账号");

    final resp = await _dio.get(
      "https://api.bilibili.com/x/v3/fav/resource/list",
      queryParameters: {
        "media_id": "$mediaId",
        "pn": "$page",
        "ps": "$pageSize",
        "keyword": "",
        "order": "mtime",
        "type": "0",
        "tid": "0",
        "platform": "web",
        "web_location": "333.1387",
      },
      options: Options(headers: {"Cookie": cookieHeader}),
    );

    final data = _pick(resp.data);
    if (data == null) return [];

    final medias = data["medias"];
    if (medias is! List) return [];

    return medias
        .whereType<Map>()
        .map((e) => BiliFavMedia.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.bvid.isNotEmpty)
        .toList();
  }

  /// 统一解包 `{code, message, data}` 结构
  Map<String, dynamic>? _pick(dynamic raw) {
    final body = raw is String ? jsonDecode(raw) : raw;
    if (body is! Map) return null;
    final data = body["data"];
    if (data is! Map) return null;
    return Map<String, dynamic>.from(data);
  }
}
