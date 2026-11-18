import "dart:async";

import "package:audio_service/audio_service.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/party/party_control.dart";
import "package:bobomusic/modules/player/service.dart";
import "package:bobomusic/modules/player/audio_equalizer.dart";
import "package:just_audio/just_audio.dart";
import "package:flutter/material.dart";
import "package:bobomusic/modules/player/const.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";

class PlayerModel extends ChangeNotifier {
  AudioPlayer? get _audio => _playerHandler?.player.audio;
  Duration? get duration => _audio?.duration;
  AudioHandler? _playerService;
  AudioPlayerHandler? _playerHandler;
  final List<StreamSubscription?> _subscriptions = [];

  MusicItem? get current => _playerHandler?.current;

  set current(MusicItem? value) {
    if (_playerHandler != null) {
      _playerHandler!.current = value;
      notifyListeners();
    }
  }

  bool get isLoading => _playerHandler?.player.isLoading ?? false;

  /// 当前播放进度
  Duration get currentPosition => _audio?.position ?? Duration.zero;
  Duration get bufferedPosition => _audio?.bufferedPosition ?? Duration.zero;
  Stream<Duration>? get positions => _audio?.positionStream;
  Stream<Duration>? get bufferedPositions => _audio?.bufferedPositionStream;

  bool get isPlaying {
    return _playerHandler?.player.isPlaying ?? false;
  }

  List<MusicItem> get playerList {
    return _playerHandler?.player.playerList ?? [];
  }

  PlayerMode get playerMode {
    return _playerHandler?.player.playerMode ?? PlayerMode.listLoop;
  }

  init({
    required AudioPlayerHandler playerHandler,
    required AudioHandler playerService,
  }) async {
    _playerHandler = playerHandler;
    _playerService = playerService;
    _subscriptions
        .add(eventBus.on<RefreshPlayerCard>().listen((_) => notifyListeners()));
    _subscriptions.add(
        eventBus.on<RefreshAudioOptions>().listen((_) => notifyListeners()));
    _subscriptions.add(_audio?.playerStateStream.listen((event) {
      notifyListeners();
    }));
    await playerHandler.player.init();
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub?.cancel();
    }
    super.dispose();
  }

  List<MusicItem> get collectionQueue =>
      _playerHandler?.player.collectionQueue ?? const [];

  String get sourceDescription =>
      _playerHandler?.player.sourceDescription ?? "";

  AudioEqualizer? get equalizer => _playerHandler?.player.equalizer;

  bool get repairingAudio => _playerHandler?.player.repairingAudio ?? false;
  AudioPreviewMode get audioPreviewMode =>
      _playerHandler?.player.audioPreviewMode ?? AudioPreviewMode.original;
  bool get automaticAudioRepair =>
      _playerHandler?.player.automaticAudioRepair ?? true;

  Future<String?> setAutomaticAudioRepair(bool enabled) async {
    final work = _playerHandler?.player.setAutomaticAudioRepair(enabled);
    notifyListeners();
    try {
      return await work;
    } finally {
      notifyListeners();
    }
  }

  Future<String?> setAudioRepair(AudioPreviewMode mode) async {
    final work = _playerHandler?.player.setAudioRepair(mode);
    notifyListeners();
    try {
      return await work;
    } finally {
      notifyListeners();
    }
  }

  Stream<PlayerState>? get playerStates => _audio?.playerStateStream;

  Future<void> followRoom({
    required MusicItem? music,
    required bool playing,
    required Duration Function(Duration?) position,
    required bool Function() isCurrent,
  }) async {
    await _playerHandler?.player.followRoom(
      music: music,
      playing: playing,
      position: position,
      isCurrent: isCurrent,
    );
    notifyListeners();
  }

  Future<bool> setLyrics(MusicItem music, String lyrics) async {
    final updated =
        await _playerHandler?.player.setLyrics(music, lyrics) ?? false;
    if (updated) notifyListeners();
    return updated;
  }

  // 播放
  Future<void> play({MusicItem? music, List<MusicItem>? collection}) async {
    if (PartyControl.blocked()) return;
    await _playerHandler?.play(music: music, collection: collection);
    notifyListeners();
  }

  // 暂停
  Future<void> pause() async {
    if (PartyControl.blocked()) return;
    await _playerService?.pause();
    notifyListeners();
  }

  // 上一首
  Future<void> prev() async {
    if (PartyControl.blocked()) return;
    await _playerService?.skipToPrevious();
    notifyListeners();
  }

  // 下一首
  Future<void> next() async {
    if (PartyControl.blocked()) return;
    await _playerService?.skipToNext();
    notifyListeners();
  }

  Future<void>? seek(Duration position) => _playerHandler?.seek(position);

  // 切换播放模式
  void togglePlayerMode({PlayerMode? mode}) {
    _playerHandler?.player.togglePlayerMode(mode: mode);
    notifyListeners();
  }

  // 添加到待播放列表中
  Future<void> addPlayerList(List<MusicItem> musics, {bool? showToast}) async {
    await _playerHandler?.player.addPlayerList(musics, showToast: showToast);
    notifyListeners();
  }

  // 在待播放列表中移除
  Future<void> removePlayerList(List<MusicItem> musics) async {
    await _playerHandler?.player.removePlayerList(musics);
    notifyListeners();
  }

  // 清空播放列表
  Future<void> clearPlayerList() async {
    await _playerHandler?.player.clearPlayerList();
    notifyListeners();
  }

  void togglePlayDoneAutoClose() {
    _playerHandler?.player.autoClose.togglePlayDoneAutoClose();
    notifyListeners();
  }

  get playDoneAutoClose {
    return _playerHandler?.player.autoClose.openPlayDoneAutoClose ?? false;
  }

  autoCloseHandler(Duration duration) {
    return _playerHandler?.player.autoClose.close(duration);
  }

  // 监听播放进度
  StreamSubscription<Duration>? listenPosition(
    void Function(Duration)? onData,
  ) {
    return _audio?.positionStream.listen(onData);
  }
}
