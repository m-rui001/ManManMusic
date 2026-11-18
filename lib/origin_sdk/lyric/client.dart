import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bot_toast/bot_toast.dart";
import "package:dio/dio.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";

class SongResponseData {
  int errno;
  String errmsg;
  SongData data;

  SongResponseData({
    required this.errno,
    required this.errmsg,
    required this.data,
  });

  factory SongResponseData.fromJson(Map<String, dynamic> json) {
    return SongResponseData(
      errno: json["errno"],
      errmsg: json["errmsg"],
      data: SongData.fromJson(json["data"]),
    );
  }
}

class SongData {
  int total;
  List<SongItem> list;

  SongData({
    required this.total,
    required this.list,
  });

  factory SongData.fromJson(Map<String, dynamic> json) {
    return SongData(
      total: json["total"],
      list: ((json["list"] as List?) ?? const [])
          .map((item) => SongItem.fromJson(item))
          .toList(),
    );
  }
}

class SongItem {
  String songmid;
  String songname;
  int interval;
  List<Singer> singer;
  String albumcover;
  String albumname;
  String albumdesc;
  bool free;

  SongItem({
    required this.songmid,
    required this.songname,
    required this.interval,
    required this.singer,
    required this.albumcover,
    required this.albumname,
    required this.albumdesc,
    required this.free,
  });

  factory SongItem.fromJson(Map<String, dynamic> json) {
    return SongItem(
      songmid: json["songmid"],
      songname: json["songname"],
      interval: json["interval"],
      singer: (json["singer"] as List)
          .map((item) => Singer.fromJson(item))
          .toList(),
      albumcover: json["albumcover"],
      albumname: json["albumname"],
      albumdesc: json["albumdesc"],
      free: json["free"],
    );
  }
}

class Singer {
  int id;
  String name;

  Singer({
    required this.id,
    required this.name,
  });

  factory Singer.fromJson(Map<String, dynamic> json) {
    return Singer(
      id: json["id"],
      name: json["name"],
    );
  }
}

class LyricResponse {
  int errno;
  String errmsg;
  LyricData data;

  LyricResponse({
    required this.errno,
    required this.errmsg,
    required this.data,
  });

  factory LyricResponse.fromJson(Map<String, dynamic> json) {
    return LyricResponse(
      errno: json['errno'],
      errmsg: json['errmsg'],
      data: LyricData.fromJson(json['data']),
    );
  }
}

class LyricData {
  String lyric;
  String tlyric;

  LyricData({
    required this.lyric,
    required this.tlyric,
  });

  factory LyricData.fromJson(Map<String, dynamic> json) {
    return LyricData(
      lyric: json['lyric'],
      tlyric: json['tlyric'],
    );
  }
}

class LyricClient {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));
  final String baseURL = "https://api.timelessq.com/music/tencent";

  Future<SongData?> searchMusic(SearchParams params,
      {bool silent = false}) async {
    if (!silent) EasyLoading.show(maskType: EasyLoadingMaskType.black);
    try {
      final response = await dio.get("$baseURL/search", queryParameters: {
        "keyword": params.keyword,
        "page": params.page,
        "pageSize": params.pageSize,
      });
      final data = response.data["data"];
      return SongData.fromJson(data);
    } catch (_) {
      if (!silent) BotToast.showText(text: "歌曲信息查询失败，请检查网络");
      return null;
    } finally {
      if (!silent) EasyLoading.dismiss();
    }
  }

  Future<LyricData?> searchLyric(String songmid, {bool silent = false}) async {
    if (!silent) EasyLoading.show(maskType: EasyLoadingMaskType.black);
    try {
      final response = await dio
          .get("$baseURL/lyric", queryParameters: {"songmid": songmid});
      final data = response.data["data"];
      return LyricData.fromJson(data);
    } catch (_) {
      if (!silent) BotToast.showText(text: "歌词预览失败，请检查网络");
      return null;
    } finally {
      if (!silent) EasyLoading.dismiss();
    }
  }
}
