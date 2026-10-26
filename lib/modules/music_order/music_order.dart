// ignore_for_file: use_build_context_synchronously

import "dart:async";

import "package:bobomusic/components/custom_dialog/custom_dialog.dart";
import "package:bobomusic/components/delete_orders/delete_orders.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/music_order/components/edit_order.dart";
import "package:bobomusic/modules/music_order/pages/music_list_common.dart";
import "package:bobomusic/modules/music_order/pages/search.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:bobomusic/components/sheet/bottom_sheet.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";

final DBOrder db = DBOrder(version: 2);

typedef OnItemHandler = void Function(
  MusicOrderItem data,
);

class Menus {
  static String newOrder = "新建歌单";
  static String editOrder = "编辑歌单";
  static String deleteOrders = "删除歌单";
}

class MusicOrderView extends StatefulWidget {
  final MusicOrderItem? musicOrder;

  /// 嵌在首页分栏里时不需要自己的 AppBar / Scaffold
  final bool embedded;

  const MusicOrderView({super.key, this.musicOrder, this.embedded = false});

  @override
  State<MusicOrderView> createState() => UserMusicOrderView();
}

class UserMusicOrderView extends State<MusicOrderView> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;


  List<String> customOrderList = [];
  List<SheetItem> orderSheetList = [];
  // 每个歌单的歌曲数，key 为歌单名
  Map<String, int> orderCountMap = {};
  List<String> tabList = [
    TableName.musicILike,
  ];
  final Map<String, IconData> menuBtnMap = {
    Menus.newOrder: Icons.create_new_folder_outlined,
    Menus.editOrder: Icons.edit_note,
    Menus.deleteOrders: Icons.delete_forever,
  };
  final List<StreamSubscription?> _subscriptions = [];

  @override
  void initState() {
    super.initState();

    // 「本地」分栏已移除，长按删除歌单走 ShowDeleteListDialog
    _subscriptions.add(eventBus.on<ShowDeleteListDialog>().listen((event) {
      deleteList(event.tabName);
    }));
    _subscriptions.add(eventBus.on<RefreshTabList>().listen((event) {
      _loadData();
    }));

    _loadData();
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub?.cancel();
    }
    super.dispose();
  }

  Future<void> refreshTabList() async {
    final orderList = await getCustomOrderList();

    setState(() {
      tabList = [
        TableName.musicILike,
        ...orderList,
      ];
    });
  }

  Future<void> _loadData() async {
    final orderList = await getCustomOrderList();

    // 统计各歌单歌曲数
    final Map<String, int> countMap = {};
    for (final name in [TableName.musicILike, ...orderList]) {
      countMap[name] = await _countSongs(name);
    }

    if (!mounted) return;

    setState(() {
      customOrderList = orderList;
      orderCountMap = countMap;
      tabList = [
        TableName.musicILike,
        ...orderList,
      ];
      orderSheetList = orderList.map((e) {
        return SheetItem(
          title: Row(
            children: [
              Expanded(
                child: Text(
                  e,
                  style: TextStyle(
                    color: Theme.of(context).hintColor,
                    fontWeight: FontWeight.bold,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const Icon(Icons.keyboard_arrow_right)
            ],
          ),
          onPressed: () {
            final NavigatorState navigator = Navigator.of(context, rootNavigator: false);
            navigator.push(ModalBottomSheetRoute(
              isScrollControlled: true,
              builder: (context) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: EditMusicOrder(name: e, update: _loadData),
                );
              },
            ));
          },
        );
      }).cast<SheetItem>().toList();
    });
  }

  /// 统计某个歌单的歌曲数（失败时返回 0）
  Future<int> _countSongs(String tabName) async {
    try {
      final database = await db.database;
      // 表名可能含特殊字符，用双引号包裹并转义
      final table = tabName.replaceAll('"', '""');
      final rows = await database.rawQuery('SELECT COUNT(*) AS c FROM "$table"');
      return rows.isEmpty ? 0 : (rows.first["c"] as int? ?? 0);
    } catch (error) {
      return 0;
    }
  }

  /// 进入歌单内容页
  void _openOrder(String tabName) {
    Navigator.of(context, rootNavigator: false)
      .push(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return Scaffold(
              appBar: AppBar(
                centerTitle: true,
                title: Text(
                  tabName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              body: MusicListCommon(tabName: tabName),
            );
          },
        ),
      )
      .then((_) {
        // 返回时刷新歌曲数
        if (mounted) _loadData();
      });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.embedded) {
      return _buildBody();
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (BuildContext context) {
                  return const SearchOrderMusicView();
                },
              ),
            );
          },
          child: const TextField(
            enabled: false,
            decoration: InputDecoration(
              filled: true,
              fillColor: Color.fromARGB(255, 239, 240, 241),
              constraints: BoxConstraints(maxHeight: 35),
              border: UnderlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              hintText: "搜索歌单中的歌曲",
              hintStyle: TextStyle(fontSize: 12),
              contentPadding: EdgeInsets.symmetric(vertical: 13.5, horizontal: 16),
            ),
          ),
        ),
        actions: [
          PopupMenuButton(
            icon: const Icon(Icons.menu),
            itemBuilder: (context) => _buildPopupBtnItems(),
            offset: const Offset(0, 46),
            constraints: const BoxConstraints(
              minWidth: 130,
              maxWidth: 130,
            ),
            onSelected: (e) {
              if (e == Menus.newOrder) {
                final NavigatorState navigator = Navigator.of(context, rootNavigator: false);
                navigator.push(ModalBottomSheetRoute(
                  isScrollControlled: true,
                  builder: (context) {
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom,
                      ),
                      child: EditMusicOrder(name: "", update: _loadData),
                    );
                  },
                ));
              }
              if (e == Menus.editOrder) {
                if (orderSheetList.isNotEmpty) {
                  openBottomSheet(context, [
                    SheetItem(
                      title: Text(
                        "可编辑歌单",
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    ...orderSheetList,
                  ]);
                } else {
                  BotToast.showText(text: "没有可编辑的歌单", duration: const Duration(seconds: 2));
                }
              }
              if (e == Menus.deleteOrders) {
                if (customOrderList.isNotEmpty) {
                   Navigator.of(context, rootNavigator: false).push(ModalBottomSheetRoute(
                    isScrollControlled: true,
                    builder: (context) {
                      return DeleteOrders(onConfirm: _loadData);
                    },
                  ));
                } else {
                  BotToast.showText(text: "没有可删除的歌单", duration: const Duration(seconds: 2));
                }
              }
            },
          ),
          const SizedBox(width: 10)
        ],
      ),
      body: _buildBody(),
    );
  }

  /// 歌单纵向列表
  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.only(top: 10, left: 14, right: 14, bottom: 20),
      children: [
        _buildOrderCard(
          tabName: TableName.musicILike,
          icon: Icons.favorite,
        ),
        ...customOrderList.map((e) {
          return _buildOrderCard(
            tabName: e,
            icon: Icons.queue_music,
          );
        }),
      ],
    );
  }

  /// 歌单卡片
  Widget _buildOrderCard({required String tabName, required IconData icon}) {
    final primaryColor = Theme.of(context).primaryColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openOrder(tabName),
          // 长按删除该歌单所有歌曲
          onLongPress: () => eventBus.fire(ShowDeleteListDialog(tabName: tabName)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.08),
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                  ),
                  child: Icon(icon, size: 22, color: primaryColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tabName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "${orderCountMap[tabName] ?? 0} 首歌曲",
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<PopupMenuItem<String>> _buildPopupBtnItems() {
    return menuBtnMap.keys.toList().map((btn) {
      return PopupMenuItem<String>(
        value: btn,
        child: SizedBox(
          width: 100, // 设置一个合适的宽度
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

  Future<void> deleteList(String tabName) async {
    final musicList = await db.queryAll(tabName);

    if (context.mounted && musicList.isNotEmpty) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return CustomDialog(
            body: const Text("删除此歌单所有歌曲?"),
            onConfirm: () async {
              EasyLoading.show(maskType: EasyLoadingMaskType.black);

              if (context.mounted) {
                Navigator.of(context).pop();
              }

              try {
                await db.deleteAll(tabName);
                eventBus.fire(ClearMusicList());
                _loadData();
              } catch (error) {
                print(error);
              }
              EasyLoading.dismiss();
            },
            onCancel: () {
              Navigator.of(context).pop();
            },
          );
        },
      );
    }
  }
}
