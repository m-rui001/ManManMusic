import "package:bobomusic/constants/app_info.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/modules/bili_account/fav_sync.dart";
import "package:bobomusic/modules/history/play_history.dart";
import "package:bobomusic/modules/party/party_roster.dart";
import "package:bobomusic/modules/party/party_service.dart";
import "package:bobomusic/modules/share/share_payload.dart";
import "package:bobomusic/origin_sdk/bili/utils.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/bili_link.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  group("应用信息", () {
    test("应用名为满满音乐", () {
      expect(appName, "满满音乐");
    });

    test("logo 资源路径指向 assets/logo.png", () {
      expect(appLogoAsset, "assets/logo.png");
    });
  });

  _moreTests();

  group("BiliId 编解码", () {
    test("只含 aid 与 bvid 时往返一致", () {
      final id = BiliId(aid: "1", bvid: "BV1xx411c7mD").decode();
      expect(id, "1_BV1xx411c7mD");

      final parsed = BiliId.unicode(id);
      expect(parsed.aid, "1");
      expect(parsed.bvid, "BV1xx411c7mD");
      expect(parsed.cid, "");
    });

    test("含 cid 时往返一致", () {
      final id = BiliId(aid: "1", bvid: "BV1xx411c7mD", cid: "123").decode();
      expect(id, "1_BV1xx411c7mD_123");

      final parsed = BiliId.unicode(id);
      expect(parsed.cid, "123");
    });

    test("格式错误时抛出异常", () {
      expect(() => BiliId.unicode("not-valid"), throwsA(isA<Exception>()));
    });
  });

  group("时间转换", () {
    test("mm:ss 转秒", () {
      expect(duration2seconds("03:20"), 200);
      expect(duration2seconds("00:00"), 0);
    });

    test("异常输入返回 0", () {
      expect(duration2seconds(""), 0);
      expect(duration2seconds("abc"), 0);
    });

    test("秒转 mm:ss", () {
      expect(seconds2duration(200), "03:20");
      expect(seconds2duration(0), "00:00");
      expect(seconds2duration(3600), "60:00");
    });
  });

  group("清理 html 标签", () {
    test("去掉标签并替换实体", () {
      expect(clearHtmlTags("<em>周杰伦</em>&nbsp;稻香"), "周杰伦 稻香");
    });
  });

  group("MusicItem 序列化", () {
    test("toJson / fromJson 往返一致", () {
      final music = MusicItem(
        id: "1_BV1_1",
        cover: "https://example.com/cover.jpg",
        name: "测试歌曲",
        duration: 200,
        author: "测试作者",
        origin: OriginType.bili,
        orderName: "我喜欢",
        playId: "play-1",
      );

      final restored = MusicItem.fromJson(music.toJson());

      expect(restored.id, music.id);
      expect(restored.name, music.name);
      expect(restored.duration, music.duration);
      expect(restored.origin, OriginType.bili);
      expect(restored.orderName, "我喜欢");
      expect(restored.playId, "play-1");
    });
  });

  group("收藏夹同步记录", () {
    test("FavBinding 往返一致", () {
      final b = FavBinding(
        favId: 123456,
        title: "我的最爱",
        mediaCount: 42,
        syncedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      final restored = FavBinding.fromJson(b.toJson());

      expect(restored.favId, 123456);
      expect(restored.title, "我的最爱");
      expect(restored.mediaCount, 42);
      expect(restored.syncedAt.millisecondsSinceEpoch, 1700000000000);
    });

    test("缺少字段时回退到安全默认值", () {
      final restored = FavBinding.fromJson(<String, dynamic>{});

      expect(restored.favId, 0);
      expect(restored.title, "");
      expect(restored.mediaCount, 0);
    });

    test("copyWith 只覆盖指定字段", () {
      final b = FavBinding(
        favId: 1,
        title: "t",
        mediaCount: 1,
        syncedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

      final c = b.copyWith(mediaCount: 9);

      expect(c.favId, 1);
      expect(c.title, "t");
      expect(c.mediaCount, 9);
    });
  });

  group("一起听名单", () {
    test("RosterMember 往返一致", () {
      const m = RosterMember(mid: 12345, uname: "小明", face: "https://x/a.jpg");
      final restored = RosterMember.fromJson(m.toJson());

      expect(restored.mid, 12345);
      expect(restored.uname, "小明");
      expect(restored.face, "https://x/a.jpg");
    });

    test("房间号由 UID 派生", () {
      const m = RosterMember(mid: 12345, uname: "小明", face: "");
      expect(m.roomId, "bili_12345");
    });

    test("缺字段时回退到安全默认值", () {
      final restored = RosterMember.fromJson(<String, dynamic>{});
      expect(restored.mid, 0);
      expect(restored.uname, "");
      expect(restored.face, "");
      expect(restored.canControl, isFalse);
    });

    test("共管标记能存下来", () {
      const m = RosterMember(mid: 1, uname: "小明", face: "", canControl: true);
      expect(RosterMember.fromJson(m.toJson()).canControl, isTrue);
      expect(m.copyWith(canControl: false).canControl, isFalse);
    });
  });

  group("一起听协议", () {
    test("状态消息带 uid 与共管名单", () {
      const state = PartyState(
        type: PartyMessageType.state,
        roomId: "bili_123",
        from: "c1",
        uid: 123,
        fromName: "房主",
        musicId: "1_BV1_2",
        name: "歌名",
        position: 1000,
        playing: true,
        at: 1700000000000,
        controlUids: [123, 456],
      );

      final restored = PartyState.fromJson(state.toJson());

      expect(restored.type, PartyMessageType.state);
      expect(restored.uid, 123);
      expect(restored.controlUids, [123, 456]);
      expect(restored.position, 1000);
      expect(restored.playing, isTrue);
      expect(restored.toMusicItem()!.id, "1_BV1_2");
    });

    test("拒绝消息带目标 uid", () {
      const deny = PartyState(
        type: PartyMessageType.deny,
        roomId: "bili_123",
        from: "host",
        uid: 123,
        at: 1,
        toUid: 789,
      );

      final restored = PartyState.fromJson(deny.toJson());
      expect(restored.type, PartyMessageType.deny);
      expect(restored.toUid, 789);
    });

    test("房间号能解析出房主 UID", () {
      expect(PartyService.hostUidFromRoom("bili_123456"), 123456);
      expect(PartyService.hostUidFromRoom("u12345"), 0);
      expect(PartyService.hostUidFromRoom(""), 0);
    });
  });

  group("歌单表结构", () {
    test("建表语句带 IF NOT EXISTS，重复导入不会再撞名", () {
      final sql = orderTableSql(TableName.myMusic);
      expect(sql.contains("CREATE TABLE IF NOT EXISTS"), isTrue);
      expect(sql.contains(TableName.myMusic), isTrue);
    });

    test("满满音乐是唯一的主歌单", () {
      expect(TableName.myMusic, "满满音乐");
      expect(TableName.myMusic == TableName.musicLocal, isFalse);
    });
  });

  group("历史播放条目序列化", () {
    test("HistoryEntry 往返一致", () {
      final music = MusicItem(
        id: "1_BV1xx411c7mD_2",
        cover: "https://example.com/c.jpg",
        name: "历史里的歌",
        duration: 180,
        author: "某个UP",
        origin: OriginType.bili,
        playId: "p-9",
        orderName: "我喜欢",
      );

      final entry = HistoryEntry(
        music: music,
        playedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        count: 3,
      );

      final restored = HistoryEntry.fromJson(entry.toJson());

      expect(restored.music.id, music.id);
      expect(restored.music.name, music.name);
      expect(restored.music.author, music.author);
      expect(restored.music.duration, music.duration);
      expect(restored.music.playId, "p-9");
      expect(restored.music.orderName, "我喜欢");
      expect(restored.music.origin, OriginType.bili);
      expect(restored.playedAt.millisecondsSinceEpoch, 1700000000000);
      expect(restored.count, 3);
    });

    test("缺少字段时回退到安全默认值", () {
      final restored = HistoryEntry.fromJson(<String, dynamic>{});

      expect(restored.music.id, "");
      expect(restored.music.duration, 0);
      expect(restored.count, 1);
      expect(restored.music.origin, OriginType.bili);
    });
  });
}

// ===== 新增测试（分享 / 链接解析 / 一起听） =====

void _moreTests() {
  group("分享载荷编解码", () {
    test("单曲分享往返一致", () {
      const payload = SharePayload(
        type: SharePayloadType.music,
        musicId: "123_BV1xx411c7mD_456",
        origin: "bili",
        name: "某个视频标题",
        author: "某个UP主",
        cover: "https://i0.hdslb.com/cover.jpg",
        duration: 213,
        position: 41000,
        from: "小明",
      );

      final code = payload.encode();
      final decoded = SharePayload.decode(code);

      expect(decoded, isNotNull);
      expect(decoded!.type, SharePayloadType.music);
      expect(decoded.musicId, payload.musicId);
      expect(decoded.name, payload.name);
      expect(decoded.author, payload.author);
      expect(decoded.duration, 213);
      expect(decoded.position, 41000);
      expect(decoded.from, "小明");
    });

    test("一起听分享带房间号", () {
      const payload = SharePayload(
        type: SharePayloadType.party,
        musicId: "1_BV1xx411c7mD_2",
        name: "歌名",
        roomId: "123456",
      );
      final decoded = SharePayload.decode(payload.encode());
      expect(decoded!.type, SharePayloadType.party);
      expect(decoded.roomId, "123456");
    });

    test("中文与 emoji 能正确还原", () {
      const payload = SharePayload(
        type: SharePayloadType.music,
        musicId: "1_BV1xx411c7mD_2",
        name: "夜に駆ける 🎵「测试」",
        from: "小王",
      );
      final decoded = SharePayload.decode(payload.encode());
      expect(decoded!.name, "夜に駆ける 🎵「测试」");
      expect(decoded.from, "小王");
    });

    test("编码结果不含 URL 不安全字符", () {
      const payload = SharePayload(
        type: SharePayloadType.music,
        musicId: "1_BV1xx411c7mD_2",
        name: "测试",
      );
      final code = payload.encode();
      expect(code.contains("+"), isFalse);
      expect(code.contains("/"), isFalse);
      expect(code.contains("="), isFalse);
    });

    test("损坏的编码返回 null 而不抛异常", () {
      expect(SharePayload.decode("!!!!"), isNull);
      expect(SharePayload.decode(""), isNull);
      expect(SharePayload.decode("YWJj"), isNull);
    });
  });

  group("分享链接", () {
    test("生成的链接能被解析回来", () {
      const payload = SharePayload(
        type: SharePayloadType.music,
        musicId: "1_BV1xx411c7mD_2",
        name: "一首歌",
        roomId: "",
      );
      final link = buildManmanLink(payload);
      expect(link.startsWith("manman://play?d="), isTrue);

      final parsed = parseManmanUri(Uri.parse(link));
      expect(parsed, isNotNull);
      expect(parsed!.name, "一首歌");
      expect(parsed.musicId, "1_BV1xx411c7mD_2");
    });

    test("能从整段分享文案里提取链接", () {
      const payload = SharePayload(
        type: SharePayloadType.music,
        musicId: "1_BV1xx411c7mD_2",
        name: "测试歌曲",
      );
      final text = buildShareText(payload);
      final parsed = parseManmanShareText(text);
      expect(parsed, isNotNull);
      expect(parsed!.name, "测试歌曲");
    });

    test("非满满音乐的文本解析为 null", () {
      expect(parseManmanShareText("今天天气不错"), isNull);
      expect(parseManmanUri(Uri.parse("https://www.bilibili.com")), isNull);
    });
  });

  group("B 站链接解析", () {
    test("识别完整视频链接", () {
      final info = parseBiliUrl("https://www.bilibili.com/video/BV1xx411c7mD");
      expect(info, isNotNull);
      expect(info!.bvid, "BV1xx411c7mD");
      expect(info.page, 1);
    });

    test("识别分 P 参数", () {
      final info = parseBiliUrl(
        "https://www.bilibili.com/video/BV1xx411c7mD?p=3&t=10",
      );
      expect(info!.page, 3);
    });

    test("识别 av 号", () {
      final info = parseBiliUrl("https://www.bilibili.com/video/av170001");
      expect(info, isNotNull);
      expect(info!.aid, "170001");
    });

    test("从微信/QQ 分享文本里提取链接", () {
      const text = "【某视频】这个太好听了 https://b23.tv/abcdefg 快来看";
      final url = extractBiliUrl(text);
      expect(url, "https://b23.tv/abcdefg");
    });

    test("链接尾部的中文标点会被去掉", () {
      const text = "看这个 https://www.bilibili.com/video/BV1xx411c7mD，好笑";
      final url = extractBiliUrl(text);
      expect(url, "https://www.bilibili.com/video/BV1xx411c7mD");
      expect(parseBiliUrl(url!)!.bvid, "BV1xx411c7mD");
    });

    test("非 B 站链接返回 null", () {
      expect(extractBiliUrl("https://example.com/video/1"), isNull);
      expect(parseBiliUrl("https://example.com/video/1"), isNull);
    });
  });
}
