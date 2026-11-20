import "package:bobomusic/origin_sdk/bili/subtitle.dart";
import "package:bobomusic/modules/player/utils.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("多行字幕往返转换保留时间和整句文本", () {
    final lrc = subtitleToLrc({
      "body": [
        {"from": -1, "content": "无效"},
        {"from": double.infinity, "content": "无效"},
        {"from": 6001.34, "content": " 上半句\r\n下半句 "},
      ]
    });
    expect(lrc, "[100:01.34]上半句 下半句");
    expect(parseLyrics(lrc!), [
      {"time": 6001340, "text": "上半句 下半句"}
    ]);
    expect(
        parseLyrics("[00:01.5]A\n[00:02.125]B\n[00:03]C")
            .map((row) => row["time"]),
        [1500, 2125, 3000]);
  });

  test("B 站字幕时间戳转成 LRC，空字幕返回 null", () {
    final lrc = subtitleToLrc({
      "body": [
        {"from": 0.0, "to": 2.5, "content": "第一句"},
        {"from": 25.34, "to": 28.0, "content": "第二句"},
        {"from": 61.5, "to": 64.0, "content": "第三句"},
      ],
    });
    expect(lrc,
        "[00:00.00]第一句\n[00:02.50]\n[00:25.34]第二句\n[00:28.00]\n[01:01.50]第三句\n[01:04.00]");
    expect(parseLyrics(lrc!).map((row) => row["end"]), [2500, 28000, 64000]);
    expect(subtitleToLrc({"body": []}), isNull);
    expect(subtitleToLrc({}), isNull);
  });

  test("百分秒进位不会写出 [00:01.100] 这种非法时间戳", () {
    final lrc = subtitleToLrc({
      "body": [
        {"from": 1.999, "content": "进位"},
        {"from": 59.999, "content": "跨分"},
      ],
    });
    expect(lrc, "[00:02.00]进位\n[01:00.00]跨分");
  });

  test("跳过空行和坏数据，保留有效字幕", () {
    final lrc = subtitleToLrc({
      "body": [
        {"from": 1.0, "content": "  "},
        {"from": "坏", "content": "无效"},
        {"from": 3.0, "content": "有效"},
      ],
    });
    expect(lrc, "[00:03.00]有效");
  });
}
