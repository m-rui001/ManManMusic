import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:sqflite/sqflite.dart";
import "package:path/path.dart";

class DBName {
  /// 歌单
  static String orderName  = "musicOrder";
}

class TableName {
  /// 本地
  static String musicLocal  = "本地";
  /// 满满音乐：唯一的主歌单
  ///
  /// 点红心、从 B 站收藏夹导入，全都进这一张表。
  /// 不再区分「我喜欢」和一堆「收藏夹_xxx」。
  static String myMusic  = "满满音乐";
  /// 旧版「我喜欢」表名，只在数据库升级时用来迁移
  static String legacyILike  = "我喜欢";
  /// 待播放列表
  static String musicWaitPlay  = "待播放列表";
}

/// 歌单表的建表语句（所有歌单表结构一致）
String orderTableSql(String tableName) =>
    "CREATE TABLE IF NOT EXISTS $tableName (id INTEGER PRIMARY KEY AUTOINCREMENT, mid TEXT, name TEXT, cover TEXT, duration INTEGER, author TEXT, origin TEXT, playId TEXT, lyric TEXT, localPath TEXT, prev TEXT, next TEXT, orderName TEXT, isFirst TEXT, isLast TEXT)";

// 基础数据库帮助类
abstract class BaseDatabaseHelper {
  static final Map<String, BaseDatabaseHelper> _instances = {};

  final String databaseName;
  final int version;
  Database? _database;

  BaseDatabaseHelper._internal(this.databaseName, this.version);

  factory BaseDatabaseHelper({
    required String databaseName,
    int version = 1,
  }) {
    final key = "$databaseName:$version";
    if (!_instances.containsKey(key)) {
      _instances[key] = _createInstance(databaseName, version);
    }
    return _instances[key]!;
  }

  // 抽象工厂构造函数，由子类实现
  factory BaseDatabaseHelper.createInstance(String databaseName, int version) =>
      throw UnimplementedError("Subclasses should implement this");

  static BaseDatabaseHelper _createInstance(String databaseName, int version) {
    return BaseDatabaseHelper.createInstance(databaseName, version);
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    try {
      _database = await _initDatabase();
      return _database!;
    } catch (e) {
      print("Database initialization error: $e");
      rethrow;
    }
  }

