import "dart:async";

import "package:audio_service/audio_service.dart";
import "package:bobomusic/modules/player/service.dart";
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
    await playerHandler.player.init();
    _subscriptions.add(_audio?.playerStateStream.listen((event) {
      notifyListeners();
    }));
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub?.cancel();
    }
    super.dispose();
  }

  // 播放
  Future<void> play({MusicItem? music}) async {
    await _playerHandler?.play(music: music);
    notifyListeners();
  }

  // 暂停
  Future<void> pause() async {
    await _playerService?.pause();
    notifyListeners();
  }

  // 上一首
  Future<void> prev() async {
    await _playerService?.skipToPrevious();
    notifyListeners();
  }

  // 下一首
  Future<void> next() async {
    await _playerService?.skipToNext();
    notifyListeners();
  }

  Future<void>? seek(Duration position) => _playerHandler?.seek(position);

  // 切换播放模式
  void togglePlayerMode({PlayerMode? mode}) {
    _playerHandler?.player.togglePlayerMode();
    notifyListeners();
  }

  // 添加到待播放列表中
  void addPlayerList(List<MusicItem> musics, {bool? showToast}) {
    _playerHandler?.player.addPlayerList(musics, showToast: showToast);
    notifyListeners();
  }

  // 在待播放列表中移除
  void removePlayerList(List<MusicItem> musics) {
    _playerHandler?.player.removePlayerList(musics);
    notifyListeners();
  }

  // 清空播放列表
  void clearPlayerList() {
    _playerHandler?.player.clearPlayerList();
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