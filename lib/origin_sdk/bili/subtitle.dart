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
    if (!from.isFinite || from < 0) continue;
    final line = content.trim().replaceAll(RegExp(r"[\r\n]+"), " ");
    buffer.writeln("${_timestamp(from)}$line");
    final to = item["to"];
    if (to is num && to.isFinite && to > from) {
      // A timed empty LRC line marks the silence following this sentence.
      buffer.writeln(_timestamp(to));
    }
  }
  final lrc = buffer.toString().trim();
  return lrc.isEmpty ? null : lrc;
}

String _two(int value) => value.toString().padLeft(2, "0");

String _timestamp(num seconds) {
  final centis = (seconds * 100).round();
  return "[${_two(centis ~/ 6000)}:${_two(centis ~/ 100 % 60)}.${_two(centis % 100)}]";
}
