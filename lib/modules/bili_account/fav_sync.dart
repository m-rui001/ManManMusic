import "dart:convert";

import "package:bobomusic/db/db.dart";
import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bobomusic/origin_sdk/bili/utils.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:uuid/uuid.dart";

const _uuid = Uuid();

/// 一个「同步过的 B 站收藏夹」记录
class FavBinding {
  /// B 站收藏夹 id
  final int favId;

  /// 收藏夹标题
  final String title;

  /// 上次同步时收藏夹里的视频数
  final int mediaCount;

  /// 上次同步时间
  final DateTime syncedAt;

  const FavBinding({
    required this.favId,
    required this.title,
    required this.mediaCount,
    required this.syncedAt,
  });

  FavBinding copyWith({
    String? title,
    int? mediaCount,
    DateTime? syncedAt,
  }) {
    return FavBinding(
      favId: favId,
      title: title ?? this.title,
      mediaCount: mediaCount ?? this.mediaCount,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        "favId": favId,
        "title": title,
        "mediaCount": mediaCount,
        "syncedAt": syncedAt.millisecondsSinceEpoch,
      };

  factory FavBinding.fromJson(Map<String, dynamic> json) {
    return FavBinding(
      favId: (json["favId"] is int) ? json["favId"] : 0,
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

  /// 收藏夹总数
  final int total;

  /// 失败原因
  final String? error;

  const FavSyncResult({
    required this.ok,
    this.added = 0,
    this.total = 0,
    this.error,
  });
}

/// 全部同步的汇总
class FavSyncSummary {
  final int syncedFolders;
  final int added;

  const FavSyncSummary({
    this.syncedFolders = 0,
    this.added = 0,
  });
}

/// 收藏夹导入 / 同步
///
/// 设计（v3 起）：
/// - 全 App 只有一张歌单：满满音乐。点红心、导收藏夹都进这里。
/// - 导入 = 把收藏夹里**满满音乐还没有**的歌补进去，只增不删。
/// - 不自动同步。用户哪天点了「同步」才拉一次，避免后台偷偷请求 B 站接口，
///   也避免把用户手动删掉的歌又塞回来。
/// - 本机只记「哪些收藏夹同步过、上次什么时候同步、当时有多少首」。
class FavSyncService {
  FavSyncService._();

  static const String _kBindings = "manman_fav_bindings";

  static final DBOrder _db = DBOrder();

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
          .where((e) => e.favId > 0)
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
    for (final b in await loadBindings()) {
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

  /// 只删掉「同步记录」，不动满满音乐里已经导入的歌
  static Future<void> unbind(int favId) async {
    final bindings = await loadBindings();
    bindings.removeWhere((e) => e.favId == favId);
    await _saveBindings(bindings);
  }

  // ===== 满满音乐读写 =====

  /// 满满音乐里所有歌的 mid
  static Future<Set<String>> existingMids() async {
    final rows = await _db.queryAll(TableName.myMusic);
    return rows.map((e) => "${e["mid"]}").where((e) => e.isNotEmpty).toSet();
  }

  static Future<bool> isInMyMusic(String mid) async {
    if (mid.isEmpty) return false;
    return (await existingMids()).contains(mid);
  }

  /// 加一首进满满音乐（已存在就不重复加）
  ///
  /// 返回 true 表示真的新加了。
  static Future<bool> addMusic(MusicItem music) async {
    if (music.id.isEmpty) return false;
    if ((await existingMids()).contains(music.id)) return false;

    await _db.insert(
      TableName.myMusic,
      musicItem2Row(
        music: music.copyWith(
          orderName: TableName.myMusic,
          playId: music.playId.isEmpty ? _uuid.v4() : music.playId,
        ),
      ),
    );
    return true;
  }

  /// 从满满音乐里删掉一首（按 mid，精确删除）
  static Future<void> removeMusic(String mid) async {
    if (mid.isEmpty) return;
    await _db.deleteByMid(TableName.myMusic, mid);
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
    }

    return medias;
  }

  /// 把一个收藏夹里「满满音乐还没有」的歌补进去
  ///
  /// 重复调用安全：已经有的歌会被跳过，不会建表、不会报错。
  static Future<FavSyncResult> importFolder(BiliFavFolder folder) async {
    try {
      final medias = await fetchAllMedias(
        folder.id,
        totalHint: folder.mediaCount,
      );

      final existing = await existingMids();
      final rows = <Map<String, dynamic>>[];

      for (final media in medias) {
        final id = BiliId(aid: media.aid, bvid: media.bvid).decode();
        if (id.isEmpty || !existing.add(id)) continue;

        rows.add(
          musicItem2Row(
            music: MusicItem(
              id: id,
              cover: media.cover,
              name: media.title,
              duration: media.duration,
              author: media.upper,
              origin: OriginType.bili,
              orderName: TableName.myMusic,
              playId: _uuid.v4(),
            ),
          ),
        );
      }

      // 一次性事务写入，几百首也是秒级
      await _db.insertAll(TableName.myMusic, rows);
      final added = rows.length;

      await _upsertBinding(
        FavBinding(
          favId: folder.id,
          title: folder.title,
          mediaCount: medias.length,
          syncedAt: DateTime.now(),
        ),
      );

      return FavSyncResult(
        ok: true,
        added: added,
        total: medias.length,
      );
    } catch (e) {
      return FavSyncResult(ok: false, error: "$e");
    }
  }

  /// 手动同步所有同步过的收藏夹（只增不删）
  static Future<FavSyncSummary> syncAll() async {
    final bindings = await loadBindings();
    if (bindings.isEmpty) return const FavSyncSummary();

    List<BiliFavFolder> remoteFolders;
    try {
      remoteFolders = await BiliAuth.instance.fetchFavFolders();
    } catch (_) {
      // 网络失败就什么都不动
      return const FavSyncSummary();
    }

    final remoteMap = {for (final f in remoteFolders) f.id: f};

    int synced = 0;
    int added = 0;

    for (final binding in bindings) {
      final remote = remoteMap[binding.favId];
      // B 站上这个收藏夹没了：只解除同步记录，歌留在满满音乐里
      if (remote == null) {
        await unbind(binding.favId);
        continue;
      }

      final result = await importFolder(remote);
      if (result.ok) {
        synced += 1;
        added += result.added;
      }
    }

    return FavSyncSummary(syncedFolders: synced, added: added);
  }
}
