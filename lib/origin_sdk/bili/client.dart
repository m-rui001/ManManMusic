import "dart:convert";

import "package:bot_toast/bot_toast.dart";
import "package:bobomusic/origin_sdk/bili/utils.dart";
import "package:dio/dio.dart";
import "package:shared_preferences/shared_preferences.dart";
import "../origin_types.dart";
import "./auth.dart";
import "./sign.dart";
import "./subtitle.dart";
import "./ticket.dart";
import "./types.dart";

const _userAgent =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
const _referer = "https://www.bilibili.com/";
const _cacheCreatedAtKey = "bili_catch_created_at";
const _signImgKey = "bili_sign_img_key";
const _signSubKey = "bili_sign_sub_key";
const _ticketKey = "bili_ticket";
const _spiB3 = "bili_spi_b3";
const _spiB4 = "bili_spi_b4";
const _cacheVersionKey = "bili_cache_version";
const _cacheVersionValue = "4";

class BiliClient implements OriginService {
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  SignData? signData;
  SpiData? spiData;
  String? ticket;
  String? bNut;

  // bNut 缓存
  BiliBNut? _bNutCache;
  DateTime? _bNutCacheTime;

  BiliClient() {
    dio.options.headers["UserAgent"] = _userAgent;
    dio.options.headers["Referer"] = _referer;
    // dio.options.headers["Origin"] = "https://space.bilibili.com";
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          final cookies = [
            // "buvid4=${spiData?.b4};",
            // "buvid3=${spiData?.b3};",
          ];
          if (options.uri.path.startsWith("/x/player/wbi/playurl")) {
            // cookies.add("bili_ticket=$ticket;");
          } else {
            cookies.add("buvid4=${spiData?.b4};");
            cookies.add("buvid3=${spiData?.b3};");
            cookies.add("bili_ticket=$ticket;");
            cookies.add("b_nut=$bNut;");
          }

          // 已登录时带上账号 Cookie（正常 web 端行为，用于拿到更高音质）
          final loginCookie = BiliAuth.instance.cookieHeader;
          if (BiliAuth.instance.isLogin && loginCookie.isNotEmpty) {
            cookies.add(loginCookie);
          }

          final cookie = cookies.where((e) => e.trim().isNotEmpty).join(" ");
          if (cookie.isNotEmpty) {
            options.headers["cookie"] = cookie;
          }
          return handler.next(options);
        },
        onError: (DioException error, ErrorInterceptorHandler handler) {
          // BotToast.showText(text: "请求失败: $error");
          return handler.next(error);
        },
        onResponse: (Response response, ResponseInterceptorHandler handler) {
          // 静默请求（字幕自动匹配等）失败时不弹提示，不打扰听歌
          final silent = response.requestOptions.extra["silent"] == true;
          final logData = {
            "requestOptions": response.requestOptions,
            "url": response.realUri.toString(),
            "data": response.data,
            "statusCode": response.statusCode,
          };
          if (response.realUri.toString().contains("x/web-interface/nav")) {
            return handler.next(response);
          }
          if (response.statusCode! < 200 || response.statusCode! > 300) {
            if (!silent) {
              BotToast.showText(
                  text:
                      "请求失败: ${response.statusCode} ${response.statusMessage} ${response.data}");
            }
            throw DioException(
              requestOptions: response.requestOptions,
              response: response,
              error: logData,
              type: DioExceptionType.badResponse,
            );
          }

          if (response.data is! Map) {
            return handler.next(response);
          }

          final code = response.data["code"];
          final message = response.data["message"];
          final resData = response.data["data"];

          if (code != 0) {
            if (!silent) BotToast.showText(text: "请求失败: $message");
            throw DioException(
              requestOptions: response.requestOptions,
              response: response,
              error: logData,
              type: DioExceptionType.badResponse,
            );
          }
          if (resData["v_voucher"] != null) {
            if (!silent) BotToast.showText(text: "请求失败，触发风控，请稍后重试");
            throw DioException(
              requestOptions: response.requestOptions,
              response: response,
              error: logData,
              type: DioExceptionType.badResponse,
            );
          }
          return handler.next(response);
        },
      ),
    );
  }

  init() async {
    final localStorage = await SharedPreferences.getInstance();
    final createAt = localStorage.getInt(_cacheCreatedAtKey);
    final cacheVersion = localStorage.getString(_cacheVersionKey);
    final bNutItem = await getBNut();
    bNut = bNutItem?.bNut;

    if (createAt != null && cacheVersion == _cacheVersionValue) {
      // 判断是否过期
      final isExpired = DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(createAt))
              .inDays >
          1;
      if (!isExpired) {
        final signImgKey = localStorage.getString(_signImgKey);
        final signSubKey = localStorage.getString(_signSubKey);
        final spiB3 = localStorage.getString(_spiB3);
        final spiB4 = localStorage.getString(_spiB4);
        final ticketCache = localStorage.getString(_ticketKey);
        if (signSubKey != null &&
            signImgKey != null &&
            spiB3 != null &&
            spiB4 != null &&
            ticketCache != null &&
            ticketCache.isNotEmpty) {
          signData = SignData(imgKey: signImgKey, subKey: signSubKey);
          spiData = SpiData(b3: bNutItem?.b3 ?? spiB3, b4: spiB4);
          ticket = ticketCache;
          return;
        }
      }
    }
    try {
      final results = await Future.wait([
        getSignData(),
        getSpiData(),
        getBiliTicket(""),
      ]);
      signData = results[0] as SignData;
      spiData = results[1] as SpiData;
      ticket = results[2] as String;
      if (bNutItem?.b3.isNotEmpty == true && spiData!.b3.isNotEmpty) {
        spiData = SpiData(b3: bNutItem!.b3, b4: spiData!.b4);
      }

      localStorage.setString(_cacheVersionKey, _cacheVersionValue);

      localStorage.setInt(
        _cacheCreatedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      if (ticket != null || ticket!.isNotEmpty) {
        localStorage.setString(_ticketKey, ticket!);
      }
      if (signData != null) {
        localStorage.setString(_signImgKey, signData!.imgKey);
        localStorage.setString(_signSubKey, signData!.subKey);
      }
      if (spiData != null) {
        localStorage.setString(_spiB3, spiData!.b3);
        localStorage.setString(_spiB4, spiData!.b4);
      }
    } catch (e) {
      print(e);
    }
  }

  // 获取签名秘钥
  Future<SignData> getSignData() async {
    final response =
        await dio.get("https://api.bilibili.com/x/web-interface/nav");

    if (response.statusCode == 200) {
      return SignData.fromJson(response.data);
    } else {
      throw response.data;
    }
  }

  // 获取 spi 唯一标识
  Future<SpiData> getSpiData() async {
    final response =
        await dio.get("https://api.bilibili.com/x/frontend/finger/spi");

    if (response.statusCode == 200) {
      return SpiData.fromJson(response.data);
    } else {
      throw response.data;
    }
  }

  // 获取 b_nut
  Future<BiliBNut?> getBNut() async {
    if (_bNutCache != null &&
        _bNutCacheTime != null &&
        DateTime.now().difference(_bNutCacheTime!).inSeconds < 1) {
      return _bNutCache;
    }
    final response = await Dio().get("https://www.bilibili.com/");
    if (response.statusCode == 200) {
      // 获取响应头中的 Set-Cookie 字段中 的 b_nut
      final setCookie = response.headers["Set-Cookie"];
      final b3Item =
          setCookie?.firstWhere((element) => element.startsWith("buvid3"));
      final b3 = b3Item?.split(";")[0].split("=")[1] ?? "";
      final bNutItem =
          setCookie?.firstWhere((element) => element.startsWith("b_nut"));
      final nNut = bNutItem?.split(";")[0].split("=")[1] ?? "";

      _bNutCache = BiliBNut(bNut: nNut, b3: b3);
      _bNutCacheTime = DateTime.now();
      return _bNutCache;
    }
    return null;
  }

  // 搜索
  @override
  Future<SearchResponse> search(SearchParams params) async {
    await init();
    const url = "https://api.bilibili.com/x/web-interface/wbi/search/type";
    Map<String, String> query = _signParams({
      "search_type": "video",
      "keyword": params.keyword,
      "page": params.page.toString(),
      "pagesize": "20",
    });
    final apiPath = Uri.parse(url).replace(queryParameters: query).toString();
    try {
      final response = await dio.get(apiPath);
      return BiliSearchResponse.fromJson(response.data);
    } catch (e) {
      return BiliSearchResponse(
        current: 0,
        total: 0,
        pageSize: 0,
        data: [],
      );
    }
  }

  // 搜索条目详情
  @override
  Future<SearchItem> searchDetail(String id) async {
    BiliId biliid = BiliId.unicode(id);
    await init();
    const url = "https://api.bilibili.com/x/web-interface/view";
    Map<String, String> query = _signParams({
      "aid": biliid.aid,
      "bvid": biliid.bvid,
    });
    final response = await dio.get(
      Uri.parse(url).replace(queryParameters: query).toString(),
    );
    final data = response.data["data"];
    return BiliSearchItem.fromJson(data);
  }

  // 搜索视频所在系列或合集
  Future<BiliSearchSeasonItem?> searchSeason(int mid, int seasonId) async {
    await init();
    const url =
        "https://api.bilibili.com/x/polymer/web-space/seasons_archives_list";
    return loadSeasonPages((page, size) async {
      final query = _signParams({
        "mid": "$mid",
        "season_id": "$seasonId",
        "page_num": "$page",
        "page_size": "$size",
      });
      final response = await dio.get(
        Uri.parse(url).replace(queryParameters: query).toString(),
      );
      if (response.statusCode != 200 || response.data["data"] is! Map<String, dynamic>) {
        throw StateError("合集加载失败");
      }
      return response.data["data"] as Map<String, dynamic>;
    });
  }

  // 搜索建议
  @override
  Future<List<SearchSuggestItem>> searchSuggest(String keyword) async {
    await init();
    const url = "https://s.search.bilibili.com/main/suggest";
    Map<String, String> query = _signParams({
      "term": keyword,
    });
    final response = await dio.get(url, queryParameters: query);

    if (response.statusCode == 200) {
      final data =
          response.data is String ? jsonDecode(response.data) : response.data;
      final List<dynamic> tags = data["result"]["tag"];
      List<SearchSuggestItem> result = [];
      tags.toList().forEach((t) {
        result.add(SearchSuggestItem(name: t["name"], value: t["value"]));
      });
      return result;
    } else {
      throw response.data;
    }
  }

  /// 用 aid / bvid 查 cid（取第一个分 P）
  ///
  /// 做过缓存，同一视频只查一次。
  Future<String?> _fetchCid({required String aid, required String bvid}) async {
    final cacheKey = "cid_${bvid.isNotEmpty ? bvid : aid}";
    final cached = _cidCache[cacheKey];
    if (cached != null) return cached;

    // 同一视频并发请求时复用同一个 Future
    final pending = _cidPending[cacheKey];
    if (pending != null) return pending;

    final future = _doFetchCid(aid: aid, bvid: bvid);
    _cidPending[cacheKey] = future;
    try {
      final cid = await future;
      if (cid != null && cid.isNotEmpty) _cidCache[cacheKey] = cid;
      return cid;
    } finally {
      _cidPending.remove(cacheKey);
    }
  }

  Future<String?> _doFetchCid(
      {required String aid, required String bvid}) async {
    try {
      final resp = await dio.get(
        "https://api.bilibili.com/x/web-interface/view",
        queryParameters: {
          if (bvid.isNotEmpty) "bvid": bvid else "aid": aid,
        },
        options: Options(
          headers: {
            if (BiliAuth.instance.isLogin)
              "Cookie": BiliAuth.instance.cookieHeader,
          },
        ),
      );
      final body = resp.data is String ? jsonDecode(resp.data) : resp.data;
      if (body is! Map) return null;

      final data = body["data"];
      if (data is! Map) return null;

      // 优先用当前分 P，否则第一个分 P
      final pages = data["pages"];
      if (pages is List && pages.isNotEmpty) {
        final first = pages.first;
        if (first is Map) return "${first["cid"] ?? ""}";
      }

      final direct = data["cid"];
      if (direct != null) return "$direct";
      return null;
    } catch (_) {
      return null;
    }
  }

  /// cid 缓存：key = bvid 或 aid
  final Map<String, String> _cidCache = {};

  /// 正在查询中的 cid，避免并发重复请求
  final Map<String, Future<String?>> _cidPending = {};

  /// 字幕 JSON 在 CDN 上，返回的不是 {code, data} 结构，
  /// 不能走上面那套业务拦截器，单独用一个干净的 Dio。
  final _subtitleDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {"UserAgent": _userAgent, "Referer": _referer},
  ));

  /// 取当前视频的 CC 字幕，转成 LRC 文本；没有字幕返回 null
  ///
  /// 只读 web 接口：player/v2 拿字幕列表，再取字幕 JSON。
  /// 优先人工中文字幕，其次 AI 中文，最后兜底第一条。
  Future<String?> getSubtitleLrc(String id) async {
    final BiliId biliid;
    try {
      biliid = BiliId.unicode(id);
    } catch (_) {
      return null;
    }
    if (int.tryParse(biliid.aid) == null && biliid.bvid.isEmpty) return null;
    var cid = biliid.cid ?? "";
    if (cid.isEmpty) {
      cid = await _fetchCid(aid: biliid.aid, bvid: biliid.bvid) ?? "";
      if (cid.isEmpty) return null;
    }
    try {
      await init();
      final query = _signParams({
        "aid": biliid.aid,
        "bvid": biliid.bvid,
        "cid": cid,
      });
      final response = await dio.get(
        Uri.parse("https://api.bilibili.com/x/player/wbi/v2")
            .replace(queryParameters: query)
            .toString(),
        options: Options(
          extra: {"silent": true},
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final data = response.data is Map ? response.data["data"] : null;
      final subtitle = data is Map ? data["subtitle"] : null;
      final list = subtitle is Map ? subtitle["subtitles"] : null;
      if (list is! List || list.isEmpty) return null;
      final entries = list.whereType<Map>().toList();
      Map? chosen;
      for (final lan in const ["zh-Hans", "zh-CN", "zh", "ai-zh"]) {
        for (final entry in entries) {
          if (entry["lan"] == lan) {
            chosen = entry;
            break;
          }
        }
        if (chosen != null) break;
      }
      chosen ??= entries.first;
      var url = "${chosen["subtitle_url"] ?? ""}";
      if (url.isEmpty) return null;
      if (url.startsWith("//")) url = "https:$url";
      final json = await _subtitleDio.get(url);
      final body = json.data is String ? jsonDecode(json.data) : json.data;
      if (body is! Map<String, dynamic>) return null;
      return subtitleToLrc(body);
    } catch (_) {
      return null;
    }
  }

  // 获取音乐播放地址
  //
  // 已登录（且为大会员）时请求 fnval=4048，可拿到 Hi-Res / 杜比 / 无损音轨；
  // 未登录时退回 fnval=16，只拿普通 DASH 音轨。
  @override
  Future<MusicUrl> getMusicUrl(String id) async {
    BiliId biliid = BiliId.unicode(id);

    // 收藏夹导入的条目只有 aid/bvid，没有 cid；
    // 这里惰性补一次，避免「source error」播不了。
    if (biliid.cid == null || biliid.cid == "") {
      final cid = await _fetchCid(aid: biliid.aid, bvid: biliid.bvid);
      if (cid == null || cid.isEmpty) {
        throw Exception("获取视频信息失败，可能已下架或仅限会员");
      }
      biliid = BiliId(aid: biliid.aid, bvid: biliid.bvid, cid: cid);
    }

    await init();
    const apiPath = "https://api.bilibili.com/x/player/wbi/playurl";
    // const url = "https://api.bilibili.com/x/player/playurl";
    Future<MusicUrl> requestAudio(String flags) async {
      final query = _signParams({
        "avid": biliid.aid,
        "bvid": biliid.bvid,
        "cid": biliid.cid!,
        "fnval": flags,
        "fourk": "1",
      });
      final response = await dio.get(
        Uri.parse(apiPath).replace(queryParameters: query).toString(),
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );
      final body = response.data;
      final data = body is Map ? body["data"] : null;
      final dash = data is Map ? data["dash"] : null;
      if (dash is! Map) throw StateError("该视频没有可播放的音轨");

      int trackInt(Object? value) =>
          value is num ? value.toInt() : int.tryParse("$value") ?? 0;

      Iterable<MusicUrl> urls(Map track, String format) sync* {
        final backup = track["backupUrl"] ?? track["backup_url"];
        for (final value in [
          track["baseUrl"] ?? track["base_url"],
          if (backup is List) ...backup,
        ]) {
          final uri = value is String ? Uri.tryParse(value) : null;
          if (uri == null || !uri.hasAuthority || uri.scheme != "https") {
            continue;
          }
          yield MusicUrl(
            url: value as String,
            headers: {"Referer": _referer},
            format: format,
            bitrate: trackInt(track["bandwidth"]),
            trackId: trackInt(track["id"]),
            codec: track["codecs"]?.toString() ?? "",
          );
        }
      }

      final flac = dash["flac"];
      final lossless = flac is Map ? flac["audio"] : null;
      final dolby = dash["dolby"];
      final dolbyAudio = dolby is Map ? dolby["audio"] : null;
      final audio = dash["audio"];
      final stereo = audio is List ? audio.whereType<Map>().toList() : <Map>[];
      stereo.sort((a, b) {
        final byBandwidth =
            trackInt(b["bandwidth"]).compareTo(trackInt(a["bandwidth"]));
        if (byBandwidth != 0) return byBandwidth;
        return trackInt(b["id"]).compareTo(trackInt(a["id"]));
      });
      final candidates = [
        if (lossless is Map) ...urls(lossless, "FLAC"),
        for (final track in stereo)
          ...urls(
              track, "${track["codecs"]}".contains("mp4a") ? "AAC" : "DASH"),
        if (dolbyAudio is Map) ...urls(dolbyAudio, "杜比音轨"),
        if (dolbyAudio is List)
          for (final track in dolbyAudio.whereType<Map>())
            ...urls(track, "杜比音轨"),
      ];
      final seen = <String>{};
      final usable =
          candidates.where((candidate) => seen.add(candidate.url)).toList();
      if (usable.isNotEmpty) {
        final best = usable.first;
        return MusicUrl(
          url: best.url,
          headers: best.headers,
          format: best.format,
          bitrate: best.bitrate,
          trackId: best.trackId,
          codec: best.codec,
          alternatives: usable.skip(1).toList(),
        );
      }
      throw StateError("获取音频地址失败：没有可用音轨");
    }

    if (BiliAuth.instance.isLogin) {
      try {
        return await requestAudio("4048");
      } catch (_) {
        // HTTP 成功也可能返回业务错误或缺失 DASH，继续请求常规音轨。
      }
    }
    return requestAudio("16");
  }

  // 对参数进行签名
  _signParams(Map<String, String> params) {
    if (signData == null) {
      throw Exception("请先获取签名秘钥");
    }
    return encWbi(params, signData!.imgKey, signData!.subKey);
  }
}
