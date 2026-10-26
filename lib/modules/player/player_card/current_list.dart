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
  const CurrentList({super.key, required this.musicList});

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
    final player = Provider.of<PlayerModel>(context, listen: false);
    if (player.current == null) return;

    // 找到当前播放歌曲在列表中的索引
    int? targetIndex;
    for (int i = 0; i < widget.musicList.length; i++) {
      final item = widget.musicList[i];
      // 优先通过 playId 匹配，再通过 id 匹配
      if (item.playId.isNotEmpty && player.current!.playId.isNotEmpty && item.playId == player.current!.playId) {
        targetIndex = i;
        break;
      } else if (item.id == player.current!.id) {
        targetIndex = i;
        break;
      }
    }

    // 如果找到目标索引，则滚动到该位置
    if (targetIndex != null && _scrollController.hasClients) {
      // 每首歌大约 60 像素高度（估算），如果更准确的话可以通过 GlobalKey 计算
      const double itemHeight = 60;
      final double scrollOffset = targetIndex * itemHeight;

      // 滚动到目标位置
      _scrollController.animateTo(
        scrollOffset.clamp(0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    double height = MediaQuery.of(context).size.height * 0.6;
    double topHeight = 56;
    return Consumer<PlayerModel>(
      builder: (context, player, child) {
        return SizedBox(
          height: height,
          width: MediaQuery.of(context).size.width,
          child: Flex(
            direction: Axis.vertical,
            children: [
              _buildTopBar(context, player, topHeight),
              _buildList(context, player, height - topHeight)
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context, PlayerModel player, double topHeight) {
    return Container(
      height: topHeight,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const Text(
                  "当前播放列表",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 10),
                Text(
                  "${widget.musicList.length}首歌曲",
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).disabledColor,
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, PlayerModel player, double h) {
    if (widget.musicList.isEmpty) {
      return const Center(child: Text("没有歌曲"));
    }

    return SizedBox(
      height: h,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: widget.musicList.length,
        itemBuilder: (context, index) {
          final item = widget.musicList[index];
          // 检查是否是当前播放的歌曲
          final isCurrentPlaying = (item.playId.isNotEmpty && player.current?.playId.isNotEmpty == true && item.playId == player.current?.playId) ||
              (item.id == player.current?.id);

          return Container(
            decoration: isCurrentPlaying
                ? BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  )
                : null,
            child: MusicListTile(
              item,
              showAddIcon: false,
              onMore: () => showItemSheet(context, item, player),
            ),
          );
        },
      ),
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
        onPressed: () => collectToMusicOrder(context: context, musicList: [data]),
      ),
      SheetItem(
        title: const Text("添加到待播放列表"),
        onPressed: () => player.addPlayerList([data], showToast: true),
      ),
      SheetItem(
        title: const Text("下载"),
        onPressed: () {
          checkMusicLocalRepeat(context, data, () {
            final downloadModel = Provider.of<DownloadModel>(context, listen: false);
            downloadModel.download([data]);
          });
        },
      ),
    ]);
  }
}
