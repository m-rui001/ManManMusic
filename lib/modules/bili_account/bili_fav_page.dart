import "package:bobomusic/db/db.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bobomusic/origin_sdk/bili/utils.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";

/// 从哔哩哔哩收藏夹一键导入歌单
class BiliFavPage extends StatefulWidget {
  const BiliFavPage({super.key});

  @override
  State<BiliFavPage> createState() => _BiliFavPageState();
}

class _BiliFavPageState extends State<BiliFavPage> {
  final BiliAuth _auth = BiliAuth.instance;
  final DBOrder _db = DBOrder(version: 2);

  List<BiliFavFolder> _folders = [];
  bool _loading = true;
  String? _error;

  /// 正在导入的收藏夹 id
  int? _importingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final folders = await _auth.fetchFavFolders();
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "$e";
      });
    }
  }

  Future<void> _import(BiliFavFolder folder) async {
    setState(() => _importingId = folder.id);

    try {
      // 分页拉取全部条目
      final medias = <BiliFavMedia>[];
      int page = 1;
      while (true) {
        final batch = await _auth.fetchFavMedias(
          mediaId: folder.id,
          page: page,
          pageSize: 20,
        );
        if (batch.isEmpty) break;
        medias.addAll(batch);
        page += 1;
        if (medias.length >= folder.mediaCount) break;
        // 防止异常数据导致死循环
        if (page > 50) break;
      }

      if (medias.isEmpty) {
        BotToast.showText(text: "这个收藏夹里没有可导入的视频");
        setState(() => _importingId = null);
        return;
      }

      // 表名：收藏夹_标题（去掉非法字符）
      final safeTitle = _safeTableName("收藏夹_${folder.title}");
      final tableName = safeTitle;

      await _db.createOrderTable(tableName);

      int count = 0;
      for (final media in medias) {
        if (media.bvid.isEmpty) continue;

        final music = MusicItem(
          id: BiliId(aid: media.aid, bvid: media.bvid).decode(),
          cover: media.cover,
          name: media.title,
          duration: media.duration,
          author: media.upper,
          origin: OriginType.bili,
          orderName: tableName,
        );

        // 避免同歌单内重复
        final exists = await _db.queryByParam(tableName, music.id);
        if (exists.isNotEmpty) continue;

        await _db.insert(tableName, musicItem2Row(music: music));
        count += 1;
      }

      // 写入自定义歌单列表，让它在首页出现
      await setCustomOrderItem(newName: tableName);

      if (!mounted) return;
      setState(() => _importingId = null);

      BotToast.showText(
        text: "已导入 $count 首到歌单「$tableName」",
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _importingId = null);
      BotToast.showText(text: "导入失败：$e");
    }
  }

  String _safeTableName(String raw) {
    var name = raw.replaceAll(RegExp(r"[\\/:*?&|<>#;'\x22]"), "_").trim();
    if (name.length > 40) name = name.substring(0, 40);
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text("从收藏夹导入", style: TextStyle(fontSize: 18)),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, size: 20),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: _buildBody(primaryColor),
      ),
    );
  }

  Widget _buildBody(Color primaryColor) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 42, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 14),
              TextButton(onPressed: _load, child: const Text("重试")),
            ],
          ),
        ),
      );
    }

    if (_folders.isEmpty) {
      return const Center(
        child: Text(
          "还没有创建任何收藏夹",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
      itemCount: _folders.length,
      itemBuilder: (context, index) {
        final folder = _folders[index];
        final importing = _importingId == folder.id;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 64,
                  height: 42,
                  child: folder.cover.isEmpty
                      ? Container(
                          color: const Color(0xFFEEEEEE),
                          child: const Icon(
                            Icons.folder_outlined,
                            size: 20,
                            color: Colors.grey,
                          ),
                        )
                      : Image.network(
                          folder.cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFFEEEEEE),
                            child: const Icon(
                              Icons.folder_outlined,
                              size: 20,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "${folder.mediaCount} 个视频",
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              importing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: _importingId == null
                          ? () => _import(folder)
                          : null,
                      style: TextButton.styleFrom(
                        foregroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text("导入", style: TextStyle(fontSize: 12)),
                    ),
            ],
          ),
        );
      },
    );
  }
}
