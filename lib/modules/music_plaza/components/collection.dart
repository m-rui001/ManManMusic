import "dart:async";
import "dart:math";

import "package:bobomusic/components/empty_page/empty_page.dart";
import "package:bobomusic/components/title_area/title_area.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/music_plaza/components/collection_item.dart";
import "package:bobomusic/modules/music_plaza/components/detail.dart";
import "package:bobomusic/modules/music_plaza/search/search.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";
import "package:path/path.dart" as path;

final DBOrder db = DBOrder();
final DBCollection dbCollection = DBCollection();

class Collection extends StatefulWidget {
  const Collection({super.key});

  @override
  State<Collection> createState() => CollectionViewState();
}

class CollectionViewState extends State<Collection> {
  List<Widget> singerList = [];
  final List<StreamSubscription?> _subscriptions = [];

  @override
  void initState() {
    super.initState();

    _subscriptions.add(eventBus.on<RefreshCollectionList>().listen((event) {
      _loadSingerList();
    }));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        _loadSingerList();
      }
    });
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub?.cancel();
    }
    super.dispose();
  }

  Future<void> _loadSingerList() async {
    final List<Map<String, dynamic>> collectionList = await dbCollection.queryAll(TableName.collection, needOrder: false);
    List<Widget> singerViewList = [];

    if (collectionList.length == 1) {
      final collectionPrev = row2Collection(dbRow: collectionList[0]);
      singerViewList.add(
        Row(
          children: [
            genCollectionItem(collectionPrev)
          ]
        ),
      );

      setState(() {
        singerList = singerViewList;
      });

      return;
    }

    for (var i = 0; i < collectionList.length; i++) {
      if (i > 0 && i % 2 == 1) {
        continue;
      }

      final collectionPrev = row2Collection(dbRow: collectionList[i]);
      CollectionItemType? collectionNext;

      if (i + 1 < collectionList.length) {
        collectionNext = row2Collection(dbRow: collectionList[i + 1]);
      }

      singerViewList.add(
        Row(children: [
          genCollectionItem(collectionPrev),
          const SizedBox(width: 12),
          if(collectionNext != null)
          genCollectionItem(collectionNext)
        ])
      );
    }

    setState(() {
      singerList = singerViewList;
    });
  }

  genCollectionItem(CollectionItemType collection) {
    return CollectionItem(
      imageUrl: collection.cover,
      name: collection.name,
      author: collection.author.isNotEmpty ? collection.author : "哔哩哔哩",
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (BuildContext context) {
            return MusicOrderDetail(
              musicOrderItem: MusicOrderItem(
                id: collection.id,
                name: collection.musicListTableName,
                desc: "",
                author: collection.author,
                musicList: []
              ),
              shouldLoadData: true,
            );
          },
        ));
      },
      onLongPress: () {
        showDialog(
          context: context,
          builder: (ctx) => Container(
            alignment: Alignment.bottomCenter,
            child: CupertinoActionSheet(
              title: const Text("请选择操作", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              message: Container(
                margin: const EdgeInsets.only(top: 6),
                child: const Text("删除你不想要的合集", style: TextStyle(fontSize: 10)),
              ),
              actions: [
                CupertinoActionSheetAction(
                  onPressed: () async {
                    Navigator.of(context).pop();

                    EasyLoading.show(maskType: EasyLoadingMaskType.black);
                    final musicListTableName = genMusicListTableName(id: collection.id);

                    try {
                      await dbCollection.delete(TableName.collection, collection.id);

                      if (await db.isTableExists(musicListTableName)) {
                        await db.dropTable(musicListTableName);
                      }

                      await _loadSingerList();
                    } catch (error) {
                      BotToast.showText(text: "删除失败，请重试");
                    }

                    EasyLoading.dismiss();
                  },
                  child: const Text("删除此合集", style: TextStyle(fontSize: 12, color: Colors.deepPurple))
                ),
              ],
              cancelButton: CupertinoActionSheetAction(onPressed: () {
                Navigator.of(context).pop();
              }, child: Text("取消", style: TextStyle(fontSize: 12, color: Colors.grey[800]))),
            ),
          )
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;
    final emptyPageHeight = MediaQuery.of(context).size.height - 400;
    final imageWidth = screenSize.width ~/ 2;
    final restHeight = emptyPageHeight - imageWidth - (20 + 32 + 30 + 48 + 30); // 20 文字高度, 32 按钮 top, 30 image bottom, 48 按钮 height, 30 凭感觉减去的高度

    return SafeArea(
      bottom: true,
      child: Column(
        children: [
          const TitleAreaView(title: "收藏合集"),
          singerList.isEmpty ? SizedBox(
            height: emptyPageHeight,
            child: Center(
              child: EmptyPage(
                imageTopPadding: (restHeight / 2) > 0 ? (restHeight / 2) : 0,
                imageBottomPadding: 30,
                text: "你还没有收藏的合集",
                customImage: SizedBox(
                  width: min(screenSize.width / 2, screenSize.height / 2) - (isLandscape ? 80 : 0),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                    child: Image.asset(path.join("assets", "images", "space_exploration.png"))
                  ),
                ),
                btns: [
                  if(isLandscape)
                    const SizedBox(height: 40),
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.only(left: 32, right: 32),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4)))
                    ),
                    onPressed: () async {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (BuildContext context) {
                            return const SearchView();
                          },
                        ),
                      );
                    },
                    child: const Text("去搜索合集"),
                  ),
                ]
              ),
            )
          ) : Column(children: singerList),
          const SizedBox(height: 50),
        ],
      )
    );
  }
}
