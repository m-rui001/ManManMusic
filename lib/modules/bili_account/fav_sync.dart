import "dart:convert";

import "package:bobomusic/db/db.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bobomusic/origin_sdk/bili/utils.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:shared_preferences/shared_preferences.dart";

/// 一个「已导入的收藏夹」绑定关系
class FavBinding {
  /// B 站收藏夹 id
  final int favId;

  /// 本地歌单表名
  final String tableName;

  /// 收藏夹标题（B 站上的原名，用于显示与改名检测）
  final String title;

  /// 上次同步时收藏夹里的视频数
  final int mediaCount;

  /// 上次同步时间
  final DateTime syncedAt;

  const FavBinding({
    required this.favId,
    required this.tableName,
    required this.title,
    required this.mediaCount,
    required this.syncedAt,
  });

  FavBinding copyWith({
    String? tableName,
    String? title,
    int? mediaCount,
    DateTime? syncedAt,
  }) {
    return FavBinding(
      favId: favId,
      tableName: tableName ?? this.tableName,
      title: title ?? this.title,
      mediaCount: mediaCount ?? this.mediaCount,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        "favId": favId,
        "tableName": tableName,
        "title": title,
        "mediaCount": mediaCount,
        "syncedAt": syncedAt.millisecondsSinceEpoch,
      };

  factory FavBinding.fromJson(Map<String, dynamic> json) {
    return FavBinding(
      favId: (json["favId"] is int) ? json["favId"] : 0,
      tableName: "${json["tableName"] ?? ""}",
      title: "${json["title"] ?? ""}",
      mediaCount: (json["mediaCount"] is int) ? json["mediaCount"] : 0,
      syncedAt: DateTime.fromMillisecondsSinceEpoch(
        (json["syncedAt"] is int) ? json["syncedAt"] : 0,
      ),
    );
  }
}

/// 单个收藏夹的同步结果
class FavSyncResult {
  final bool ok;

  /// 新增了多少首
  final int added;

  /// 移除了多少首
  final int removed;

  /// 收藏夹总数
  final int total;

  /// 失败原因
  final String? error;

  const FavSyncResult({
    required this.ok,
    this.added = 0,
    this.removed = 0,
    this.total = 0,
    this.error,
  });
}

/// 全部同步的汇总
class FavSyncSummary {
  final int syncedFolders;
  final int added;
  final int removed;

  /// 因为 B 站上已删除而被清掉的本地歌单
  final List<String> deletedOrders;

  const FavSyncSummary({
    this.syncedFolders = 0,
    this.added = 0,
    this.removed = 0,
    this.deletedOrders = const [],
  });
}

/// 收藏夹导入与同步
///
/// 设计：
/// - 导入一次后记录 favId → 本地歌单 的绑定关系
/// - 再次导入同一个收藏夹不会报错，而是做增量同步（补新增、删已移除）
/// - B 站上收藏夹被删掉后，本地歌单也自动删除
/// - 从没导入过的收藏夹完全不管
class FavSyncService {
  FavSyncService._();

  static const String _kBindings = "manman_fav_bindings";

  static final DBOrder _db = DBOrder(version: 2);

  // ===== 绑定关系读写 =====

