import "package:bobomusic/components/continuous_rounding.dart";
import "package:bobomusic/modules/player/artwork.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class MusicListTile extends StatelessWidget {
  final MusicItem music;
  final VoidCallback onMore;
  final VoidCallback? onPlay;
  final bool showAddIcon;
  final bool showOrderName;
  final bool showOrgin;

  const MusicListTile(
    this.music, {
    super.key,
    required this.onMore,
    this.onPlay,
    this.showAddIcon = true,
    this.showOrderName = false,
    this.showOrgin = true,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final current = player.current;
    final active = current != null &&
        current.orderName == music.orderName &&
        (current.playId.isNotEmpty && current.orderName.isNotEmpty
            ? current.playId == music.playId
            : current.id == music.id);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final description = [
      if (showOrgin) music.origin.name,
      if (music.author.isNotEmpty) clearHtmlTags(music.author),
      if (showOrderName && music.orderName.isNotEmpty) music.orderName,
      if (music.duration > 0) seconds2duration(music.duration),
    ].join(" · ");

    const shape = ContinuousRounding(17);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: active ? colors.secondaryContainer : Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          shape: shape,
          contentPadding: const EdgeInsetsDirectional.only(start: 10, end: 4),
          leading: TrackArtwork(cover: music.cover, size: 46),
          title: Text(
            clearHtmlTags(music.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? colors.onSecondaryContainer : colors.onSurface,
            ),
          ),
          subtitle: description.isEmpty
              ? null
              : Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (active)
                Icon(
                  player.isPlaying
                      ? Icons.graphic_eq_rounded
                      : Icons.pause_rounded,
                  color: colors.onSecondaryContainer,
                  size: 18,
                ),
              if (showAddIcon)
                IconButton(
                  icon: const Icon(Icons.playlist_add_rounded, size: 21),
                  tooltip: "加入待播放",
                  onPressed: () =>
                      player.addPlayerList([music], showToast: true),
                ),
              IconButton(
                icon: const Icon(Icons.more_horiz_rounded, size: 21),
                tooltip: "曲目选项",
                onPressed: onMore,
              ),
            ],
          ),
          onTap: onPlay ?? () => player.play(music: music),
          onLongPress: onMore,
        ),
      ),
    );
  }
}
