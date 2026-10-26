import "package:bobomusic/modules/bili_account/fav_sync.dart";
import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";

/// 从哔哩哔哩收藏夹导入 / 同步歌单
///
/// 导入过的收藏夹会记住绑定关系：
/// - 再次导入不会报错，而是增量同步（补新增、删已移除）
/// - B 站上删了收藏夹，本地歌单也会自动删掉
/// - 没导入过的收藏夹完全不管
class BiliFavPage extends StatefulWidget {
  const BiliFavPage({super.key});

  @override
  State<BiliFavPage> createState() => _BiliFavPageState();
}

class _BiliFavPageState extends State<BiliFavPage> {
  final BiliAuth _auth = BiliAuth.instance;

  List<BiliFavFolder> _folders = [];
  Map<int, FavBinding> _bindings = {};
  bool _loading = true;
  String? _error;

  int? _busyId;
  bool _syncingAll = false;

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
      final bindings = await FavSyncService.loadBindings();

      if (!mounted) return;
      setState(() {
        _folders = folders;
        _bindings = {for (final b in bindings) b.favId: b};
        _loading = false;
      });

      // 打开页面顺手清理掉 B 站上已删除的收藏夹歌单
      await _cleanupDeletedFolders();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "$e";
      });
    }
  }

  /// B 站上已经不存在、但本地还留着的收藏夹歌单 → 删掉
  Future<void> _cleanupDeletedFolders() async {
    final remoteIds = _folders.map((e) => e.id).toSet();
    final gone = _bindings.values.where((b) => !remoteIds.contains(b.favId)).toList();
    if (gone.isEmpty) return;

    for (final b in gone) {
      await FavSyncService.deleteOrder(b.tableName);
    }

    if (!mounted) return;
    setState(() {
      _bindings = {};
    });
    BotToast.showText(
      text: "已移除 ${gone.length} 个在 B 站已删除的收藏夹",
      duration: const Duration(seconds: 3),
    );
    await _load();
  }

  Future<void> _import(BiliFavFolder folder) async {
    final already = _bindings.containsKey(folder.id);
    setState(() => _busyId = folder.id);

    final result = await FavSyncService.importFolder(folder);

    if (!mounted) return;
    setState(() => _busyId = null);

    if (!result.ok) {
      BotToast.showText(text: "操作失败：${result.error}");
      return;
    }

    final parts = <String>[];
    if (result.added > 0) parts.add("新增 ${result.added} 首");
    if (result.removed > 0) parts.add("移除 ${result.removed} 首");
    if (parts.isEmpty) parts.add("已是最新");

    BotToast.showText(
      text: already
          ? "已同步「${folder.title}」：${parts.join("，")}"
          : "已导入 ${result.total} 首到「${folder.title}」",
      duration: const Duration(seconds: 3),
    );

    await _load();
  }

  Future<void> _syncAll() async {
    setState(() => _syncingAll = true);
    EasyLoading.show(maskType: EasyLoadingMaskType.black);

    final summary = await FavSyncService.syncAll();

    EasyLoading.dismiss();
    if (!mounted) return;
    setState(() => _syncingAll = false);

    final parts = <String>[];
    if (summary.added > 0) parts.add("新增 ${summary.added} 首");
    if (summary.removed > 0) parts.add("移除 ${summary.removed} 首");
    if (summary.deletedOrders.isNotEmpty) {
      parts.add("删除 ${summary.deletedOrders.length} 个已失效歌单");
    }

    BotToast.showText(
      text: parts.isEmpty
          ? "全部已是最新"
          : "同步完成：${parts.join("，")}",
      duration: const Duration(seconds: 3),
    );

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final hasBound = _bindings.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text("从收藏夹导入", style: TextStyle(fontSize: 17)),
        actions: [
          if (hasBound)
            TextButton(
              onPressed: (_syncingAll || _busyId != null) ? null : _syncAll,
              child: _syncingAll
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      "全部同步",
                      style: TextStyle(fontSize: 12, color: primaryColor),
                    ),
            ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, size: 20),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(child: _buildBody(primaryColor)),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: _folders.length + 1,
      itemBuilder: (context, index) {
        if (index == _folders.length) {
          return const Padding(
            padding: EdgeInsets.only(top: 10, left: 4, right: 4),
            child: Text(
              "导入过的收藏夹会自动跟随 B 站的增删变化：\n"
              "B 站加了视频这里会补上，B 站删了收藏夹这里也会删掉。",
              style: TextStyle(fontSize: 10, color: Colors.grey, height: 1.7),
            ),
          );
        }

        final folder = _folders[index];
        final binding = _bindings[folder.id];
        final busy = _busyId == folder.id;

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
                    Row(
                      children: [
                        Text(
                          "${folder.mediaCount} 个视频",
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        if (binding != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "已导入",
                              style: TextStyle(fontSize: 9, color: primaryColor),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (binding != null)
                Row(
                  children: [
                    TextButton(
                      onPressed: (_busyId == null && !_syncingAll)
                          ? () => _import(folder)
                          : null,
                      style: TextButton.styleFrom(
                        foregroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text("同步", style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: _busyId != null
                          ? null
                          : () => _removeBinding(folder, binding),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text("移除", style: TextStyle(fontSize: 12)),
                    ),
                  ],
                )
              else
                TextButton(
                  onPressed: (_busyId == null && !_syncingAll)
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

  /// 移除导入：删掉本地歌单，但不动 B 站上的收藏夹
  Future<void> _removeBinding(BiliFavFolder folder, FavBinding binding) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("移除导入", style: TextStyle(fontSize: 14)),
        content: Text(
          "会删除本地歌单「${binding.tableName}」，B 站上的收藏夹不受影响。",
          style: const TextStyle(fontSize: 12, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("移除"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await FavSyncService.deleteOrder(binding.tableName);
    if (!mounted) return;
    BotToast.showText(text: "已移除「${binding.tableName}」");
    await _load();
  }
}