  Future<Database> _initDatabase() async {
    final String path = join(await getDatabasesPath(), databaseName);
    return await openDatabase(
      path,
      version: version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // 抽象方法，子类需要实现数据库创建逻辑
  Future<void> _onCreate(Database db, int version);

  // 抽象方法，子类需要实现数据库升级逻辑
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion);

  Future<int> insert(String tableName, Map<String, dynamic> row) async {
    try {
      Database db = await database;
      return await db.insert(tableName, row);
    } catch (e) {
      print("Insert error: $e");
      rethrow;
    }
  }

  /// 批量写入（一次事务，几百首也不会卡）
  Future<void> insertAll(String tableName, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in rows) {
        batch.insert(tableName, row);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<bool> isTableExists(String tableName) async {
    Database db = await database;
    var result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    return result.isNotEmpty;
  }

  /// 按 mid 去重后取出全部歌曲
  ///
  /// - [groupBy] 默认 mid：同一首歌只留最早插入的那一条
  /// - [needOrder] 为 false 时按插入顺序（id）返回，适合歌单/待播放这类有先后意义的列表
  Future<List<Map<String, dynamic>>> queryAll(String tableName, {String? groupBy = "mid", bool? needOrder}) async {
    final isOrder = needOrder ?? true;
    try {
      Database db = await database;
      return await db.rawQuery("""
        SELECT * FROM $tableName
        WHERE id IN (
          SELECT MIN(id) FROM $tableName
          GROUP BY $groupBy
        )
        ${isOrder ? "ORDER BY name ASC" : "ORDER BY id ASC"}
      """);
    } catch (e) {
      print("Query error: $e");
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> queryByParam(String tableName, String param) async {
    try {
      Database db = await database;
      return await db.rawQuery("""
        SELECT * FROM $tableName
        WHERE id IN (
          SELECT MIN(id) FROM $tableName
          WHERE mid =? OR name LIKE? OR playId =?
          GROUP BY mid
        )
        ORDER BY name ASC
      """, [param, "%$param%", param]);
    } catch (e) {
      print("Update error: $e");
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> queryRandom({required String tableName, int? limit}) async {
    try {
      Database db = await database;
      return await db.query(
        tableName,
        orderBy: "RANDOM()",
        limit: limit ?? 1,
      );
    } catch (e) {
      print("Update error: $e");
      rethrow;
    }
  }

  Future<int> update(String tableName, Map<String, dynamic> row) async {
    try {
      Database db = await database;
      String mid = row["mid"];
      String playId = row["playId"];

      return await db.update(
        tableName,
        row,
        where: "mid =? OR playId =?",
        whereArgs: [mid, playId],
      );
    } catch (e) {
      print("Update error: $e");
      rethrow;
    }
  }

  Future<int> delete(String tableName, String param) async {
    try {
      Database db = await database;
      return await db.delete(
        tableName,
        where: "mid =? OR name=?",
        whereArgs: [param, param],
      );
    } catch (e) {
      print("Delete error: $e");
      rethrow;
    }
  }

  /// 按歌曲 mid 精确删除（只删这一首，不会误删同名歌曲）
  Future<int> deleteByMid(String tableName, String mid) async {
    try {
      Database db = await database;
      return await db.delete(tableName, where: "mid =?", whereArgs: [mid]);
    } catch (e) {
      print("Delete error: $e");
      rethrow;
    }
  }

  Future<int> deleteAll(String tableName) async {
    try {
      Database db = await database;
      // 检查表是否存在
      bool isExist = await isTableExists(tableName);

      if (isExist) {
        // 表存在，执行删除操作
        return await db.rawDelete("DELETE FROM $tableName");
      } else {
        // 表不存在，返回 0 表示未删除任何记录
        return 0;
      }
    } catch (e) {
      print("Delete error: $e");
      rethrow;
    }
  }
}

class DBOrder extends BaseDatabaseHelper {
  DBOrder({
    int version = 3,
  }) : super._internal(DBName.orderName, version);

  @override
  Future<void> _onCreate(Database db, int version) async {
    /// 本地
    await db.execute(orderTableSql(TableName.musicLocal));
    /// 满满音乐
    await db.execute(orderTableSql(TableName.myMusic));
    /// 待播放列表
    await db.execute(orderTableSql(TableName.musicWaitPlay));
  }

  @override
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await _migrateToMyMusic(db);
    }
  }

  /// v2 → v3：把「我喜欢」和所有「收藏夹_xxx」并成一张「满满音乐」
  ///
  /// 老版本每个收藏夹单独建一张表，表名取自标题，重名或标题为空时
  /// 建表直接抛 "table already exists"，导入也就跟着失败。
  /// 现在只剩一张表，结构上不可能再撞名。
  Future<void> _migrateToMyMusic(Database db) async {
    await db.execute(orderTableSql(TableName.myMusic));

    if (await _tableExists(db, TableName.legacyILike)) {
      await _mergeTable(db, from: TableName.legacyILike, into: TableName.myMusic);
      await db.execute('DROP TABLE "${TableName.legacyILike}"');
    }

    final legacyFavTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '收藏夹\\_%' ESCAPE '\\'",
    );
    for (final row in legacyFavTables) {
      final name = "${row["name"]}";
      if (name.isEmpty) continue;
      await _mergeTable(db, from: name, into: TableName.myMusic);
      await db.execute('DROP TABLE "$name"');
    }

    await db.rawUpdate(
      "UPDATE ${TableName.myMusic} SET orderName = ?",
      [TableName.myMusic],
    );
  }

  Future<bool> _tableExists(Database db, String tableName) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    return rows.isNotEmpty;
  }

  /// 把 [from] 里 [into] 没有的歌并进 [into]（按 mid 去重）
  Future<void> _mergeTable(
    Database db, {
    required String from,
    required String into,
  }) async {
    final rows = await db.query(from);
    if (rows.isEmpty) return;

    final existing = await db.query(into, columns: ["mid"]);
    final ids = existing.map((e) => "${e["mid"]}").toSet();

    var index = 0;
    for (final row in rows) {
      final mid = "${row["mid"] ?? ""}";
      if (mid.isEmpty || !ids.add(mid)) continue;
      final playId = "${row["playId"] ?? ""}";
      await db.insert(into, {
        "mid": mid,
        "name": "${row["name"] ?? ""}",
        "cover": "${row["cover"] ?? ""}",
        "duration": row["duration"] is int ? row["duration"] : 0,
        "author": "${row["author"] ?? ""}",
        "origin": "${row["origin"] ?? OriginType.bili.value}",
        "playId": playId.isEmpty
            ? "m${DateTime.now().microsecondsSinceEpoch}$index"
            : playId,
        "lyric": "${row["lyric"] ?? ""}",
        "localPath": "${row["localPath"] ?? ""}",
        "prev": "",
        "next": "",
        "orderName": into,
        "isFirst": "",
        "isLast": "",
      });
      index += 1;
    }
  }
}

Map<String, dynamic> musicItem2Row({required MusicItem music, String? prev, String? next, String? isFirst, String? isLast, String? lyric}) {
  Map<String, dynamic> musicRow = {
    "mid": music.id,
    "name": music.name,
    "cover": music.cover,
    "duration": music.duration,
    "author": music.author,
    "origin": music.origin.value,
    "playId": music.playId,
    "lyric": lyric ?? music.lyric,
    "orderName": music.orderName,
    "localPath": music.localPath,
    "prev": prev ?? music.prev,
    "next": next ?? music.next,
    "isFirst": isFirst ?? music.isFirst,
    "isLast": isLast ?? music.isLast,
  };

  return musicRow;
}

MusicItem row2MusicItem({required Map<String, dynamic> dbRow, String? prev, String? next, String? isFirst, String? isLast, String? lyric}) {
  return MusicItem(
    id: dbRow["mid"] as String,
    cover: dbRow["cover"] as String,
    name: dbRow["name"] as String,
    duration: dbRow["duration"] as int,
    author: dbRow["author"] as String,
    origin: OriginType.getByValue(dbRow["origin"]),
    orderName: dbRow["orderName"] as String,
    localPath: dbRow["localPath"] as String,
    playId: dbRow["playId"] as String,
    lyric: lyric ?? dbRow["lyric"] as String,
    prev: prev ?? dbRow["prev"] as String,
    next: next ?? dbRow["next"] as String,
    isFirst: isFirst ?? dbRow["isFirst"] as String,
    isLast: isLast ?? dbRow["isLast"] as String,
  );
}
