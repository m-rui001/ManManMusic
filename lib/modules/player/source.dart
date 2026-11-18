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

typedef PlaybackSource = ({AudioSource audio, String description});

Stream<PlaybackSource> musicSources(MusicItem music) async* {
  if (music.localPath.isNotEmpty) {
    yield (audio: AudioSource.file(music.localPath), description: "本地文件");
    return;
  }
  final tag = MediaItem(
    id: music.id,
    title: music.name,
    artUri: Uri.tryParse(music.cover),
  );
  final cached = await cachedMusicFile(music);
  if (cached != null) {
    final label = await _readCacheDescription(cached);
    yield (
      audio: AudioSource.file(cached.path, tag: tag),
      description: label.isEmpty ? "本机缓存" : "$label · 本机缓存",
    );
  }

  final primary = await service.getMusicUrl(music.id);
  for (final url in [primary, ...primary.alternatives]) {
    final uri = Uri.parse(url.url);
    final cacheFile = identical(url, primary) && cached == null
        ? await _streamCacheFile(music)
        : null;
    if (cacheFile != null) {
      await _saveCacheDescription(cacheFile, url.description);
    }
    final source = cacheFile != null
        ? LockCachingAudioSource(
            uri,
            headers: url.headers,
            cacheFile: cacheFile,
            tag: tag,
          )
        : AudioSource.uri(uri, headers: url.headers, tag: tag);
    yield (
      audio: source,
      description: url.description.isEmpty ? "在线音轨" : url.description,
    );
  }
}

Future<String> _readCacheDescription(File cache) async {
  try {
    return await File("${cache.path}.quality").readAsString();
  } on FileSystemException {
    return "";
  }
}

Future<void> _saveCacheDescription(File cache, String description) async {
  try {
    await cache.parent.create(recursive: true);
    await File("${cache.path}.quality").writeAsString(description);
  } on FileSystemException {
    // Playback continues with an unlabeled cache.
  }
}
