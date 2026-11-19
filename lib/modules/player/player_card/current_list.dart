import "package:bobomusic/modules/player/artwork.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:bobomusic/modules/download/model.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:bobomusic/utils/check_music_local_repeat.dart";
import "package:flutter/material.dart";
import "package:bobomusic/components/sheet/bottom_sheet.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:provider/provider.dart";

class CurrentList extends StatefulWidget {
  final List<MusicItem> musicList;
  final bool waiting;
  const CurrentList({super.key, required this.musicList, this.waiting = false});

  @override
  State<CurrentList> createState() => CurrentListState();
}

class CurrentListState extends State<CurrentList> {
  final ScrollController _scrollController = ScrollController();
  static const _rowHeight = 66.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentSong();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentSong() {
    if (!mounted) return;
    final player = Provider.of<PlayerModel>(context, listen: false);
    if (player.current == null) return;

    final index =
        widget.musicList.indexWhere((item) => _isCurrent(item, player.current));
    if (index < 0 || !_scrollController.hasClients) return;
    _scrollController.jumpTo(
      (index * _rowHeight).clamp(0, _scrollController.position.maxScrollExtent),
    );
  }

  bool _isCurrent(MusicItem item, MusicItem? current) {
    if (current == null) return false;
    if (item.playId.isNotEmpty) return item.playId == current.playId;
    return item.id == current.id && item.orderName == current.orderName;
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final items = widget.musicList;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(21, 2, 12, 2),
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "${items.length} 首",
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (widget.waiting)
                  TextButton.icon(
                    onPressed: items.isEmpty ? null : player.clearPlayerList,
                    icon: const Icon(Icons.clear_all_rounded, size: 19),
                    label: const Text("清空"),
                  )
                else
                  IconButton(
                    tooltip: "定位到当前曲目",
                    onPressed:
                        items.any((item) => _isCurrent(item, player.current))
                            ? _scrollToCurrentSong
                            : null,
                    icon: const Icon(Icons.my_location_rounded, size: 19),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    widget.waiting ? "待播放列表为空" : "还没有正在播放的歌曲",
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  itemExtent: _rowHeight,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final active = _isCurrent(item, player.current);
                    void overflow() => showItemSheet(context, item, player);
                    return Padding(
                      key: ValueKey(item.playId.isEmpty
                          ? "$index:${item.id}"
                          : item.playId),
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Material(
                        color: active
                            ? colors.secondaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => player.play(music: item),
                          onLongPress: overflow,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Row(
                              children: [
                                TrackArtwork(music: item, size: 44),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        clearHtmlTags(item.name),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                          fontWeight: active
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                      if (item.author.isNotEmpty)
                                        Text(
                                          clearHtmlTags(item.author),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (active)
                                  Icon(
                                    player.isPlaying
                                        ? Icons.graphic_eq_rounded
                                        : Icons.pause_rounded,
                                    color: colors.onSecondaryContainer,
                                    size: 18,
                                  ),
                                IconButton(
                                  tooltip: "曲目选项",
                                  onPressed: overflow,
                                  icon: const Icon(Icons.more_horiz_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void showItemSheet(BuildContext context, MusicItem data, PlayerModel player) {
    openBottomSheet(
      context,
      [
        SheetItem(
          title: "播放",
          icon: Icons.play_arrow_rounded,
          onPressed: () => player.play(music: data),
        ),
        SheetItem(
          title: "收藏到歌单",
          icon: Icons.favorite_border_rounded,
          onPressed: () =>
              collectToMusicOrder(context: context, musicList: [data]),
        ),
        if (widget.waiting)
          SheetItem(
            title: "移出待播放",
            icon: Icons.playlist_remove_rounded,
            onPressed: () => player.removePlayerList([data]),
          )
        else
          SheetItem(
            title: "添加到待播放",
            icon: Icons.playlist_add_rounded,
            onPressed: () => player.addPlayerList([data], showToast: true),
          ),
        if (data.localPath.isEmpty)
          SheetItem(
            title: "下载",
            icon: Icons.download_rounded,
            onPressed: () {
              checkMusicLocalRepeat(context, data, () {
                final downloadModel =
                    Provider.of<DownloadModel>(context, listen: false);
                downloadModel.download([data]);
              });
            },
          ),
      ],
      header: SheetHeader(
        title: clearHtmlTags(data.name),
        subtitle: clearHtmlTags(data.author),
        track: data,
      ),
    );
  }
}
