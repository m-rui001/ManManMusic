import "dart:async";

import "package:bobomusic/components/music_list_tile/music_list_tile.dart";
import "package:bobomusic/components/sheet/bottom_sheet.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/download/model.dart";
import "package:bobomusic/modules/music_order/components/edit_music.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/check_music_local_repeat.dart";
import "package:flutter/material.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";
import "package:provider/provider.dart";

final DBOrder db = DBOrder();

/// 歌单里的歌曲列表
///
/// 同一份组件既能在首页「我的歌单」里内嵌使用（[embedded] = true，
/// 不套自己的 Scaffold），也能单独作为一页打开。
class MusicListCommon extends StatefulWidget {
  final String tabName;

  /// 内嵌使用时不再套 Scaffold
  final bool embedded;

  /// 列表顶部的自定义头部（跟着列表一起滚），参数是当前歌曲数
  final Widget Function(int count)? headerBuilder;

  const MusicListCommon({
    super.key,
    required this.tabName,
    this.embedded = false,
    this.headerBuilder,
  });

  @override
  State<MusicListCommon> createState() => MusicListCommonState();
}

class MusicListCommonState extends State<MusicListCommon> {
  List<MusicItem> musicList = [];
  final List<StreamSubscription?> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _loadData();

    _subscriptions.add(eventBus.on<RefreshMusicList>().listen((event) {
      if (mounted) _loadData();
    }));

    _subscriptions.add(eventBus.on<ClearMusicList>().listen((event) {
      if (mounted) _clearData();
    }));
  }

  @override
  void dispose() {
    for (var subscription in _subscriptions) {
      subscription?.cancel();
    }
    super.dispose();
  }

  Future<void> _loadData({bool? forceLoading = false}) async {
    final musics = await getUpdatedMusicList(tabName: widget.tabName);

    if (!mounted) return;
    setState(() {
      musicList = musics;
    });
  }

  Future<void> _clearData() async {
    EasyLoading.show(maskType: EasyLoadingMaskType.black);

    try {
      setState(() {
        musicList = [];
      });

      await db.deleteAll(widget.tabName);
    } catch (error) {
      print(error);
    }

    EasyLoading.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final headerCount = widget.headerBuilder == null ? 0 : 1;
    final hasHeader = headerCount == 1;

    final content = RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: hasHeader ? 30 : 20),
        itemCount: musicList.length + headerCount + (musicList.isEmpty ? 1 : 0),
        itemBuilder: (context, index) {
          if (hasHeader && index == 0) {
            return widget.headerBuilder!(musicList.length);
          }

          final dataIndex = index - headerCount;
          if (musicList.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: Text(
                  "还没有歌曲\n点红心、或者从 B 站收藏夹导入都会出现在这里",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.8),
                ),
              ),
            );
          }

          final item = musicList[dataIndex];
          return MusicListTile(
            item,
            onMore: () => showItemSheet(context, item),
          );
        },
      ),
    );

    if (widget.embedded) return content;

    return Scaffold(body: content);
  }

  void showItemSheet(BuildContext context, MusicItem musicItem) {
    final player = Provider.of<PlayerModel>(context, listen: false);

    openBottomSheet(context, [
      SheetItem(
        title: Text(
          musicItem.name,
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.bold,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      SheetItem(
        title: const Text("播放"),
        onPressed: () {
          player.play(music: musicItem);
        },
      ),
      SheetItem(
        title: const Text("添加到待播放列表"),
        onPressed: () {
          player.addPlayerList([musicItem], showToast: true);
        },
      ),
      SheetItem(
        title: const Text("编辑"),
        onPressed: () {
          Navigator.of(context).push(
            ModalBottomSheetRoute(
              isScrollControlled: true,
              builder: (context) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: EditMusic(
                    musicItem: musicItem,
                    onOk: (music) async {
                      await db.update(widget.tabName, musicItem2Row(music: music));

                      if (player.current != null && player.current!.playId == music.playId) {
                        player.current = music;
                      }

                      _loadData();
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
      SheetItem(
        title: const Text("从满满音乐移除"),
        onPressed: () async {
          EasyLoading.show(maskType: EasyLoadingMaskType.black);
          await db.deleteByMid(widget.tabName, musicItem.id);
          EasyLoading.dismiss();

          _loadData();
          eventBus.fire(RefreshTabList());
        },
      ),
      if (musicItem.localPath.isEmpty)
        SheetItem(
          title: const Text("下载"),
          onPressed: () {
            checkMusicLocalRepeat(context, musicItem, () {
              final downloadModel = Provider.of<DownloadModel>(context, listen: false);
              downloadModel.download([musicItem]);
            });
          },
        ),
    ]);
  }
}
