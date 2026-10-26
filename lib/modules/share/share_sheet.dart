import "package:bobomusic/modules/party/party_service.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/modules/share/share_payload.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:provider/provider.dart";
import "package:share_plus/share_plus.dart";

/// 分享入口：单曲分享 / 一起听邀请
Future<void> showShareSheet(BuildContext context) async {
  final player = Provider.of<PlayerModel>(context, listen: false);
  final music = player.current;

  if (music == null) return;

  final position = player.currentPosition;

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final primaryColor = Theme.of(ctx).primaryColor;
      return Container(
        decoration: const BoxDecoration(
          color: Color.fromARGB(255, 245, 245, 245),
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.share_outlined, size: 18, color: primaryColor),
                const SizedBox(width: 8),
                const Text(
                  "分享",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              music.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            _ShareItem(
              icon: Icons.chat_bubble_outline,
              title: "分享给 QQ / 微信好友",
              desc: "发送歌曲链接，好友点开即可播放",
              onTap: () async {
                Navigator.of(ctx).pop();
                final payload = SharePayload.song(
                  music: music,
                  position: position.inMilliseconds,
                );
                await SharePlus.instance.share(
                  ShareParams(text: buildShareText(payload)),
                );
              },
            ),
            _ShareItem(
              icon: Icons.headphones_outlined,
              title: "邀请好友一起听",
              desc: "创建房间，好友加入后同步播放进度",
              onTap: () async {
                Navigator.of(ctx).pop();
                await showPartyInviteDialog(context);
              },
            ),
            _ShareItem(
              icon: Icons.bolt_outlined,
              title: "复制歌曲信息",
              desc: "复制歌名、作者和播放链接",
              onTap: () async {
                Navigator.of(ctx).pop();
                final payload = SharePayload.song(
                  music: music,
                  position: position.inMilliseconds,
                );
                await Clipboard.setData(
                  ClipboardData(text: buildShareText(payload)),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("已复制，去粘贴给好友吧"),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
      );
    },
  );
}

class _ShareItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback onTap;

  const _ShareItem({
    required this.icon,
    required this.title,
    required this.desc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 19, color: primaryColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

/// 创建房间并邀请
Future<void> showPartyInviteDialog(BuildContext context) async {
  final player = Provider.of<PlayerModel>(context, listen: false);
  final music = player.current;
  if (music == null) return;

  final party = PartyService.instance;
  final ok = await party.createRoom(name: "房主");

  if (!context.mounted) return;

  final roomId = party.roomId;
  final payload = SharePayload.party(
    music: music,
    position: player.currentPosition.inMilliseconds,
    roomId: roomId,
  );

  await showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(ok ? "房间已创建" : "无法创建房间"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ok) ...[
              const Text("把下面的房间号或邀请发给好友：", style: TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              SelectableText(
                roomId,
                style: TextStyle(
                  fontSize: 28,
                  letterSpacing: 6,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(ctx).primaryColor,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "房主切换歌曲、拖动进度时，好友会自动跟随",
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ] else ...[
              const Text(
                "连接公共同步服务器失败，请检查网络后重试。",
                style: TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          if (ok)
            TextButton(
              onPressed: () async {
                await SharePlus.instance.share(ShareParams(text: buildShareText(payload)));
              },
              child: const Text("发送邀请"),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("关闭"),
          ),
        ],
      );
    },
  );
}
