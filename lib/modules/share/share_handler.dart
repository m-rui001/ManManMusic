import "package:bobomusic/modules/party/party_page.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/modules/share/share_payload.dart";
import "package:bobomusic/origin_sdk/bili/utils.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/bili_link.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:provider/provider.dart";

/// 接收系统「分享到满满音乐」的文本（Android MethodChannel）
class IncomingShare {
  static const MethodChannel _channel = MethodChannel("manman/share");

  /// 注册回调
  static void listen(void Function(String text) onText) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == "onSharedText") {
        final text = call.arguments;
        if (text is String && text.isNotEmpty) onText(text);
      }
      return null;
    });

    // 冷启动时取一次
    _channel.invokeMethod<String>("getInitialSharedText").then((text) {
      if (text != null && text.isNotEmpty) onText(text);
    }).catchError((_) => null);
  }
}

/// 解析并播放一个 B 站分享链接 / 文本
///
/// 支持：完整视频链接、b23.tv 短链、微信/QQ 分享出来的一整段文字。
Future<void> openBiliShareText(BuildContext context, String text) async {
  final info = await parseBiliShareText(text);

  if (!context.mounted) return;

  if (info == null) {
    BotToast.showText(text: "没有识别到哔哩哔哩视频链接");
    return;
  }

  final detail = await fetchBiliVideoDetail(info);

  if (!context.mounted) return;

  if (detail == null || detail.pages.isEmpty) {
    BotToast.showText(text: "视频信息获取失败，可能已失效");
    return;
  }

  // 多分 P 时按分享里的 p 参数定位
  final targetPage = (info.page > 0 && info.page <= detail.pages.length)
      ? detail.pages[info.page - 1]
      : detail.pages.first;

  final musics = <MusicItem>[];
  for (int i = 0; i < detail.pages.length; i++) {
    final p = detail.pages[i];
    final title = detail.pages.length > 1
        ? (p.part.isNotEmpty ? p.part : "P${i + 1}")
        : detail.title;
    musics.add(
      MusicItem(
        id: BiliId(aid: detail.aid, bvid: detail.bvid, cid: p.cid).decode(),
        cover: detail.cover,
        name: title,
        duration: p.duration,
        author: detail.author,
        origin: OriginType.bili,
      ),
    );
  }

  final player = Provider.of<PlayerModel>(context, listen: false);

  if (musics.length == 1) {
    await player.play(music: musics.first);
    BotToast.showText(text: "正在播放：${musics.first.name}");
    return;
  }

  // 多 P：弹出选择
  final picked = await showModalBottomSheet<MusicItem>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      final primaryColor = Theme.of(ctx).primaryColor;
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.7,
        ),
        decoration: const BoxDecoration(
          color: Color.fromARGB(255, 245, 245, 245),
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Icon(Icons.playlist_play, size: 18, color: primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      detail.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              "共 ${musics.length} 个分 P，选择要播放的",
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 20),
                itemCount: musics.length,
                itemBuilder: (c, i) {
                  final m = musics[i];
                  final isTarget =
                      targetPage.cid.isNotEmpty && m.id.endsWith(targetPage.cid);
                  return ListTile(
                    dense: true,
                    leading: Text(
                      "P${i + 1}",
                      style: TextStyle(fontSize: 11, color: primaryColor),
                    ),
                    title: Text(
                      m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isTarget ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: Text(
                      _durationText(m.duration),
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    onTap: () => Navigator.of(c).pop(m),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );

  if (picked != null) {
    await player.play(music: picked);
  }
}

String _durationText(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return "$m:${s.toString().padLeft(2, "0")}";
}

/// 从剪贴板读取一条分享内容并解析
Future<void> openFromClipboard(BuildContext context) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text ?? "";

  if (text.isEmpty) {
    BotToast.showText(text: "剪贴板是空的");
    return;
  }

  final manman = parseManmanShareText(text);
  if (manman != null) {
    if (!context.mounted) return;
    await handleSharePayload(context, manman);
    return;
  }

  if (extractBiliUrl(text) == null) {
    BotToast.showText(text: "剪贴板里没有哔哩哔哩或满满音乐链接");
    return;
  }

  if (!context.mounted) return;
  await openBiliShareText(context, text);
}

/// 处理解析出来的满满音乐分享
Future<void> handleSharePayload(
  BuildContext context,
  SharePayload payload,
) async {
  final player = Provider.of<PlayerModel>(context, listen: false);

  if (payload.type == SharePayloadType.party) {
    final shouldJoin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("收到一起听邀请"),
        content: Text(
          "${payload.from.isEmpty ? "好友" : payload.from} 想和你一起听《${payload.name}》\n"
          "房间号：${payload.roomId}",
          style: const TextStyle(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("忽略"),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("加入"),
          ),
        ],
      ),
    );

    if (!context.mounted) return;

    if (shouldJoin == true) {
      // 先把分享的歌曲放上，随后由同步消息覆盖
      final music = payload.toMusicItem();
      if (music.id.isNotEmpty) {
        await player.play(music: music);
      }
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PartyJoinPage(roomId: payload.roomId),
        ),
      );
    }
    return;
  }

  // 单曲分享
  final music = payload.toMusicItem();
  if (music.id.isEmpty) {
    BotToast.showText(text: "分享内容已损坏");
    return;
  }

  await player.play(music: music);
  if (payload.position > 0) {
    await Future.delayed(const Duration(milliseconds: 500));
    await player.seek(Duration(milliseconds: payload.position));
  }

  BotToast.showText(text: "正在播放：${music.name}");
}