  static Future<List<FavBinding>> loadBindings() async {
    final storage = await SharedPreferences.getInstance();
    final raw = storage.getString(_kBindings);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => FavBinding.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.favId > 0 && e.tableName.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveBindings(List<FavBinding> bindings) async {
    final storage = await SharedPreferences.getInstance();
    await storage.setString(
      _kBindings,
      jsonEncode(bindings.map((e) => e.toJson()).toList()),
    );
  }

  static Future<FavBinding?> findByFavId(int favId) async {
    final bindings = await loadBindings();
    for (final b in bindings) {
      if (b.favId == favId) return b;
    }
    return null;
  }

  static Future<void> _upsertBinding(FavBinding binding) async {
    final bindings = await loadBindings();
    final index = bindings.indexWhere((e) => e.favId == binding.favId);
    if (index >= 0) {
      bindings[index] = binding;
    } else {
      bindings.add(binding);
    }
    await _saveBindings(bindings);
  }

  static Future<void> unbind(int favId) async {
    final bindings = await loadBindings();
    bindings.removeWhere((e) => e.favId == favId);
    await _saveBindings(bindings);
  }

  /// 该本地歌单是否来自收藏夹
  static Future<FavBinding?> findByTableName(String tableName) async {
    final bindings = await loadBindings();
    for (final b in bindings) {
      if (b.tableName == tableName) return b;
    }
    return null;
  }

  // ===== 导入 / 同步 =====

  /// 拉取收藏夹全部条目（分页到底）
  static Future<List<BiliFavMedia>> fetchAllMedias(
    int favId, {
    int totalHint = 0,
  }) async {
    final medias = <BiliFavMedia>[];
    final seen = <String>{};
    int page = 1;

    while (page <= 100) {
      final batch = await BiliAuth.instance.fetchFavMedias(
        mediaId: favId,
        page: page,
        pageSize: 20,
      );
      if (batch.isEmpty) break;

      for (final m in batch) {
        if (m.bvid.isEmpty) continue;
        final key = m.bvid.isNotEmpty ? m.bvid : m.aid;
        if (seen.add(key)) medias.add(m);
      }

      page += 1;
      // 拉够了就停，避免多余请求
      if (totalHint > 0 && medias.length >= totalHint) break;
    }

    return medias;
  }

  /// 导入或同步一个收藏夹
  ///
  /// 已导入过的会做增量更新，不会重复建表也不会报错。
  static Future<FavSyncResult> importFolder(BiliFavFolder folder) async {
    try {
      final medias = await fetchAllMedias(
        folder.id,
        totalHint: folder.mediaCount,
      );

      final tableName = _targetTableName(folder);
      await _db.createOrderTable(tableName);

      // 本地已有的（按 id 索引）
      final existingRows = await _db.queryAll(tableName);
      final existingIds = <String>{};
      for (final row in existingRows) {
        final mid = "${row["mid"] ?? ""}";
        if (mid.isNotEmpty) existingIds.add(mid);
      }

      // 远端现在的 id 集合
      final remoteIds = <String>{};
      final toInsert = <MusicItem>[];
      for (final media in medias) {
        final id = BiliId(aid: media.aid, bvid: media.bvid).decode();
        remoteIds.add(id);
        if (existingIds.contains(id)) continue;

        toInsert.add(
          MusicItem(
            id: id,
            cover: media.cover,
            name: media.title,
            duration: media.duration,
            author: media.upper,
            origin: OriginType.bili,
            orderName: tableName,
          ),
        );
      }

      // 远端已经没有的，本地删掉
      final toRemove = existingIds.difference(remoteIds);

      for (final music in toInsert) {
        await _db.insert(tableName, musicItem2Row(music: music));
      }
      for (final id in toRemove) {
        await _db.delete(tableName, id);
      }

      // 绑定关系 + 出现在歌单列表里
      await _upsertBinding(
        FavBinding(
          favId: folder.id,
          tableName: tableName,
          title: folder.title,
          mediaCount: medias.length,
          syncedAt: DateTime.now(),
        ),
      );
      await setCustomOrderItem(newName: tableName);

      return FavSyncResult(
        ok: true,
        added: toInsert.length,
        removed: toRemove.length,
        total: medias.length,
      );
    } catch (e) {
      return FavSyncResult(ok: false, error: "$e");
    }
  }

  /// 同步所有已导入的收藏夹；B 站上已不存在的，本地一并删除
  static Future<FavSyncSummary> syncAll() async {
    final bindings = await loadBindings();
    if (bindings.isEmpty) return const FavSyncSummary();

    List<BiliFavFolder> remoteFolders;
    try {
      remoteFolders = await BiliAuth.instance.fetchFavFolders();
    } catch (_) {
      // 网络失败就什么都不动，避免误删
      return const FavSyncSummary();
    }

    final remoteMap = {for (final f in remoteFolders) f.id: f};

    int synced = 0;
    int added = 0;
    int removed = 0;
    final deletedOrders = <String>[];

    for (final binding in bindings) {
      final remote = remoteMap[binding.favId];

      // B 站上这个收藏夹没了 → 本地也删掉
      if (remote == null) {
        try {
          await _db.dropTable(binding.tableName);
        } catch (_) {}
        await delCustomOrderItem(name: binding.tableName);
        await unbind(binding.favId);
        deletedOrders.add(binding.tableName);
        continue;
      }

      // 收藏夹改了名也继续用原表名，避免歌单在列表里跳来跳去；
      // 只把新标题记进绑定关系
      final result = await importFolder(remote);
      if (result.ok) {
        synced += 1;
        added += result.added;
        removed += result.removed;
      }
    }

    return FavSyncSummary(
      syncedFolders: synced,
      added: added,
      removed: removed,
      deletedOrders: deletedOrders,
    );
  }

  /// 删除整个收藏夹歌单（含绑定关系）
  static Future<void> deleteOrder(String tableName) async {
    final binding = await findByTableName(tableName);
    if (binding != null) await unbind(binding.favId);

    try {
      await _db.dropTable(tableName);
    } catch (_) {}

    await delCustomOrderItem(name: tableName);
  }

  /// 表名规则：收藏夹_标题
  static String _targetTableName(BiliFavFolder folder, {String? fallback}) {
    final name = "收藏夹_${folder.title}";
    final safe = safeTableName(name);
    if (safe.isEmpty) return fallback ?? "收藏夹_${folder.id}";
    return safe;
  }

  /// 把任意标题转成安全的 SQLite 表名
  ///
  /// 保留中文，过滤掉会破坏 SQL 或路径的字符，并截断到 40 字。
  static String safeTableName(String raw) {
    var name = raw.replaceAll(RegExp(r"[\\/:*?&|<>#;'\x22]"), "_").trim();
    if (name.length > 40) name = name.substring(0, 40);
    return name;
  }
}
