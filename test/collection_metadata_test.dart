import "dart:convert";

import "package:bobomusic/db/db.dart";
import "package:bobomusic/modules/history/play_history.dart";
import "package:bobomusic/modules/music_order/collection_subtitle.dart";
import "package:bobomusic/origin_sdk/bili/types.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/bili_link.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  test("合集按接口页大小加载并保留跨页顺序", () async {
    final calls = <int>[];
    final season = await loadSeasonPages((page, size) async {
      calls.add(page);
      expect(page, lessThanOrEqualTo(2));
      return {
        "meta": {"mid": 1, "season_id": 2, "name": "演出"},
        "page": {"total": 4, "page_size": 2},
        "archives": [
          for (final id in page == 1 ? [1, 2] : [2, 3])
            {"aid": id, "bvid": "BV$id", "title": "曲目$id"},
        ],
      };
    });
    expect(calls, [1, 2]);
    expect(season.musicList.map((track) => track.name), ["曲目1", "曲目2", "曲目3"]);
  });

  test("合集保留可播放的无标题条目并跳过无效视频标识", () {
    final season = BiliSearchSeasonItem.fromJson({
      "meta": {"mid": 1, "season_id": 7, "name": "<em>合集</em>"},
      "archives": [
        null,
        {"title": "缺标识"},
        {"aid": "2", "bvid": "BVSecond"},
        {"aid": 3, "bvid": "BVThird", "title": "终曲"},
      ],
    });
    expect(season.meta.name, "合集");
    expect(
        season.musicList.map((item) => item.id), ["2_BVSecond", "3_BVThird"]);
    expect(season.musicList.map((item) => item.name), ["BVSecond", "终曲"]);
  });

  test("搜索保留缺时长的视频并跳过不可播放条目", () {
    final page = BiliSearchResponse.fromJson({
      "data": {
        "page": 1,
        "numResults": 4,
        "pagesize": 20,
        "result": [
          null,
          {"type": "ketang"},
          {"aid": 2, "title": "缺标识"},
          {
            "aid": 1,
            "bvid": "BV123",
            "title": "演出",
            "is_season_display": 0,
            "pages": [
              null,
              {},
              {"cid": 3, "duration": "01:02:03"}
            ]
          }
        ],
      }
    });
    expect(page.data, hasLength(1));
    expect(page.data.single.duration, 0);
    final part = page.data.single.musicList!.single;
    expect(part.name, "演出");
    expect(part.duration, 3723);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  const video = {
    "aid": 1,
    "bvid": "BVExample",
    "title": "第一交响曲",
    "pic": "http://i0.hdslb.com/video.jpg",
    "duration": 600,
    "ugc_season": {"mid": 7, "id": 8, "title": "交响曲全集"},
    "pages": [
      {
        "cid": 10,
        "part": "第一乐章",
        "duration": 300,
        "first_frame": "//i0.hdslb.com/first.jpg"
      },
      {"cid": 11, "part": "第二乐章", "duration": 300},
    ],
  };

  test("多分 P 和独立视频合集都保留作品名，收藏行和播放队列可以回读", () {
    final details = BiliSearchItem.fromJson(video);
    final first = details.musicList!.first;
    expect(first.id, "1_BVExample_10");
    expect(first.name, "第一乐章");
    expect(first.collectionName, "第一交响曲");
    expect(first.cover, "https://i0.hdslb.com/first.jpg");
    expect(details.musicList![1].cover, "https://i0.hdslb.com/video.jpg");
    expect(details.ugcSeason?.title, "交响曲全集");
    final shared = BiliVideoDetail.fromJson(video);
    expect(shared.seasonTitle, "交响曲全集");
    expect(shared.coverFor("10"), first.cover);
    expect(shared.coverFor("11"), details.musicList![1].cover);

    final season = BiliSearchSeasonItem.fromJson({
      "meta": {
        "mid": 7,
        "name": "第二交响曲",
        "season_id": 8,
        "cover": "//i0.hdslb.com/season.jpg"
      },
      "archives": [
        {
          "aid": 2,
          "bvid": "BVSecond",
          "title": "第一乐章",
          "pic": "",
          "duration": 300
        },
      ],
    });
    final second = season.musicList.single;
    expect(second.collectionName, "第二交响曲");
    expect(second.cover, "https://i0.hdslb.com/season.jpg");
    expect(second.name, first.name);
    expect(
        row2MusicItem(
            dbRow: musicItem2Row(
                music: second.copyWith(
          orderName: TableName.myMusic,
        ))).collectionName,
        "第二交响曲");
    expect(MusicItem.fromJson(first.toJson()).collectionName, "第一交响曲");
    final legacy = first.toJson()..remove("collectionName");
    expect(MusicItem.fromJson(legacy).collectionName, isEmpty);
  });

  test("补全旧历史后保留记录时间和次数，再播旧条目也保留合集名", () async {
    final first = BiliSearchItem.fromJson(video).musicList!.first;
    final legacy = first.copyWith(collectionName: "", cover: "");
    final playedAt = DateTime.fromMillisecondsSinceEpoch(1000);
    SharedPreferences.setMockInitialValues({
      "manman_play_history": jsonEncode([
        {"music": {"id": "invalid-time"}, "at": 9000000000000000},
        null,
        {"music": {}},
        HistoryEntry(music: legacy, playedAt: playedAt, count: 4).toJson(),
      ]),
    });
    final history = PlayHistory.instance;
    await history.fillMetadata(legacy.id,
        collectionName: first.collectionName, cover: first.cover);
    expect(history.entries.single.playedAt, playedAt);
    expect(history.entries.single.count, 4);
    await history.record(legacy);
    expect(history.entries.single.count, 5);
    expect(history.entries.single.music.collectionName, "第一交响曲");
    expect(history.entries.single.music.cover, first.cover);
  });

  test("同名本地文件分别记入历史并保留可重播路径", () async {
    final history = PlayHistory.instance;
    await history.clear();
    final track = BiliSearchItem.fromJson(video)
        .musicList!
        .first
        .copyWith(id: "", localPath: "/album-a/intro.mp3");
    final other = track.copyWith(localPath: "/album-b/intro.mp3");
    await history.record(track);
    await history.record(other);
    await history.record(track.copyWith(playId: "another-queue-entry"));
    expect(history.entries.map((entry) => entry.count), [2, 1]);
    final restored = HistoryEntry.fromJson(history.entries.first.toJson());
    expect(restored.music.localPath, track.localPath);
    expect(restored.matches(track), isTrue);
    expect(restored.matches(other), isFalse);
    final selected = restored.key;
    await history.record(track);
    expect(await history.removeWhere((entry) => entry.key == selected), 1);
    expect(history.entries.single.music.localPath, other.localPath);
  });

  testWidgets("合集副标题优先显示作品名，普通曲目仍然显示原副标题", (tester) async {
    final first = BiliSearchItem.fromJson(video).musicList!.first;
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      CollectionSubtitle(music: first, description: "作者甲", style: null),
      CollectionSubtitle(
          music: first.copyWith(collectionName: ""),
          description: "作者乙",
          style: null),
    ])));
    expect(find.text("第一交响曲"), findsOneWidget);
    expect(find.text("作者乙"), findsOneWidget);
  });
}
