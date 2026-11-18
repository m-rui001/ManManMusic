import "dart:convert";
import "dart:io";

import "package:audio_service/audio_service.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/origin_sdk/service.dart";
import "package:flutter_cache_manager/flutter_cache_manager.dart";
import "package:just_audio/just_audio.dart";
import "package:path_provider/path_provider.dart";

final audioCacheManage = CacheManager(Config("bbmusicMediaCache"));

String music2cacheKey(MusicItem music) => "${music.origin.value}-${music.id}";

Future<File> _streamCacheFile(MusicItem music) async {
  final directory = await getTemporaryDirectory();
  final key = base64Url.encode(utf8.encode(music2cacheKey(music)));
  return File("${directory.path}/manman-streams/$key.m4a");
}

Future<File?> cachedMusicFile(MusicItem music) async {
  final current = await _streamCacheFile(music);
  if (await current.exists()) return current;
  final previous =
      await audioCacheManage.getFileFromCache(music2cacheKey(music));
  final file = previous?.file;
  return file != null && await file.exists() ? file : null;
}

Future<AudioSource> resolveMusicSource(MusicItem music) async {
  final tag = MediaItem(
    id: music.id,
    title: music.name,
    artUri: Uri.tryParse(music.cover),
  );
  final cached = await cachedMusicFile(music);
  if (cached != null) return AudioSource.file(cached.path, tag: tag);

  final audio = await service.getMusicUrl(music.id);
  return LockCachingAudioSource(
    Uri.parse(audio.url),
    headers: audio.headers,
    cacheFile: await _streamCacheFile(music),
    tag: tag,
  );
}
