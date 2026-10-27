import "dart:async";

import "package:bobomusic/constants/cache_key.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bot_toast/bot_toast.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:uuid/uuid.dart";

const _uuid = Uuid();

/// 所有歌单（App 里只剩两张表：本地 + 满满音乐）
Future<List<String>> getAllOrderList() async {
  return [TableName.musicLocal, TableName.myMusic];
}

/// 把歌加进满满音乐
///
/// - 已在里面的歌会跳过（按 mid 去重）
/// - 返回真正新增的数量
Future<int> addToMyMusic(List<MusicItem> musics) async {
  final DBOrder db = DBOrder();
  final rows = await db.queryAll(TableName.myMusic);
  final existing = rows.map((e) => "${e["mid"]}").toSet();

  int added = 0;
  for (final music in musics) {
    if (music.id.isEmpty || !existing.add(music.id)) continue;

    await db.insert(
      TableName.myMusic,
      musicItem2Row(
        music: music.copyWith(
          orderName: TableName.myMusic,
          playId: music.playId.isEmpty ? _uuid.v4() : music.playId,
        ),
      ),
    );
    added += 1;
  }

  return added;
}

/// 收藏进「满满音乐」
///
/// 全 App 只有一张歌单，所以不再弹选择框，点一下就加进去。
collectToMusicOrder({required context, required musicList, onConfirm}) async {
  final added = await addToMyMusic(List<MusicItem>.from(musicList));

  if (added > 0) {
    BotToast.showText(text: added == 1 ? "已加入满满音乐" : "已把 $added 首加入满满音乐");
  } else {
    BotToast.showText(text: "已经在满满音乐里了");
  }

  if (onConfirm != null) onConfirm();
}

Future<List<MusicItem>> findMusicFromNotLocalOrders({required String param}) async {
  final DBOrder db = DBOrder();
  final dbMusics = await db.queryByParam(TableName.myMusic, param);
  return dbMusics.map((e) => row2MusicItem(dbRow: e)).toList();
}

Future<List<MusicItem>> findMusicFromLocalOrders({required String param}) async {
  final DBOrder db = DBOrder();
  final dbMusics = await db.queryByParam(TableName.musicLocal, param);
  return dbMusics.map((e) => row2MusicItem(dbRow: e)).toList();
}

/// 取出某个歌单的歌曲，并顺手把 prev / next 链补齐
Future<List<MusicItem>> getUpdatedMusicList({required String tabName}) async {
  final DBOrder db = DBOrder();
  List<MusicItem> newMusicList = [];
  // 需要回写 prev / next 的行先攒着，最后一次性事务更新
  final pending = <Map<String, dynamic>>[];

  try {
    final dbMusics = await db.queryAll(tabName, needOrder: false);
    final len = dbMusics.length;

    if (dbMusics.isNotEmpty) {
      for (int index = 0; index < len; index++) {
        final isLast = dbMusics[index]["playId"] == dbMusics.last["playId"];
        final prev = index > 0 ? dbMusics[index - 1]["playId"] : dbMusics.last["playId"];
        final next = isLast ? dbMusics.first["playId"] : dbMusics[index + 1]["playId"];
        final mPrev = "${dbMusics[index]["prev"] ?? ""}";
        final mNext = "${dbMusics[index]["next"] ?? ""}";

        if (mPrev.isEmpty || mNext.isEmpty || prev != mPrev || next != mNext) {
          final newM = row2MusicItem(
            dbRow: dbMusics[index],
            prev: prev,
            next: next,
            isFirst: index == 0 ? "true" : "false",
            isLast: isLast ? "true" : "false",
          );

          newMusicList.add(newM);
          pending.add(musicItem2Row(music: newM));
        } else {
          newMusicList.add(row2MusicItem(dbRow: dbMusics[index]));
        }
      }
    }

    if (pending.isNotEmpty) {
      await db.updateAll(tabName, pending);
    }

    return newMusicList;
  } catch (error) {
    return [];
  }
}

Future<int> getCurrentTabIndex() async {
  final localStorage = await SharedPreferences.getInstance();
  final int index = localStorage.getInt(CacheKey.currentTabIndex) ?? 0;
  return index;
}

setCurrentTabIndex({required int index}) async {
  final localStorage = await SharedPreferences.getInstance();
  await localStorage.setInt(CacheKey.currentTabIndex, index);
}
