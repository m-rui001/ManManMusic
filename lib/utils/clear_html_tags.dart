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

/// Parses seconds, minutes:seconds, or hours:minutes:seconds from video metadata.
int duration2seconds(String durationStr) {
  final parts = durationStr.trim().split(":");
  if (parts.length > 3) return 0;
  var total = 0;
  for (var i = 0; i < parts.length; i++) {
    final value = int.tryParse(parts[i], radix: 10);
    if (value == null || value < 0 || (i > 0 && value >= 60)) return 0;
    total = total * 60 + value;
  }
  return total;
}

/// Formats playback time in minutes and seconds.
String seconds2duration(int seconds) {
  int minutes = (seconds / 60).floor();
  int remainingSeconds = seconds % 60;
  String minutesStr = minutes.toString().padLeft(2, "0");
  String secondsStr = remainingSeconds.toString().padLeft(2, "0");
  return "$minutesStr:$secondsStr";
}
