import "dart:async";
import "dart:convert";

import "package:bobomusic/constants/cache_key.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:bobomusic/modules/party/party_service.dart";
import "package:bobomusic/modules/player/const.dart";
import "package:bobomusic/modules/player/source.dart";
import "package:bobomusic/modules/setting/playback_prefs.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bot_toast/bot_toast.dart";
import "package:just_audio/just_audio.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:uuid/uuid.dart";

const uuid = Uuid();
var db = DBOrder();

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

  final AudioPlayer audio;

  BBPlayer({AudioPlayer? audio}) : audio = audio ?? AudioPlayer();
  MusicItem? current;
  final List<MusicItem> playerList = [];
  List<MusicItem> collectionQueue = const [];
  String? _loadedTrack;
  String sourceDescription = "";
  static String _track(MusicItem item) => "${item.origin.value}:${item.id}";
  PlayerMode playerMode = PlayerMode.listLoop;

  /// 开始播放时的回调（用于记录历史播放）
  void Function(MusicItem music)? onPlayRecord;

  late AutoCloseMusic autoClose;

  Future<void> init() async {
    autoClose = AutoCloseMusic(onPause: () {
      pause();
    });
    _subscriptions.add(audio.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && state.playing) {
        unawaited(_completeTrack());
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
    await _initLocalStorage();
  }

  void dispose() {
    _loadRequest++;
    for (var sub in _subscriptions) {
      sub?.cancel();
    }
    audio.dispose();
    _timer?.cancel();
    autoClose.cancel();
  }

  Future<void> play({MusicItem? music, List<MusicItem>? collection}) async {
    final selected =
        music ?? current ?? (playerList.isEmpty ? null : playerList.first);
    if (selected == null) return;

    try {
      final sameEntry = current?.id == selected.id &&
          current?.origin == selected.origin &&
          current?.orderName == selected.orderName &&
          current?.playId == selected.playId;
      if (!sameEntry || _loadedTrack != _track(selected)) {
        await _play(music: selected);
      } else if (isPlaying) {
        await audio.pause();
      } else {
        await _play();
      }
      current = selected;
      if (collection != null) {
        collectionQueue = List.unmodifiable(collection);
      } else if (music != null && !collectionQueue.contains(music)) {
        collectionQueue = const [];
      }
      eventBus.fire(RefreshPlayerCard());
      _updateLocalStorage();
    } on PlayerInterruptedException {
      return;
    } catch (error) {
      BotToast.showText(text: "播放失败：$error");
    }
  }

  Future<void> followRoom({
    required MusicItem? music,
    required bool playing,
    required Duration Function(Duration?) position,
    required bool Function() isCurrent,
  }) async {
    if (music == null) {
      if (isCurrent()) await audio.pause();
      return;
    }
    if (!isCurrent()) return;
    final changed = _loadedTrack != _track(music);
    if (changed) {
      await _load(music, isCurrent: isCurrent);
      if (!isCurrent()) return;
      collectionQueue = const [];
      eventBus.fire(RefreshPlayerCard());
    }
    if (!isCurrent()) return;
    if (!playing && audio.playing) await audio.pause();
    final target = position(audio.duration);
    if (changed || (audio.position - target).abs().inMilliseconds > 900) {
      await audio.seek(target);
    }
    if (isCurrent() && playing && !audio.playing) _startPlayback();
  }

  Future<void> resume() async {
    final music = current;
    if (music == null || audio.playing) return;
    try {
      await _play(music: _loadedTrack == _track(music) ? null : music);
    } on PlayerInterruptedException {
      return;
    } catch (error) {
      BotToast.showText(text: "播放失败：$error");
    }
  }

  // 暂停
  Future<void> pause() async {
    await audio.pause();
    _updateLocalStorage();
  }

  Future<bool> setLyrics(MusicItem music, String lyrics) async {
    if (!identical(current, music)) return false;
    if (music.orderName.isNotEmpty) {
      await db.update(
          music.orderName, musicItem2Row(music: music.copyWith(lyric: lyrics)));
    }
    music.lyric = lyrics;
    if (!identical(current, music)) return false;
    _updateLocalStorage();
    return true;
  }

  Future<void> seek(Duration position) async {
    await audio.seek(position);
    await _cachePosition();
  }

  /// 「上一首」在播放超过 3 秒时先回到本曲开头。
  ///
  /// 听了一半想重听，不该被扔去上一首；连按两次才是真的切歌。
  Future<void> prev() async {
    if (PlaybackPrefs.instance.restartOnPrevious &&
        current != null &&
        audio.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    await _step(-1);
  }

  Future<void> next() => _step(1);

  bool _advancing = false;

  Future<void> _completeTrack() async {
    if (_advancing) return;
    _advancing = true;
    try {
      if (PartyService.instance.isGuest || autoClose.isPlayDoneAutoClose) {
        autoClose.isPlayDoneAutoClose = false;
        await pause();
      } else {
        await _step(1, completed: true);
      }
    } catch (_) {
      await pause();
    } finally {
      _advancing = false;
    }
  }

  Future<void> _step(int offset, {bool completed = false}) async {
    final music = current;
    if (music == null || isLoading) return;
    if (completed && playerMode == PlayerMode.signalLoop) {
      await audio.seek(Duration.zero);
      _startPlayback();
      return;
    }

    final List<MusicItem> queue;
    if (collectionQueue.isNotEmpty) {
      queue = collectionQueue;
    } else if (music.orderName == TableName.musicWaitPlay ||
        (offset > 0 && playerList.isNotEmpty)) {
      queue = playerList;
    } else if (music.orderName.isNotEmpty) {
      queue = await getUpdatedMusicList(tabName: music.orderName);
    } else {
      queue = const [];
    }
    if (!identical(current, music)) return;
    if (queue.isEmpty) {
      if (completed) {
        await pause();
      } else if (offset < 0) {
        await audio.seek(Duration.zero);
      }
      return;
    }

    final index = queue.indexWhere((entry) =>
        identical(entry, music) ||
        (music.playId.isNotEmpty && entry.playId == music.playId) ||
        (music.playId.isEmpty &&
            entry.orderName == music.orderName &&
            _track(entry) == _track(music)));
    final nextIndex = nextQueueIndex(
      length: queue.length,
      current: index,
      offset: offset,
      mode: playerMode,
    );
    if (nextIndex == null) {
      if (completed) await pause();
      return;
    }
    if (nextIndex == index) {
      await audio.seek(Duration.zero);
      _startPlayback();
    } else {
      await play(music: queue[nextIndex]);
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

  Future<void> _waitListMutation = Future.value();

  Future<void> addPlayerList(List<MusicItem> musics, {bool? showToast}) =>
      _mutateWaitList(() async {
        if (playerList.length + musics.length > 1000) {
          BotToast.showText(text: "待播放列表最多可加入 1000 首");
          return;
        }
        await db.insertAll(TableName.musicWaitPlay, [
          for (final music in musics)
            musicItem2Row(
                music: music.copyWith(
              playId: uuid.v4(),
              orderName: TableName.musicWaitPlay,
            )),
        ]);
        if (showToast == true) BotToast.showText(text: "已添加到待播放列表");
      });

  Future<void> removePlayerList(List<MusicItem> musics) =>
      _mutateWaitList(() async {
        final database = await db.database;
        await database.transaction((transaction) async {
          final batch = transaction.batch();
          for (final item in musics.where((music) => music.playId.isNotEmpty)) {
            batch.delete(TableName.musicWaitPlay,
                where: "playId = ?", whereArgs: [item.playId]);
          }
          await batch.commit(noResult: true);
        });
      });

  Future<void> clearPlayerList() => _mutateWaitList(() async {
        await db.deleteAll(TableName.musicWaitPlay);
      });

  Future<void> _mutateWaitList(Future<void> Function() action) {
    _waitListMutation = _waitListMutation.then((_) async {
      try {
        await action();
        await _readWaitList();
      } catch (_) {
        BotToast.showText(text: "待播放列表更新失败");
      }
    });
    return _waitListMutation;
  }

  Future<void> _readWaitList() async {
    final rows = await db.queryAll(
      TableName.musicWaitPlay,
      groupBy: "playId",
      needOrder: false,
    );
    playerList
      ..clear()
      ..addAll(rows.map((row) => row2MusicItem(dbRow: row)));
  }

  int _loadRequest = 0;

  Future<void> _load(MusicItem music, {bool Function()? isCurrent}) async {
    final request = ++_loadRequest;
    bool canLoad() => request == _loadRequest && (isCurrent?.call() ?? true);
    isLoading = true;
    try {
      if (!canLoad()) throw PlayerInterruptedException("歌曲已切换");
      Object? failure;
      await for (final source in musicSources(music)) {
        if (!canLoad()) throw PlayerInterruptedException("歌曲已切换");
        await audio.pause();
        if (!canLoad()) throw PlayerInterruptedException("歌曲已切换");
        _loadedTrack = null;
        sourceDescription = "";
        try {
          await audio.setAudioSource(source.audio);
        } on PlayerInterruptedException {
          rethrow;
        } on PlayerException catch (error) {
          failure = error;
          continue;
        }
        if (!canLoad()) throw PlayerInterruptedException("歌曲已切换");
        _loadedTrack = _track(music);
        sourceDescription = source.description;
        current = music;
        return;
      }
      throw failure ?? StateError("找不到可播放的音轨");
    } finally {
      if (request == _loadRequest) isLoading = false;
    }
  }

  Future<void> _play({MusicItem? music, bool isPlay = true}) async {
    if (music != null) await _load(music);
    if (isPlay) {
      if (music != null) unawaited(_cachePosition());
      if (audio.processingState == ProcessingState.completed) {
        await audio.seek(Duration.zero);
      }
      _startPlayback();
    }
  }

  void _startPlayback() {
    unawaited(audio.play().catchError((Object error) {
      BotToast.showText(text: "播放失败：$error");
    }));
    final music = current;
    if (music != null) onPlayRecord?.call(music);
  }

  // 缓存播放进度
  Future<void> _cachePosition() async {
    if (_loadedTrack == null || PartyService.instance.isGuest) return;
    final localStorage = await SharedPreferences.getInstance();
    localStorage.setInt(
      _storageKeyPosition,
      audio.position.inMilliseconds,
    );
  }

  // 更新缓存
  void _updateLocalStorage() {
    if (PartyService.instance.isGuest) return;
    _timer?.cancel();
    _timer = Timer(const Duration(microseconds: 500), () async {
      final localStorage = await SharedPreferences.getInstance();
      final music = current;
      await localStorage.setString(
          _storageKeyCurrent,
          music == null
              ? ""
              : jsonEncode({
                  ...music.toJson(),
                  if (collectionQueue.isNotEmpty) "collection": collectionQueue,
                  if (collectionQueue.isNotEmpty)
                    "collectionIndex": collectionQueue.indexOf(music),
                }));
      localStorage.setString(
        _storageKeyPlayerMode,
        playerMode.value.toString(),
      );
    });
  }

  // 读取缓存
  Future<void> _initLocalStorage() async {
    final localStorage = await SharedPreferences.getInstance();
    final savedPosition = localStorage.getInt(_storageKeyPosition) ?? 0;
    final mode =
        int.tryParse(localStorage.getString(_storageKeyPlayerMode) ?? "");
    if (mode != null && PlayerMode.values.any((value) => value.value == mode)) {
      playerMode = PlayerMode.getByValue(mode);
    }

    // Wait for pending queue writes before reloading the persisted rows.
    try {
      await _waitListMutation;
      await _readWaitList();
    } catch (_) {
      // Playback remains available if the local database is unavailable.
    }

    final encoded = localStorage.getString(_storageKeyCurrent);
    if (encoded == null || encoded.isEmpty || _loadRequest != 0) return;
    try {
      final data = jsonDecode(encoded) as Map<String, dynamic>;
      var saved = MusicItem.fromJson(data);
      final collection = data["collection"];
      final index = data["collectionIndex"];
      if (collection is List &&
          index is int &&
          index >= 0 &&
          index < collection.length) {
        final entries = collection
            .cast<Map<String, dynamic>>()
            .map(MusicItem.fromJson)
            .toList();
        if (_track(entries[index]) == _track(saved)) {
          entries[index] = saved;
          collectionQueue = List.unmodifiable(entries);
          saved = collectionQueue[index];
        }
      }
      current = saved;
      await _play(music: saved, isPlay: false);
      if (savedPosition > 0 && identical(current, saved)) {
        await audio.seek(Duration(milliseconds: savedPosition));
      }
      eventBus.fire(RefreshPlayerCard());
    } catch (_) {
      // The saved track can be retried from the player.
    }
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
