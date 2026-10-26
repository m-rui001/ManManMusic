import "dart:async";
import "dart:convert";

import "package:bobomusic/constants/cache_key.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:bobomusic/modules/player/const.dart";
import "package:bobomusic/modules/player/source.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/throttle.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";
import "package:just_audio/just_audio.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:uuid/uuid.dart";

const uuid = Uuid();
var db = DBOrder(version: 2);

final _storageKeyCurrent = CacheKey.playerCurrent;
final _storageKeyPlayerMode = CacheKey.playerMode;
final _storageKeyPosition = CacheKey.playerPosition;

class BBPlayer {
  Timer? _timer;
  bool isLoading = false;
  final List<StreamSubscription?> _subscriptions = [];

  bool get isPlaying {
    return audio.playing;
  }

  final audio = AudioPlayer();
  MusicItem? current;
  final List<MusicItem> playerList = [];
  PlayerMode playerMode = PlayerMode.listLoop;

  /// 开始播放时的回调（用于记录历史播放）
  void Function(MusicItem music)? onPlayRecord;

  late AutoCloseMusic autoClose;

  Future<void> init() async {
    autoClose = AutoCloseMusic(onPause: () {
      pause();
    });
    await _initLocalStorage();
    var throttleEndNext = Throttle(const Duration(seconds: 1));

    _subscriptions.add(audio.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.loading) {
        isLoading = true;
      }
      if (state.processingState == ProcessingState.ready) {
        isLoading = false;
      }
      if (state.processingState == ProcessingState.completed) {
        throttleEndNext.call(() {
          if (autoClose.isPlayDoneAutoClose) {
            autoClose.isPlayDoneAutoClose = false;
            return pause();
          }
          return endNext();
        });
      }
    }));

    var t = DateTime.now();
    _subscriptions.add(audio.positionStream.listen((event) {
      var n = DateTime.now();
      if (t.add(const Duration(seconds: 1)).isBefore(n)) {
        _cachePosition();
        t = n;
      }
    }));
  }

  void dispose() {
    for (var sub in _subscriptions) {
      sub?.cancel();
    }
    audio.dispose();
    _timer?.cancel();
    autoClose.cancel();
  }

  // 播放
  Future<void> play({MusicItem? music}) async {
    if (music != null) {
      if (
        current == null ||
        (current!.orderName != music.orderName) ||
        (current!.playId.isNotEmpty && current!.playId != music.playId) ||
        current!.id != music.id
      ) {
        current = music;
        _updateLocalStorage();

        await audio.seek(Duration.zero);
        await _play(music: music);
      } else {
        // 和 current 相等
        if (isPlaying) {
          // 播放中暂停
          await audio.pause();
        } else {
          // 暂停中恢复播放
          await _play();
        }
      }
    } else {
      if (current != null) {
        if (isPlaying) {
          // 播放中暂停
          await audio.pause();
        } else {
          // 停止中恢复播放
          await _play();
        }
      } else {
        // 没有播放列表
        if (playerList.isNotEmpty) {
          // 播放列表不为空
          current = playerList.first;
          _updateLocalStorage();
          if (current != null) {
            await _play(music: current);
          }
        }
      }
    }

    if (current!.duration == 0 && audio.duration != null) {
      await db.update(current!.orderName, musicItem2Row(music: current!.copyWith(duration: audio.duration!.inSeconds)));
    }

    eventBus.fire(RefreshPlayerCard());
    _updateLocalStorage();
  }

  // 暂停
  Future<void> pause() async {
    await audio.pause();
    _updateLocalStorage();
  }

  // 上一首
  Future<void> prev() async {
    if(current != null && !await db.isTableExists(current!.orderName)) {
      BotToast.showText(text: "找不到上一曲");
      return;
    }

    await audio.seek(Duration.zero);

    if (current != null && current!.orderName.isNotEmpty) {
      final newCurrentMusic = await db.queryByParam(current!.orderName, current!.id);

      // 检查当前播放歌曲在列表中的 prev 变了没有，变了要重新赋值，变了就意味着列表里有歌曲增减
      if (newCurrentMusic.isNotEmpty && newCurrentMusic[0]["prev"] != current!.prev) {
        current = row2MusicItem(dbRow: newCurrentMusic[0]);
      }

      // 如果当前模式是列表顺序播放
      if (playerMode == PlayerMode.listOrder && current!.isFirst == "true") {
        BotToast.showText(text: "已经是列表第一首 QAQ");
        return;
      }

      final lastMusic = await db.queryByParam(current!.orderName, current!.prev);

      if (lastMusic.isNotEmpty) {
        await play(music: row2MusicItem(dbRow: lastMusic[0]));
      } else {
        BotToast.showText(text: "找不到上一曲。当前歌曲所在歌单：${current!.orderName}", duration: const Duration(seconds: 4));
        return;
      }
    }

    _updateLocalStorage();
  }

  // 下一首
  Future<void> next() async {
    if (current == null) return;

    if (playerMode != PlayerMode.signalLoop) {
      await endNext();
    } else {
      await audio.seek(Duration.zero);
      await play(music: current);
      await audio.play();
    }

    _updateLocalStorage();
  }

  // 结束播放
  Future<void> endNext() async {
    if (current == null) return;

    signalLoop() async {
      await audio.seek(Duration.zero);
      await play(music: current);
    }

    // 单曲循环
    if (playerMode == PlayerMode.signalLoop) {
      await signalLoop();
      if (!audio.playing) {
        audio.play();
      }

      _updateLocalStorage();
      return;
    }

    if(current != null && !await db.isTableExists(current!.orderName)) {
      BotToast.showText(text: "找不到下一曲", duration: const Duration(seconds: 4));
      return;
    }

    // 随机
    if (playerMode == PlayerMode.random) {
      final randomList = await db.queryRandom(tableName: current!.orderName);

      if (randomList.isEmpty) {
        BotToast.showText(text: "当前列表是空的 QAQ", duration: const Duration(seconds: 3));
        return;
      } else {
        await audio.seek(Duration.zero);
        await play(music: row2MusicItem(dbRow: randomList[0]));
      }

      _updateLocalStorage();

      return;
    }

    if (current!.orderName.isNotEmpty) {
      final newCurrentMusic = await db.queryByParam(current!.orderName, current!.playId.isEmpty ? current!.id : current!.playId);

      // 检查当前播放歌曲在列表中的 next 变了没有，变了要重新赋值，变了就意味着列表里有歌曲增减
      if (newCurrentMusic.isNotEmpty && newCurrentMusic[0]["next"] != current!.next) {
        current = row2MusicItem(dbRow: newCurrentMusic[0]);
      }
    }

    // 列表顺序播放
    if (playerMode == PlayerMode.listOrder) {
      // 待播放列表不为空
      if (playerList.isNotEmpty) {
        await audio.seek(Duration.zero);
        final index = playerList.indexWhere((music) => music.playId == current!.playId);

        if (index >= 0) {
          if (playerList[index].isLast != "true") {
            await play(music: playerList[index + 1]);
          } else {
            BotToast.showText(text: "已经是列表最后一首了 QAQ");

            return;
          }
        } else {
          await play(music: playerList.first);
        }

        _updateLocalStorage();
        return;
      }
      /// -----------------------------------------------------------------------
      if (current!.next.isNotEmpty && current!.isLast == "false" && current!.orderName.isNotEmpty) {
        final nextDbMusics = await db.queryByParam(current!.orderName, current!.next);

        if (nextDbMusics.isNotEmpty) {
          await audio.seek(Duration.zero);
          await play(music: row2MusicItem(dbRow: nextDbMusics[0]));
        } else {
          BotToast.showText(text: "找不到下一曲。当前歌曲所在歌单：${current!.orderName}", duration: const Duration(seconds: 4));

          return;
        }
      } else if (current!.isLast == "true") {
        BotToast.showText(text: "已经是列表最后一首歌了 QAQ", duration: const Duration(seconds: 3));

        return;
      }

      if (!audio.playing) {
        audio.play();
      }

      _updateLocalStorage();

      return;
    }

    // 列表循环
    if (playerMode == PlayerMode.listLoop) {
      // 待播放列表不为空
      if (playerList.isNotEmpty) {
        final targets = playerList.where((music) => music.playId == current!.next);

        await audio.seek(Duration.zero);

        if (targets.isNotEmpty) {
          await play(music: targets.first);
        } else {
          await play(music: playerList.first);
        }

        _updateLocalStorage();
        return;
      }
      /// -----------------------------------------------------------------------
      if (current!.next.isNotEmpty && current!.orderName.isNotEmpty) {
        final dbMusics = await db.queryByParam(current!.orderName, current!.next);

        if (dbMusics.isNotEmpty) {
          await audio.seek(Duration.zero);
          await play(music: row2MusicItem(dbRow: dbMusics[0]));
        } else {
          BotToast.showText(text: "找不到下一曲。当前歌曲所在歌单：${current!.orderName}", duration: const Duration(seconds: 4));

          return;
        }
      }

      if (!audio.playing) {
        audio.play();
      }

      _updateLocalStorage();
    }
  }

  // 切换播放模式
  void togglePlayerMode({PlayerMode? mode}) {
    if (mode != null) {
      playerMode = mode;
    } else {
      const l = [
        PlayerMode.signalLoop,
        PlayerMode.listLoop,
        PlayerMode.random,
        PlayerMode.listOrder,
      ];
      int index = l.indexWhere((p) => playerMode == p);

      if (index == l.length - 1) {
        playerMode = l[0];
      } else {
        playerMode = l[index + 1];
      }
    }

    _updateLocalStorage();
    // notifyListeners();
  }

  // 添加到待播放列表中
  // 这块逻辑确实不够优雅，但是不管那么多了
  Future<void> addPlayerList(List<MusicItem> musics, {bool? showToast = false}) async {
    if (playerList.length + musics.length > 1000) {
      BotToast.showText(text: "出于性能考虑，列表歌曲不能超过 1000 首");
      return;
    }

    EasyLoading.show(maskType: EasyLoadingMaskType.black);

    List<MusicItem> mList = [];
    for (var m in musics) {
      final newM = m.copyWith(
        playId: uuid.v4(),
        orderName: TableName.musicWaitPlay
      );
      mList.add(newM);
    }
    playerList.addAll(mList);

    await db.deleteAll(TableName.musicWaitPlay);

    for (var pm in playerList) {
      await db.insert(TableName.musicWaitPlay, musicItem2Row(music: pm));
    }

    final newMusicList = await getUpdatedMusicList(tabName: TableName.musicWaitPlay);

    playerList.clear();
    playerList.addAll(newMusicList);

    EasyLoading.dismiss();

    if (current != null) {
      final targets = newMusicList.where((music) => music.playId == current!.playId).toList();

      if (targets.isNotEmpty) {
        current = targets.first;
      }
    }

    if (showToast != null && showToast) {
      BotToast.showText(text: "已添加到待播放列表");
    }
  }

  // 在待播放列表中移除
  Future<void> removePlayerList(List<MusicItem> musics) async {
    EasyLoading.show(maskType: EasyLoadingMaskType.black);
    try {
      playerList.removeWhere((w) => musics.where((e) => e.playId == w.playId).isNotEmpty);

      for (var m in musics) {
        await db.delete(TableName.musicWaitPlay, m.playId);
      }

      await getUpdatedMusicList(tabName: TableName.musicWaitPlay);
    } catch (error) {
      print(error);
    }
    EasyLoading.dismiss();
  }

  // 清空播放列表
  Future<void> clearPlayerList() async {
    EasyLoading.show(maskType: EasyLoadingMaskType.black);
    try {
      playerList.clear();
      await db.deleteAll(TableName.musicWaitPlay);
    } catch (error) {
      print(error);
    }

    EasyLoading.dismiss();
  }

  Future<void> _play({MusicItem? music, bool isPlay = true}) async {
    if (music != null) {
      if (music.localPath.isNotEmpty) {
        await audio.setFilePath(music.localPath);
      } else {
        try {
          await audio.setAudioSource(BBMusicSource(music));
        } catch (error) {
          BotToast.showText(text: "播放失败：$error");
        }
      }
    }

    if (isPlay) {
      await audio.play();
      // 真正开始播放时才记账：当前这首歌
      if (current != null) onPlayRecord?.call(current!);
    } else {
      await audio.pause();
    }
  }

  // 缓存播放进度
  Future<void> _cachePosition() async {
    final localStorage = await SharedPreferences.getInstance();
    localStorage.setInt(
      _storageKeyPosition,
      audio.position.inMilliseconds,
    );
  }

  // 更新缓存
  void _updateLocalStorage() {
    _timer?.cancel();
    _timer = Timer(const Duration(microseconds: 500), () async {
      final localStorage = await SharedPreferences.getInstance();
      localStorage.setString(
        _storageKeyCurrent,
        current != null ? jsonEncode(current) : "",
      );
      localStorage.setString(
        _storageKeyPlayerMode,
        playerMode.value.toString(),
      );
    });
  }

  // 读取缓存
  Future<void> _initLocalStorage() async {
    final localStorage = await SharedPreferences.getInstance();
    // 当前歌曲
    String? c = localStorage.getString(_storageKeyCurrent);
    if (c != null && c.isNotEmpty) {
      var data = jsonDecode(c) as Map<String, dynamic>;
      current = MusicItem(
        id: data["id"],
        name: data["name"],
        cover: data["cover"],
        author: data["author"],
        duration: data["duration"],
        origin: OriginType.getByValue(data["origin"]),
        playId: data["playId"],
        lyric: data["lyric"],
        prev: data["prev"],
        next: data["next"],
        orderName: data["orderName"],
        localPath: data["localPath"],
        isFirst: data["isFirst"],
        isLast: data["isLast"],
      );

      _play(music: current!, isPlay: false).then((res) {
        // 设置播放进度
        final pos = localStorage.getInt(_storageKeyPosition) ?? 0;
        if (pos > 0) {
          audio.seek(Duration(milliseconds: pos));
        }
      });
    }

    // 播放模式
    String? m = localStorage.getString(_storageKeyPlayerMode);
    if (m != null && m.isNotEmpty) {
      playerMode = PlayerMode.getByValue(int.parse(m));
    }

    // 待播放列表
    List<MusicItem> playMusics = (await db.queryAll(TableName.musicWaitPlay, groupBy: "playId")).map((e) => row2MusicItem(dbRow: e)).toList();
    addPlayerList(playMusics);
  }
}

/// 定时关闭
class AutoCloseMusic {
  bool openPlayDoneAutoClose = false; // 是否开启等待播放完成后再关闭
  bool isPlayDoneAutoClose = false;
  DateTime? closeTime;
  Timer? autoCloseTimer;

  final Function onPause;

  AutoCloseMusic({
    required this.onPause,
  });

  void togglePlayDoneAutoClose() {
    openPlayDoneAutoClose = !openPlayDoneAutoClose;
  }

  // 自动关闭
  void close(Duration duration) {
    isPlayDoneAutoClose = false;
    if (autoCloseTimer != null) {
      autoCloseTimer!.cancel();
    }

    // 设置时间为 5 min 后
    final now = DateTime.now();
    closeTime = now.add(duration);

    autoCloseTimer = Timer(duration, () {
      if (openPlayDoneAutoClose) {
        isPlayDoneAutoClose = true;
      } else {
        onPause();
      }
    });
  }

  void cancel() {
    closeTime = null;
    isPlayDoneAutoClose = false;
    if (autoCloseTimer != null) {
      autoCloseTimer!.cancel();
    }
  }
}
