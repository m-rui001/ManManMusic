import "package:bobomusic/modules/player/model.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

Future<void> showAudioOptions(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const _AudioDetails(),
    );

/// 音轨品质面板
///
/// 之前只有一行「当前音轨：FLAC · 约 900 kbps」，
/// 用户看不出这到底算好还是一般。这里把格式、码率、来源拆开讲清楚。
class _AudioDetails extends StatelessWidget {
  const _AudioDetails();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final track = player.current;
    final info = _parse(player.sourceDescription);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("音轨品质",
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(
              track == null ? "还没有载入歌曲" : track.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: colors.secondaryContainer.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Icon(info.icon, size: 26, color: colors.onSecondaryContainer),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.format.isEmpty ? "未知音轨" : info.format,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (info.tier.isNotEmpty) info.tier,
                            if (info.bitrate.isNotEmpty) info.bitrate,
                          ].join(" · "),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSecondaryContainer
                                .withValues(alpha: .8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _row(context, "播放来源", info.source),
            _row(context, "编码格式", info.format.isEmpty ? "未知" : info.format),
            _row(context, "码率", info.bitrate.isEmpty ? "未知" : info.bitrate),
            if (info.restricted) ...[
              const SizedBox(height: 10),
              Text(
                "无损与杜比音轨要登录哔哩哔哩账号才拿得到，未登录时会自动退回普通音轨。",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  _TrackInfo _parse(String description) {
    var format = "";
    var bitrate = "";
    var source = "在线播放";
    for (final part in description.split(" · ")) {
      final token = part.trim();
      if (token.isEmpty) continue;
      if (token == "本机缓存") {
        source = "本机缓存";
      } else if (token == "本地文件") {
        source = "本地文件";
      } else if (token == "在线音轨") {
        source = "在线播放";
      } else if (token.startsWith("约 ") && token.endsWith("kbps")) {
        bitrate = token;
      } else {
        format = token;
      }
    }
    final kbps = int.tryParse(
            RegExp(r"(\d+)").firstMatch(bitrate)?.group(1) ?? "") ??
        0;
    final tier = switch (format) {
      "FLAC" => "无损",
      "杜比音轨" => "杜比全景声",
      _ => kbps >= 320
          ? "极高音质"
          : kbps >= 192
              ? "高音质"
              : kbps > 0
                  ? "标准音质"
                  : "",
    };
    return _TrackInfo(
      format: format,
      bitrate: bitrate,
      source: source,
      tier: tier,
      restricted: format == "FLAC" || format == "杜比音轨",
      icon: switch (format) {
        "FLAC" => Icons.workspace_premium_outlined,
        "杜比音轨" => Icons.surround_sound_outlined,
        "本地文件" => Icons.folder_outlined,
        _ => source == "本机缓存"
            ? Icons.offline_pin_outlined
            : Icons.graphic_eq_rounded,
      },
    );
  }
}

class _TrackInfo {
  final String format;
  final String bitrate;
  final String source;
  final String tier;
  final bool restricted;
  final IconData icon;

  const _TrackInfo({
    required this.format,
    required this.bitrate,
    required this.source,
    required this.tier,
    required this.restricted,
    required this.icon,
  });
}