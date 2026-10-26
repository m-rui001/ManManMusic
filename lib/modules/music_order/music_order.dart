// ignore_for_file: use_build_context_synchronously

import "dart:async";

import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/bili_account/bili_fav_page.dart";
import "package:bobomusic/modules/bili_account/bili_login_gate.dart";
import "package:bobomusic/modules/music_order/pages/music_list_common.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

/// 「我的歌单」
///
/// 现在全 App 只有一张歌单：满满音乐。
/// 点红心、导入 B 站收藏夹都进这里，不再有「我喜欢 / 收藏夹 A / 收藏夹 B」的分层，
/// 所以这一页直接就是歌曲列表，不再需要先选歌单。
class MusicOrderView extends StatefulWidget {
  /// 嵌在首页分栏里时不需要自己的 AppBar / Scaffold
  final bool embedded;

  const MusicOrderView({super.key, this.embedded = false});

  @override
  State<MusicOrderView> createState() => UserMusicOrderView();
}

class UserMusicOrderView extends State<MusicOrderView> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final BiliAuth auth = BiliAuth.instance;

  bool _syncing = false;

  Future<void> _playAll() async {
    final list = await getUpdatedMusicList(tabName: TableName.myMusic);
    if (!mounted) return;

    if (list.isEmpty) {
      BotToast.showText(text: "满满音乐还是空的");
      return;
    }

    Provider.of<PlayerModel>(context, listen: false).play(music: list.first);
  }

  Future<void> _openFavSync() async {
    if (!auth.isLogin) {
      final ok = await BiliLoginGate.ensureLoggedIn(context);
      if (!ok || !mounted) return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BiliFavPage()),
    );

    if (!mounted) return;
    eventBus.fire(RefreshMusicList(tabName: TableName.myMusic));
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("清空满满音乐", style: TextStyle(fontSize: 14)),
        content: const Text(
          "会把满满音乐里的歌全部删掉，B 站上的收藏夹不受影响。",
          style: TextStyle(fontSize: 12, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("清空"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _syncing = true);
    await DBOrder().deleteAll(TableName.myMusic);
    if (!mounted) return;
    setState(() => _syncing = false);

    eventBus.fire(ClearMusicList());
    eventBus.fire(RefreshMusicList(tabName: TableName.myMusic));
    BotToast.showText(text: "已清空");
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final body = MusicListCommon(
      tabName: TableName.myMusic,
      embedded: true,
      headerBuilder: _buildHeader,
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text("我的歌单", style: TextStyle(fontSize: 17)),
      ),
      body: body,
    );
  }

  Widget _buildHeader(int count) {
    final primaryColor = Theme.of(context).primaryColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.favorite,
                        size: 24,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "满满音乐",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            "$count 首 · 点红心就会进来",
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (count > 0)
                      IconButton(
                        tooltip: "清空",
                        onPressed: _syncing ? null : _clearAll,
                        icon: Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: Colors.grey[400],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: FilledButton.icon(
                          onPressed: _playAll,
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(19),
                            ),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text("播放全部", style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: OutlinedButton.icon(
                          onPressed: _openFavSync,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryColor,
                            side: BorderSide(
                              color: primaryColor.withValues(alpha: 0.3),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(19),
                            ),
                          ),
                          icon: const Icon(Icons.sync, size: 16),
                          label: const Text("同步 B 站", style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
