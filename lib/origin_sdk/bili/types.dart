import "package:bobomusic/origin_sdk/bili/utils.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/clear_html_tags.dart";

/// 签名秘钥
class SignData {
  final String imgKey;
  final String subKey;

  const SignData({required this.imgKey, required this.subKey});

  factory SignData.fromJson(Map<String, dynamic> json) {
    String imgUrl = json["data"]["wbi_img"]["img_url"];
    String subUrl = json["data"]["wbi_img"]["sub_url"];
    String imgKey =
        imgUrl.substring(imgUrl.lastIndexOf("/") + 1, imgUrl.lastIndexOf("."));
    String subKey =
        subUrl.substring(subUrl.lastIndexOf("/") + 1, subUrl.lastIndexOf("."));
    return SignData(
      imgKey: imgKey,
      subKey: subKey,
    );
  }
}

/// 签名秘钥
class SpiData {
  final String b3;
  final String b4;

  const SpiData({required this.b3, required this.b4});

  factory SpiData.fromJson(Map<String, dynamic> json) {
    return SpiData(
      b3: json["data"]["b_3"],
      b4: json["data"]["b_4"],
    );
  }
}

/// 搜索结果
class BiliSearchResponse extends SearchResponse {
  BiliSearchResponse({
    required super.current,
    required super.total,
    required super.pageSize,
    required super.data,
  });
  factory BiliSearchResponse.fromJson(Map<String, dynamic> json) {
    var result = json["data"]["result"].toList();
    List<BiliSearchItem> data = [];
    for (var j in result) {
      if (j["type"] != "ketang") {
        data.add(BiliSearchItem.fromJson(j));
      }
    }
    return BiliSearchResponse(
      current: json["data"]["page"],
      total: json["data"]["numResults"],
      pageSize: json["data"]["pagesize"],
      data: data,
    );
  }
}

/// 搜索条目
class BiliSearchItem extends SearchItem {
  const BiliSearchItem({
    required super.id,
    required super.cover,
    required super.name,
    required super.duration,
    required super.author,
    required super.origin,
    required super.isSeasonDisplay,
    required super.ugcSeason,
    super.musicList,
    super.type,
  });
  factory BiliSearchItem.fromJson(Map<String, dynamic> json) {
    final String aid = json["aid"].toString();
    final String bvid = json["bvid"];
    final title = clearHtmlTags(json["title"]);
    final season = json["ugc_season"];
    String id = BiliId(aid: aid, bvid: bvid).decode();

    SearchType? type;
    List<MusicItem> musicList = [];

    // 判断是否为歌单
    final pages = json["pages"];
    if (pages is List) {
      final owner = json["owner"];
      for (var j in pages) {
        final mid = BiliId(
          aid: aid,
          bvid: bvid,
          cid: j["cid"]?.toString(),
        ).decode();

        final item = MusicItem(
          id: mid,
          cover: firstBiliCover([
            j["first_frame"],
            json["pic"],
            if (season is Map) season["cover"],
          ]),
          name: j["part"],
          collectionName: pages.length > 1 ? title : "",
          duration: j["duration"],
          author: owner is Map ? "${owner["name"] ?? ""}" : "",
          origin: OriginType.bili,
        );
        musicList.add(item);
      }
    }
    if (musicList.isNotEmpty) {
      if (musicList.length > 1) {
        type = SearchType.orderName;
      } else {
        type = SearchType.music;
        id = musicList[0].id;
      }
    }

    return BiliSearchItem(
      id: id,
      cover: firstBiliCover([json["pic"]]),
      name: title,
      duration: json["duration"] is String
        ? duration2seconds(json["duration"])
        : json["duration"],
      author: json["author"] ?? "",
      origin: OriginType.bili,
      type: type,
      musicList: musicList,
      isSeasonDisplay: json["is_season_display"] ?? false,
      ugcSeason: season is Map && season["mid"] is int && season["id"] is int
          ? UgcSeason(
              mid: season["mid"],
              seasonId: season["id"],
              title: "${season["title"] ?? ""}".trim(),
            )
          : null,
    );
  }
}
/// 搜索条目
class BiliSearchSeasonItem {
  final Meta meta;
  final List<MusicItem> musicList;

  const BiliSearchSeasonItem({
    required this.meta,
    required this.musicList,
  });

  factory BiliSearchSeasonItem.fromJson(Map<String, dynamic> json) {
    final jsonMeta = json["meta"];
    final jsonArchives = json["archives"];
    final collectionName = clearHtmlTags("${jsonMeta["name"] ?? ""}").trim();
    List<MusicItem> musicList = [];

    for (var archive in jsonArchives) {
      musicList.add(
        MusicItem(
          id: BiliId(
            aid: "${archive["aid"]}",
            bvid: "${archive["bvid"]}",
          ).decode(),
          cover: firstBiliCover([archive["pic"], archive["cover"], jsonMeta["cover"]]),
          name: clearHtmlTags(archive["title"]),
          collectionName: collectionName,
          duration: archive["duration"] is String
            ? duration2seconds(archive["duration"])
            : archive["duration"],
          author: archive["author"] ?? "",
          origin: OriginType.bili,
        )
      );
    }

    return BiliSearchSeasonItem(
      meta: Meta(mid: jsonMeta["mid"], name: jsonMeta["name"], seasonId: jsonMeta["season_id"], cover: firstBiliCover([jsonMeta["cover"]])),
      musicList: musicList,
    );
  }
}

class Meta {
  final int mid;
  final String name;
  final String cover;
  final int seasonId;

  Meta({
    required this.mid,
    required this.name,
    required this.cover,
    required this.seasonId,
  });
}

class BiliMusicDetail extends MusicDetail {
  BiliMusicDetail({
    required super.id,
    required super.cover,
    required super.name,
    required super.duration,
    required super.author,
    required super.origin,
    required super.url,
  });

  factory BiliMusicDetail.fromJson(
    String id,
    Map<String, dynamic> json,
  ) {
    return BiliMusicDetail(
      id: id,
      cover: firstBiliCover([json["first_frame"], json["pic"]]),
      name: json["part"],
      duration: json["duration"],
      author: "",
      origin: OriginType.bili,
      url: "",
    );
  }
}

class BiliBNut {
  final String bNut;
  final String b3;

  const BiliBNut({required this.bNut, required this.b3});
}
