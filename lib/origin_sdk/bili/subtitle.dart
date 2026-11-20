/// B 站 CC 字幕 JSON → LRC
///
/// 字幕接口给的是 {body: [{from, to, content}]}，from / to 是秒（带小数）。
/// 歌词组件吃标准 LRC，这里把时间戳写成 [分:秒.百分秒]。
String? subtitleToLrc(Map<String, dynamic> json) {
  final body = json["body"];
  if (body is! List || body.isEmpty) return null;
  final buffer = StringBuffer();
  for (final item in body.whereType<Map>()) {
    final from = item["from"];
    final content = item["content"];
    if (from is! num || content is! String || content.trim().isEmpty) continue;
    final total = from.toDouble();
    var minutes = total ~/ 60;
    var seconds = total.floor() % 60;
    var centis = ((total - total.floorToDouble()) * 100).round();
    // 1.999 秒会进位成 100 百分秒，逐级进上去
    if (centis >= 100) {
      centis -= 100;
      seconds += 1;
    }
    if (seconds >= 60) {
      seconds -= 60;
      minutes += 1;
    }
    buffer
        .writeln("[${_two(minutes)}:${_two(seconds)}.${_two(centis)}]$content");
  }
  final lrc = buffer.toString().trim();
  return lrc.isEmpty ? null : lrc;
}

String _two(int value) => value.toString().padLeft(2, "0");
