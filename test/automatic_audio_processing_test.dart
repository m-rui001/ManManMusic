import "dart:async";
import "dart:io";

import "package:bobomusic/modules/party/party_service.dart";
import "package:bobomusic/modules/player/audio_processing.dart";
import "package:bobomusic/modules/player/instance.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:just_audio/just_audio.dart";
import "package:shared_preferences/shared_preferences.dart";

class _TestAudio implements AudioPlayer {
  final switchingSource = Completer<void>();
  final finishSwitch = Completer<void>();

  @override
  AudioSource? audioSource;
  @override
  Duration position = Duration.zero;
  @override
  bool playing = false;
  @override
  Duration get duration => const Duration(minutes: 2);
  @override
  double get speed => 1;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();

  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true,
      int? initialIndex,
      Duration? initialPosition}) async {
    audioSource = source;
    position = initialPosition ?? Duration.zero;
    if (source is UriAudioSource && source.uri.path.endsWith("effects.wav")) {
      switchingSource.complete();
      await finishSwitch.future;
    }
    return duration;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    this.position = position ?? Duration.zero;
  }

  @override
  Future<void> play() async => playing = true;
  @override
  Future<void> pause() async => playing = false;
  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel("manman/audio");
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory cache;
  late _TestAudio audio;
  late BBPlayer player;
  late MusicItem music;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    PartyService.instance.role = PartyRole.guest;
    cache = await Directory.systemTemp.createTemp("manman-audio-test-");
    final original =
        await File.fromUri(cache.uri.resolve("original.m4a")).create();
    music = MusicItem(
      id: "test-audio",
      origin: OriginType.bili,
      name: "曲目",
      author: "测试",
      cover: "",
      duration: 120,
      localPath: original.path,
    );
    audio = _TestAudio();
    player = BBPlayer(audio: audio);
    await player.init();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "cancelAudioRender") return null;
      expect(call.method, "renderAudio");
      expect(call.arguments["path"], original.path);
      final processed =
          await File.fromUri(cache.uri.resolve("effects.wav")).create();
      return {
        "path": processed.path,
        "effects": ["bandwidth", "noise", "space"],
        "durationMs": 120000,
      };
    });
  });

  tearDown(() async {
    player.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    PartyService.instance.role = PartyRole.none;
    debugDefaultTargetPlatformOverride = null;
    await cache.delete(recursive: true);
  });

  Future<void> followAt(int seconds) => player.followRoom(
        music: music,
        playing: true,
        position: (_) => Duration(seconds: seconds),
        isCurrent: () => true,
      );

  test("一起听时叠加三项音效，切换过程中收到的房间进度仍能生效", () async {
    await followAt(12);
    await audio.switchingSource.future;
    expect(audio.position, const Duration(seconds: 12));
    final roomSeek = followAt(31);
    audio.finishSwitch.complete();
    await roomSeek;

    expect(audio.position, const Duration(seconds: 31));
    expect(audio.playing, isTrue);
    expect(player.activeAudioEffects, LocalAudioEffect.values);
  });

  test("音效轨正在载入时关闭自动音效，可以返回原轨和当前进度", () async {
    await followAt(12);
    await audio.switchingSource.future;
    final disabling = player.setAutomaticAudioProcessing(false);
    audio.finishSwitch.complete();
    await disabling;

    expect((audio.audioSource as UriAudioSource).uri.toFilePath(),
        music.localPath);
    expect(audio.position, const Duration(seconds: 12));
    expect(audio.playing, isTrue);
    expect(player.activeAudioEffects, isEmpty);
  });
}
