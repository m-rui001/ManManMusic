import "dart:async";
import "dart:convert";
import "dart:io";

import "package:bobomusic/constants/cache_key.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:bobomusic/modules/party/party_service.dart";
import "package:bobomusic/modules/player/const.dart";
import "package:bobomusic/modules/player/audio_processing.dart";
import "package:bobomusic/modules/player/source.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/services.dart";
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
  bool processingAudio = false;
  bool automaticAudioProcessing = true;
  String? audioProcessingStatus;
  bool _checkingAudioCache = false;
  int? _audioProcessedAttempt;
  bool _usingProcessedAudio = false;
  ({
    AudioSource original,
    AudioSource source,
    File file,
    List<LocalAudioEffect> effects
  })? _processedAudio;
  List<LocalAudioEffect> get activeAudioEffects =>
      _usingProcessedAudio ? _processedAudio?.effects ?? const [] : const [];
  Completer<void>? _audioSwap;
  static const _autoAudioKey = "automatic_audio_processing";
  static const _audioChannel = MethodChannel("manman/audio");
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
        unawaited(_tryAutomaticAudioProcessing());
      }
    }));
    await _initLocalStorage();
  }

  void dispose() {
    _invalidateAudioRender();
    for (var sub in _subscriptions) {
      sub?.cancel();
    }
    final processed = _processedAudio;
    if (processed != null) unawaited(_removeRepairFile(processed.file));
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
    final swap = _audioSwap;
    if (swap != null) await swap.future;
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
    final request = _loadRequest;
    final swap = _audioSwap;
    if (swap != null) await swap.future;
    if (request != _loadRequest) return;
    await audio.seek(position);
    await _cachePosition();
  }

  Future<void> prev() => _step(-1);

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

  Future<void> setAutomaticAudioProcessing(bool enabled) async {
    if (automaticAudioProcessing == enabled) return;
    automaticAudioProcessing = enabled;
    eventBus.fire(RefreshAudioOptions());
    if (!enabled) _cancelAudioRender(_loadRequest);
    final swap = _audioSwap;
    if (swap != null) await swap.future;
    if (automaticAudioProcessing == enabled) {
      if (enabled) {
        _audioProcessedAttempt = null;
        unawaited(_tryAutomaticAudioProcessing());
      } else if (_usingProcessedAudio && !isLoading) {
        final original = _processedAudio!.original;
        if (!await _switchAudioSource(original, _loadRequest,
            processed: false)) {
          audioProcessingStatus = "暂时无法切回原轨";
        }
      }
    }
    eventBus.fire(RefreshAudioOptions());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoAudioKey, automaticAudioProcessing);
  }

  Future<File?> _cachedAudioInput(AudioSource? source) async {
    final input = switch (source) {
      LockCachingAudioSource() => await source.cacheFile,
      UriAudioSource(uri: final uri) when uri.scheme == "file" =>
        File.fromUri(uri),
      _ => null,
    };
    return input != null && await input.exists() ? input : null;
  }

  bool _hasTimeToSwitchAudio() {
    final duration = audio.duration;
    return duration == null ||
        duration - audio.position > const Duration(seconds: 3);
  }

  Future<void> _tryAutomaticAudioProcessing() async {
    if (!supportsAudioProcessing ||
        !automaticAudioProcessing ||
        _checkingAudioCache ||
        processingAudio ||
        _usingProcessedAudio ||
        _audioProcessedAttempt == _loadRequest ||
        !isPlaying ||
        isLoading ||
        !_hasTimeToSwitchAudio()) {
      return;
    }
    final request = _loadRequest;
    final original = audio.audioSource;
    if (original == null) return;

    _checkingAudioCache = true;
    File? rendered;
    try {
      final saved = _processedAudio;
      if (saved != null) {
        if (await _switchAudioSource(saved.source, request, processed: true)) {
          audioProcessingStatus = null;
        } else if (request == _loadRequest) {
          _audioProcessedAttempt = request;
          audioProcessingStatus = "暂时无法应用音效，继续播放原轨";
        }
        return;
      }
      final input = await _cachedAudioInput(original);
      if (input == null ||
          request != _loadRequest ||
          !automaticAudioProcessing ||
          !isPlaying ||
          !_hasTimeToSwitchAudio()) {
        return;
      }

      _audioProcessedAttempt = request;
      processingAudio = true;
      audioProcessingStatus = null;
      eventBus.fire(RefreshAudioOptions());
      final result = await _audioChannel.invokeMapMethod<String, dynamic>(
        "renderAudio",
        {"path": input.path, "request": request},
      );
      if (result == null) return;
      rendered = File(result["path"] as String);
      if (request != _loadRequest || !automaticAudioProcessing) return;

      final originalDuration = audio.duration;
      final renderedDuration =
          Duration(milliseconds: result["durationMs"] as int);
      if (originalDuration != null &&
          (originalDuration - renderedDuration).abs() >
              const Duration(milliseconds: 100)) {
        audioProcessingStatus = "处理后的时长与原轨有差异，继续播放原轨";
        return;
      }
      final names = (result["effects"] as List).cast<String>();
      final effects = LocalAudioEffect.values
          .where((effect) => names.contains(effect.name))
          .toList();
      if (effects.isEmpty) return;
      final tag = original is IndexedAudioSource ? original.tag : null;
      final processed = AudioSource.file(rendered.path, tag: tag);
      _processedAudio = (
        original: original,
        source: processed,
        file: rendered,
        effects: effects,
      );
      rendered = null;
      if (!_hasTimeToSwitchAudio()) {
        _audioProcessedAttempt = null;
        return;
      }
      if (!await _switchAudioSource(processed, request, processed: true) &&
          request == _loadRequest) {
        audioProcessingStatus = "暂时无法应用音效，继续播放原轨";
      }
    } on FileSystemException {
      // The cache can be temporarily unavailable or evicted by Android.
    } on PlatformException catch (error) {
      if (request != _loadRequest || !automaticAudioProcessing) return;
      audioProcessingStatus = switch (error.code) {
        "cancelled" => null,
        "unchanged" => "这首曲目适合保留原轨",
        "format" => "此音轨格式暂不支持本地处理",
        "storage" => "本机存储空间不足，继续播放原轨",
        "size" => "曲目超过本地处理长度上限，继续播放原轨",
        "timeout" => "本地处理超时，继续播放原轨",
        _ => "此音轨无法处理，继续播放原轨",
      };
      if (error.code == "cancelled") _audioProcessedAttempt = null;
    } catch (_) {
      if (request == _loadRequest) audioProcessingStatus = "此音轨无法处理";
    } finally {
      if (rendered != null) unawaited(_removeRepairFile(rendered));
      _checkingAudioCache = false;
      if (processingAudio || _processedAudio != null) {
        processingAudio = false;
        eventBus.fire(RefreshAudioOptions());
      }
    }
  }

  Future<bool> _switchAudioSource(AudioSource target, int request,
      {required bool processed}) async {
    final previous = audio.audioSource;
    if (_audioSwap != null || previous == null || request != _loadRequest) {
      return false;
    }
    final swap = _audioSwap = Completer<void>();
    final position = audio.position;
    final wasPlaying = isPlaying;
    final watch = Stopwatch()..start();
    try {
      await audio.setAudioSource(target, initialPosition: position);
      if (request != _loadRequest) return false;
      if (wasPlaying &&
          isPlaying &&
          PartyService.instance.role != PartyRole.none) {
        final elapsed = Duration(
            microseconds: (watch.elapsedMicroseconds * audio.speed).round());
        final expected = position + elapsed;
        final duration = audio.duration;
        if ((expected - audio.position).inMilliseconds > 80 &&
            (duration == null || expected < duration)) {
          await audio.seek(expected);
        }
      }
      if (request != _loadRequest) return false;
      _usingProcessedAudio = processed;
      return true;
    } on PlayerInterruptedException {
      return false;
    } on PlayerException {
      if (request == _loadRequest) {
        await audio.setAudioSource(previous, initialPosition: position);
      }
      return false;
    } finally {
      _audioSwap = null;
      swap.complete();
    }
  }

  Future<void> _removeRepairFile(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Android can evict temporary audio files before this cleanup.
    }
  }

  int _invalidateAudioRender() {
    final previous = _loadRequest++;
    _cancelAudioRender(previous);
    return _loadRequest;
  }

  void _cancelAudioRender(int request) {
    if (!processingAudio) return;
    unawaited(_audioChannel.invokeMethod<void>("cancelAudioRender", {
      "request": request,
    }).onError<Object>((_, __) {}));
  }

  Future<void> _load(MusicItem music, {bool Function()? isCurrent}) async {
    final request = _invalidateAudioRender();
    bool canLoad() => request == _loadRequest && (isCurrent?.call() ?? true);
    isLoading = true;
    try {
      final swap = _audioSwap;
      if (swap != null) await swap.future;
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
        final previous = _processedAudio;
        _processedAudio = null;
        _usingProcessedAudio = false;
        audioProcessingStatus = null;
        if (previous != null) {
          unawaited(_removeRepairFile(previous.file));
        }
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
    unawaited(_tryAutomaticAudioProcessing());
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
    automaticAudioProcessing = localStorage.getBool(_autoAudioKey) ??
        localStorage.getBool("automatic_bandwidth_extension") ??
        true;
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
