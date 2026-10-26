import "package:bobomusic/modules/bili_account/fav_sync.dart";
import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";

/// 从哔哩哔哩收藏夹导入到「满满音乐」
///
/// 规则很简单：
/// - 导入 = 把这个收藏夹里「满满音乐还没有」的视频补进去
/// - 不做自动同步，什么时候想拉新内容就点一次「同步」
/// - 已经导入过的歌不会被删，删歌请去「我的歌单」
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "$e";
      });
    }
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

    BotToast.showText(
      text: result.added > 0
          ? (already
              ? "「${folder.title}」新增 ${result.added} 首"
              : "已把 ${result.added} 首加进满满音乐")
          : "「${folder.title}」没有新歌",
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

    BotToast.showText(
      text: summary.added == 0
          ? "全部已是最新"
          : "同步完成：新增 ${summary.added} 首",
      duration: const Duration(seconds: 3),
    );

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text("从收藏夹导入", style: TextStyle(fontSize: 17)),
        actions: [
          if (_bindings.isNotEmpty)
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
        if (index == 0) {
          return _hintCard(primaryColor);
        }

        final folder = _folders[index - 1];
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
                      ? _folderPlaceholder()
                      : Image.network(
                          folder.cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _folderPlaceholder(),
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
                      binding == null
                          ? "${folder.mediaCount} 个视频"
                          : "${folder.mediaCount} 个视频 · ${_ago(binding.syncedAt)}同步过",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
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
                  child: Text(
                    binding == null ? "导入" : "同步",
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _hintCard(Color primaryColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 15, color: primaryColor),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "导入会把收藏夹里满满音乐还没有的视频补进去，只增不删。\n"
              "不会自动同步——想拉新内容时点一次「同步」就行。",
              style: TextStyle(fontSize: 10, height: 1.7, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _folderPlaceholder() {
    return Container(
      color: const Color(0xFFEEEEEE),
      child: const Icon(Icons.folder_outlined, size: 20, color: Colors.grey),
    );
  }

  String _ago(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return "刚刚";
    if (diff.inMinutes < 60) return "${diff.inMinutes} 分钟前";
    if (diff.inHours < 24) return "${diff.inHours} 小时前";
    return "${diff.inDays} 天前";
  }
}
