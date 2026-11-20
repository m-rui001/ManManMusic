import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:bobomusic/utils/haptics.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/services.dart";

/// 长按复制曲名（去掉搜索高亮标签后的干净文本）
Future<void> copyTrackName(MusicItem music) async {
  final name = clearHtmlTags(music.name).trim();
  if (name.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: name));
  AppHaptics.selection();
  BotToast.showText(text: "已复制曲名");
}
