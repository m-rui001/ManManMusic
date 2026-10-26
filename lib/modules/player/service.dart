import "dart:async";

import "package:audio_service/audio_service.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/party/party_service.dart";
import "package:bobomusic/modules/player/instance.dart";
import "package:just_audio/just_audio.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";

class AudioPlayerHandler extends BaseAudioHandler {
  final BBPlayer player = BBPlayer();
  late PlaybackEvent _audioEvent;
  final List<StreamSubscription?> _subscriptions = [];

  double get _speed => player.audio.speed;
  MusicItem? get current => player.current;

  set current(MusicItem? value) {
    player.current = value;
    _updateMediaItem();
  }

  AudioPlayerHandler() {
    _subscriptions.add(player.audio.playbackEventStream.listen((event) {
      _audioEvent = event;
    }));
    _subscriptions.add(player.audio.playerStateStream.listen((state) {
      _updateMediaItem();
      _broadcastState();
    }));
    _updateMediaItem();
    _subscriptions.add(player.audio.positionStream.listen((position) {
      _updatePosition();
    }));
    _subscriptions.add(player.audio.durationStream.listen((duration) {
      if (mediaItem.value != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: duration));
      }
    }));
  }

  Future<void> disposeHandler() async {
    for (var sub in _subscriptions) {
      sub?.cancel();
    }
    player.dispose();
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    print("🎮 收到自定义操作: $name, 参数: $extras");

    switch (name) {
      case "toggle_lyrics":
        // 切换歌词显示状态
        print("🎮 收到自定义操作: toggle_lyrics}");
        break;
    }

    return super.customAction(name, extras);
  }

  /// 一起听里「只能听」的时候，本机控制一律拦掉
  ///
  /// 拦截点放在 audio handler 这一层，通知栏、锁屏、页面按钮就全都管住了。
  bool get _blocked => !PartyService.instance.allowLocalControl;

  @override
  Future<void> play({MusicItem? music}) async {
    if (_blocked) return;
    if (music != null) {
      await player.play(music: music); // 处理传入新音乐的情况
    } else {
      if (player.current == null) return; // 无当前音乐时返回
      await player.audio.play(); // 继续播放当前音乐
    }
    _updatePosition();
  }

  @override
  Future<void> pause() async {
    if (_blocked) return;
    await player.audio.pause(); // 直接调用播放器暂停
    _updatePosition();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_blocked) return;
    await player.audio.seek(position);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_blocked) return;
    await player.prev();
    _updateMediaItem();
  }

  @override
  Future<void> skipToNext() async {
    if (_blocked) return;
    await player.next();
    _updateMediaItem();
  }

  void _updateMediaItem() {
    if (player.current != null) {
      final newItem = music2mediaItem(player.current!);
      mediaItem.add(newItem.copyWith(
        duration: player.audio.duration ?? newItem.duration,
      ));
    }
  }

  void _updatePosition() {
    _audioEvent = _audioEvent.copyWith(
      updatePosition: player.audio.position,
      bufferedPosition: player.audio.bufferedPosition,
      updateTime: DateTime.now(),
    );
  }

  void _broadcastState() {
    eventBus.fire(ScrollLyric());

    final controls = [
      const MediaControl(
        action: MediaAction.skipToPrevious,
        androidIcon: "drawable/skip_previous",
        label: "上一曲",
      ),
      MediaControl(
        action: MediaAction.playPause,
        androidIcon: player.audio.playing ? "drawable/pause_circle" : "drawable/play_circle",
        label: "暂停/播放",
      ),
      const MediaControl(
        action: MediaAction.skipToNext,
        androidIcon: "drawable/skip_next",
        label: "下一曲",
      ),
    ];

    final processingState = {
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[player.audio.processingState] ?? AudioProcessingState.ready;

    playbackState.add(playbackState.value.copyWith(
      controls: controls,
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      processingState: processingState,
      playing: player.audio.playing, // 直接使用播放器状态
      updatePosition: player.audio.position,
      bufferedPosition: player.audio.bufferedPosition,
      speed: _speed,
      queueIndex: _audioEvent.currentIndex,
    ));
  }
}

MediaItem music2mediaItem(MusicItem music) {
  return MediaItem(
    id: music.id,
    title: music.name,
    album: music.author,
    artist: music.author,
    duration: Duration(seconds: music.duration),
  );
}
