final _htmlTag = RegExp(r"</?[A-Za-z][A-Za-z0-9:-]*(?:\s[^<>]*)?\s*/?>");
final _entity =
    RegExp(r"&(nbsp|amp|quot|apos|lt|gt|#[0-9]+|#[xX][0-9a-fA-F]+);");
const _namedEntities = {
  "nbsp": " ",
  "amp": "&",
  "quot": '"',
  "apos": "'",
  "lt": "<",
  "gt": ">",
};

String clearHtmlTags(String htmlText) {
  return htmlText
      .replaceAll(_htmlTag, "")
      .replaceAllMapped(_entity, (match) {
        final token = match[1]!;
        final named = _namedEntities[token];
        if (named != null) return named;
        final hex = token.startsWith("#x") || token.startsWith("#X");
        final code =
            int.tryParse(token.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
        if (code == null ||
            code <= 0 ||
            code > 0x10ffff ||
            (code >= 0xd800 && code <= 0xdfff)) return match[0]!;
        return code == 160 ? " " : String.fromCharCode(code);
      })
      .replaceAll("】", "-")
      .replaceAll("【", "");
}

/// 将 mm:ss 格式的时间转换为 秒
int duration2seconds(String durationStr) {
  if (durationStr.isEmpty) {
    return 0;
  }
  List<String> parts = durationStr.split(":");
  if (parts.length < 2) {
    return 0;
  }
  int minutes = int.tryParse(parts[0]) ?? 0;
  int seconds = int.tryParse(parts[1]) ?? 0;
  return minutes * 60 + seconds;
}

/// 将 mm:ss 格式的时间转换为 秒
String seconds2duration(int seconds) {
  int minutes = (seconds / 60).floor();
  int remainingSeconds = seconds % 60;
  String minutesStr = minutes.toString().padLeft(2, "0");
  String secondsStr = remainingSeconds.toString().padLeft(2, "0");
  return "$minutesStr:$secondsStr";
}
