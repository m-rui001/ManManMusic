// ignore_for_file: library_private_types_in_public_api

import "package:bobomusic/components/music_list_tile/music_list_tile.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/modules/download/model.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:bobomusic/utils/check_music_local_repeat.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:bobomusic/components/sheet/bottom_sheet.dart";
import "package:bobomusic/modules/player/player.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";
import "package:provider/provider.dart";

final DBOrder db = DBOrder();

class Menus {
  static String allAddToWaitPlayList = "全部加入待播放列表";
  static String allAddToOrders = "全部加入到歌单";
}

class MusicOrderDetail extends StatefulWidget {
  final MusicOrderItem musicOrderItem;
  final bool shouldLoadData;

  const MusicOrderDetail({super.key, required this.musicOrderItem, required this.shouldLoadData});

  @override
  MusicOrderDetailState createState() => MusicOrderDetailState();
}

class MusicOrderDetailState extends State<MusicOrderDetail> {
  late MusicOrderItem musicOrder;
  List<MusicItem> musicList = [];

  final Map<String, IconData> menuBtnMap = {
    Menus.allAddToWaitPlayList: Icons.queue_music_outlined,
    Menus.allAddToOrders: Icons.library_music_rounded,
  };

  @override
  initState() {
    super.initState();
    musicOrder = widget.musicOrderItem;

    if (widget.shouldLoadData) {
      _loadData();
    } else {
      setState(() {
        musicList = musicOrder.musicList;
      });
    }
  }

  Future<void> _loadData() async {
    EasyLoading.show(maskType: EasyLoadingMaskType.black);
    try {
      final dbMusics = await getUpdatedMusicList(tabName: musicOrder.name);

      if (dbMusics.isNotEmpty) {
        setState(() {
          musicList = dbMusics;
        });
      }
    } catch (error) {
      print(error);
    }

    EasyLoading.dismiss();
  }

  void _play(MusicItem item) {
    Provider.of<PlayerModel>(context, listen: false).play(
      music: item,
      collection: widget.shouldLoadData ? null : musicList,
    );
  }

  _moreHandler(BuildContext context, MusicItem item) {
    openBottomSheet(
      context,
      [
        SheetItem(
          title: "播放",
          icon: Icons.play_arrow_rounded,
          onPressed: () {
            _play(item);
          },
        ),
        SheetItem(
          title: "添加到待播放",
          icon: Icons.playlist_add_rounded,
          onPressed: () {
            Provider.of<PlayerModel>(context, listen: false)
                .addPlayerList([item], showToast: true);
          },
        ),
        SheetItem(
          title: "收藏到歌单",
          icon: Icons.favorite_border_rounded,
          onPressed: () {
            collectToMusicOrder(context: context, musicList: [item]);
          },
        ),
        SheetItem(
          title: "下载",
          icon: Icons.download_rounded,
          onPressed: () {
            checkMusicLocalRepeat(context, item, () {
              final downloadModel = Provider.of<DownloadModel>(context, listen: false);
              downloadModel.download([item]);
            });
          },
        ),
      ],
      header: SheetHeader(
        title: clearHtmlTags(item.name),
        subtitle: clearHtmlTags(item.author),
        track: item,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          musicOrder.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          PopupMenuButton(
            icon: const Icon(Icons.menu),
            itemBuilder: (context) => _buildPopupBtnItems(),
            offset: const Offset(0, 46),
            constraints: const BoxConstraints(
              minWidth: 200,
              maxWidth: 200,
            ),
            onSelected: (e) {
              if (musicList.isEmpty) {
                BotToast.showText(text: "列表是空的 QAQ");
                return;
              }

              if (e == Menus.allAddToWaitPlayList) {
                final player = Provider.of<PlayerModel>(context, listen: false);
                player.addPlayerList(musicList, showToast: true);
              }
              if (e == Menus.allAddToOrders) {
                collectToMusicOrder(
                  context: context,
                  musicList: musicList,
                );
              }
            },
          ),
          const SizedBox(width: 10)
        ],
      ),
      floatingActionButton: const PlayerView(cancelMargin: true),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: musicList.length,
        itemBuilder: (context, index) {
          if (musicList.isEmpty) return null;
          final item = musicList[index];
          return MusicListTile(
            item,
            showCollectionName: false,
            onPlay: () => _play(item),
            onMore: () => _moreHandler(context, item),
          );
        }
      ),
    );
  }

  List<PopupMenuItem<String>> _buildPopupBtnItems() {
    return menuBtnMap.keys.toList().map((btn) {
      return PopupMenuItem<String>(
        value: btn,
        child: SizedBox(
          width: 200, // 设置一个合适的宽度
          child: Row(
            children: [
              Icon(menuBtnMap[btn], color: Theme.of(context).primaryColor),
              const SizedBox(width: 10),
              Text(btn)
            ],
          ),
        ),
      );
    }).toList();
  }
}
