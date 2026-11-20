import "package:bobomusic/components/continuous_rounding.dart";
import "package:bobomusic/components/playing_bars.dart";
import "package:bobomusic/components/pressable.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/modules/music_order/collection_subtitle.dart";
import "package:bobomusic/modules/player/artwork.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:bobomusic/utils/haptics.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class MusicListTile extends StatelessWidget {
  final MusicItem music;
  final VoidCallback onMore;
  final VoidCallback? onPlay;
  final bool showAddIcon;
  final bool showOrderName;
  final bool showOrgin;
  final bool showCollectionName;

  const MusicListTile(
    this.music, {
    super.key,
    required this.onMore,
    this.onPlay,
    this.showAddIcon = true,
    this.showOrderName = false,
    this.showOrgin = true,
    this.showCollectionName = true,
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
      if (showOrderName && music.orderName.isNotEmpty)
        music.orderName == TableName.myMusic ? "我的歌单" : music.orderName,
      if (music.duration > 0) seconds2duration(music.duration),
    ].join(" · ");

    const shape = ContinuousRounding(17);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Pressable(
        pressScale: .985,
        pressedColor: colors.onSurface.withValues(alpha: .08),
        pressedBorderRadius: BorderRadius.circular(17),
        child: Material(
          color: active ? colors.secondaryContainer : Colors.transparent,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            shape: shape,
            contentPadding: const EdgeInsetsDirectional.only(start: 10, end: 4),
            leading: TrackArtwork(music: music, size: 46),
            title: Text(
              clearHtmlTags(music.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? colors.onSecondaryContainer : colors.onSurface,
              ),
            ),
            subtitle: CollectionSubtitle(
              music: music,
              description: description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
              showCollectionName: showCollectionName,
              restoreLegacy: music.orderName == TableName.myMusic,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (active)
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: PlayingBars(
                      playing: player.isPlaying,
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                if (showAddIcon)
                  IconButton(
                    icon: const Icon(Icons.playlist_add_rounded, size: 21),
                    tooltip: "加入待播放",
                    onPressed: () {
                      AppHaptics.action();
                      player.addPlayerList([music], showToast: true);
                    },
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
      ),
    );
  }
}
