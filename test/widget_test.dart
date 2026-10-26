import "package:bobomusic/constants/app_info.dart";
import "package:bobomusic/origin_sdk/bili/utils.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
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
}
