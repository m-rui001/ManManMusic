import "package:bobomusic/components/music_list_tile/music_list_tile.dart";
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
      (index * 64.0).clamp(0, _scrollController.position.maxScrollExtent),
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
    final selectedColor = Theme.of(context).colorScheme.primaryContainer;
    final items = widget.musicList;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                  child: Text(
                "${items.length} 首",
                style: Theme.of(context).textTheme.labelMedium,
              )),
              if (widget.waiting)
                TextButton(
                  onPressed: items.isEmpty ? null : player.clearPlayerList,
                  child: const Text("清空"),
                ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(widget.waiting ? "待播放列表为空" : "还没有正在播放的歌曲"))
              : ListView.builder(
                  controller: _scrollController,
                  itemExtent: 64,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ColoredBox(
                      key: ValueKey(item.playId.isEmpty
                          ? "$index:${item.id}"
                          : item.playId),
                      color: _isCurrent(item, player.current)
                          ? selectedColor
                          : Colors.transparent,
                      child: MusicListTile(
                        item,
                        showAddIcon: false,
                        onMore: () => showItemSheet(context, item, player),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void showItemSheet(BuildContext context, MusicItem data, PlayerModel player) {
    openBottomSheet(context, [
      SheetItem(
        title: Text(
          data.name,
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.bold,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      SheetItem(
        title: const Text("播放"),
        onPressed: () => player.play(music: data),
      ),
      SheetItem(
        title: const Text("添加到歌单"),
        onPressed: () =>
            collectToMusicOrder(context: context, musicList: [data]),
      ),
      if (widget.waiting)
        SheetItem(
          title: const Text("移出待播放列表"),
          onPressed: () => player.removePlayerList([data]),
        )
      else
        SheetItem(
          title: const Text("添加到待播放列表"),
          onPressed: () => player.addPlayerList([data], showToast: true),
        ),
      SheetItem(
        title: const Text("下载"),
        onPressed: () {
          checkMusicLocalRepeat(context, data, () {
            final downloadModel =
                Provider.of<DownloadModel>(context, listen: false);
            downloadModel.download([data]);
          });
        },
      ),
    ]);
  }
}
