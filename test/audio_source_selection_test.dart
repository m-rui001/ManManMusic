import "dart:convert";
import "dart:io";

import "package:bobomusic/modules/player/source.dart";
import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bobomusic/origin_sdk/bili/client.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/origin_sdk/service.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:path/path.dart" as path;

class _AudioService extends BiliClient {
  MusicUrl? available;

  @override
  Future<MusicUrl> getMusicUrl(String id) async =>
      available ?? (throw const SocketException("offline"));
}

const _aac = MusicUrl(
  url: "https://cdn.example/standard.m4s",
  format: "AAC",
  bitrate: 132000,
  trackId: 30280,
  codec: "mp4a.40.2",
);
const _upgraded = MusicUrl(
  url: "https://cdn.example/lossless.m4s",
  format: "FLAC",
  bitrate: 1100000,
  trackId: 30251,
  codec: "fLaC",
  alternatives: [_aac],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel("plugins.flutter.io/path_provider");
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final originalService = service;
  final auth = BiliAuth.instance;
  late Directory temporary;
  late _AudioService audioService;
  late File legacy;
  late MusicItem music;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp("manman-audio-cache-");
    messenger.setMockMethodCallHandler(paths, (_) async => temporary.path);
    audioService = _AudioService();
    service = audioService;
    auth.cookies["SESSDATA"] = "test-account";
    auth.mid = 123;
    music = MusicItem(
      id: "sample",
      name: "样本",
      author: "",
      cover: "",
      duration: 120,
      origin: OriginType.bili,
    );
    final key = base64Url.encode(utf8.encode(music2cacheKey(music)));
    final streamDirectory =
        Directory(path.join(temporary.path, "manman-streams"));
    await streamDirectory.create();
    legacy = await File(path.join(streamDirectory.path, "$key.m4a"))
        .writeAsString("old audio");
    await File("${legacy.path}.quality").writeAsString(_aac.description);
  });

  tearDown(() async {
    service = originalService;
    auth.cookies.clear();
    auth.mid = 0;
    messenger.setMockMethodCallHandler(paths, null);
    await temporary.delete(recursive: true);
  });

  test("账号获得无损后可以升级旧 AAC 缓存，失效时仍有旧 AAC 回退", () async {
    audioService.available = _upgraded;
    final candidates = await musicAudioCandidates(music).toList();

    expect(candidates.first.remote, same(_upgraded));
    expect(candidates.first.playbackCache, isNotNull);
    expect(candidates[1].file?.path, legacy.path);
    expect(candidates[1].description, "AAC · 约 132 kbps · 本机缓存");
    expect(candidates[2].remote, same(_aac));
  });

  test("同档原轨复用缓存，断网时保留旧缓存", () async {
    audioService.available = _aac;
    expect((await musicAudioCandidates(music).first).file?.path, legacy.path);

    audioService.available = null;
    expect((await musicAudioCandidates(music).single).file?.path, legacy.path);
  });

  test("游客可优先播放更高码率的 AAC，旧缓存仍可回退", () async {
    auth.cookies.clear();
    const higher = MusicUrl(
      url: "https://cdn.example/higher.m4s",
      format: "AAC",
      bitrate: 198000,
      trackId: 30280,
      codec: "mp4a.40.2",
      alternatives: [_aac],
    );
    audioService.available = higher;

    final candidates = await musicAudioCandidates(music).toList();
    expect(candidates.first.remote, same(higher));
    expect(candidates[1].file?.path, legacy.path);
  });

  test("仅当前账号可复用新无损缓存，在线档位变更后回到 AAC", () async {
    audioService.available = _upgraded;
    final preferred = await musicAudioCandidates(music).first;
    final premium = preferred.playbackCache!;
    await premium.parent.create(recursive: true);
    await premium.writeAsString("finished audio");
    final unfinished = File("${premium.path}.part");
    await unfinished.writeAsString("unfinished audio");

    expect((await musicAudioCandidates(music).first).file?.path, premium.path);
    audioService.available = null;
    expect((await musicAudioCandidates(music).first).file?.path, premium.path);

    auth.mid = 456;
    expect((await musicAudioCandidates(music).single).file?.path, legacy.path);
    auth.mid = 123;
    audioService.available = _aac;
    final candidates = await musicAudioCandidates(music).toList();
    expect(candidates.first.file?.path, legacy.path);
    expect(candidates.map((source) => source.file?.path),
        isNot(contains(premium.path)));
  });
}
