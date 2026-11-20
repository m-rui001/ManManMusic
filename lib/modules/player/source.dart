import "dart:convert";
import "dart:io";

import "package:audio_service/audio_service.dart";
import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bobomusic/origin_sdk/bili/utils.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/origin_sdk/service.dart";
import "package:flutter_cache_manager/flutter_cache_manager.dart";
import "package:just_audio/just_audio.dart";
import "package:path/path.dart" as path;
import "package:path_provider/path_provider.dart";
import "package:uuid/uuid.dart";

final _legacyAudioCache = CacheManager(Config("bbmusicMediaCache"));
const _cacheLookupTimeout = Duration(seconds: 3);
const _uuid = Uuid();

String music2cacheKey(MusicItem music) => "${music.origin.value}-${music.id}";

typedef PlaybackSource = ({AudioSource audio, String description});

class AudioCandidate {
  final File? file;
  final MusicUrl? remote;
  final File? playbackCache;
  final String description;

  const AudioCandidate.local(File this.file, this.description)
      : remote = null,
        playbackCache = null;

  AudioCandidate.online(MusicUrl this.remote, this.playbackCache)
      : file = null,
        description = remote.description.isEmpty ? "在线音轨" : remote.description;
}

typedef _CachedTrack = ({
  File file,
  String description,
  String format,
  int bitrate,
  String? variant,
});

MediaItem music2mediaItem(MusicItem music) {
  final cover = firstBiliCover([music.cover]);
  final album = clearHtmlTags(music.collectionName).trim();
  return MediaItem(
    id: music.id.isEmpty ? music.localPath : music.id,
    title: clearHtmlTags(music.name).trim(),
    artist: clearHtmlTags(music.author).trim(),
    album: album.isEmpty ? null : album,
    duration: music.duration > 0 ? Duration(seconds: music.duration) : null,
    artUri: cover.isEmpty ? null : Uri.parse(cover),
  );
}

Stream<PlaybackSource> musicSources(MusicItem music) async* {
  final tag = music2mediaItem(music);
  await for (final candidate in musicAudioCandidates(music)) {
    final file = candidate.file;
    if (file != null) {
      yield (
        audio: AudioSource.file(file.path, tag: tag),
        description: candidate.description,
      );
      continue;
    }
    final remote = candidate.remote!;
    final uri = Uri.parse(remote.url);
    final cache = candidate.playbackCache;
    if (cache != null) {
      yield (
        audio: LockCachingAudioSource(
          uri,
          headers: remote.headers,
          cacheFile: cache,
          tag: tag,
        ),
        description: candidate.description,
      );
    }
    yield (
      audio: AudioSource.uri(uri, headers: remote.headers, tag: tag),
      description: candidate.description,
    );
  }
}

Stream<AudioCandidate> musicAudioCandidates(MusicItem music) async* {
  if (music.localPath.isNotEmpty) {
    yield AudioCandidate.local(File(music.localPath), "本地文件");
    return;
  }

  final auth = BiliAuth.instance;
  int accountId() => auth.isLogin ? auth.mid : 0;
  final account = accountId();
  final storage = await getTemporaryDirectory();
  final key = base64Url.encode(utf8.encode(music2cacheKey(music)));
  final directory = Directory(path.join(storage.path, "manman-streams", key));
  final cached = await _cachedTracks(music, directory, account);

  MusicUrl? primary;
  try {
    final request = service.getMusicUrl(music.id);
    primary =
        await (cached.isEmpty ? request : request.timeout(_cacheLookupTimeout));
  } catch (_) {
    if (cached.isEmpty) rethrow;
  }

  final yieldedFiles = <String>{};
  if (primary != null) {
    final candidates = [primary, ...primary.alternatives];
    for (final remote in candidates) {
      if (remote.requiresAccount && account != accountId()) continue;
      final variant = _cacheVariant(remote);
      for (final item in cached) {
        final matches = item.variant == variant ||
            (item.variant == null &&
                item.format == remote.format &&
                (item.bitrate / 1000).round() ==
                    (remote.bitrate / 1000).round());
        if (matches && yieldedFiles.add(item.file.path)) {
          yield AudioCandidate.local(item.file, item.description);
        }
      }
      if (remote.requiresAccount && account != accountId()) continue;
      final scope = remote.requiresAccount ? account : 0;
      final canCache = !remote.requiresAccount || scope > 0;
      // Separate temporary downloads so a failed CDN attempt cannot overwrite
      // a completed file or another in-flight download of the same rendition.
      final cache = canCache
          ? File(path.join(directory.path, "$scope.$variant.${_uuid.v4()}.m4a"))
          : null;
      yield AudioCandidate.online(remote, cache);
    }
  }
  for (final item in cached) {
    final restricted = item.format == "FLAC" || item.format == "杜比音轨";
    if (restricted &&
        (primary != null || item.variant == null || account != accountId())) {
      continue;
    }
    if (yieldedFiles.add(item.file.path)) {
      yield AudioCandidate.local(item.file, item.description);
    }
  }
}

String _cacheVariant(MusicUrl url) => base64Url.encode(utf8.encode(jsonEncode([
      url.format,
      url.bitrate,
      url.trackId,
      url.codec,
    ])));

Future<List<_CachedTrack>> _cachedTracks(
    MusicItem music, Directory directory, int account) async {
  final tracks = <_CachedTrack>[];
  try {
    if (await directory.exists()) {
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is! File) continue;
        final parts = path.basename(entry.path).split(".");
        if (parts.length != 4 || parts.last != "m4a") continue;
        final scope = int.tryParse(parts.first);
        if (scope == null || (scope != 0 && scope != account)) continue;
        try {
          final variant = parts[1];
          final metadata = jsonDecode(utf8.decode(base64Url.decode(variant)));
          if (metadata case [String format, int bitrate, int _, String _]) {
            final quality = MusicUrl(url: "", format: format, bitrate: bitrate);
            if (quality.requiresAccount != (scope != 0)) continue;
            if (await entry.length() == 0) continue;
            tracks.add((
              file: entry,
              format: format,
              bitrate: bitrate,
              variant: variant,
              description: _cachedDescription(quality.description),
            ));
          }
        } on FormatException {
          // Ignore files outside the rendition naming format.
        } on FileSystemException {
          // The OS can evict an individual cache file during listing.
        }
      }
    }
  } on FileSystemException {
    // Streaming still works if temporary storage is unavailable.
  }

  final old = File("${directory.path}.m4a");
  if (await old.exists()) {
    final label = await _readLegacyDescription(old);
    final parts = label.split(" · ");
    final bitrate = RegExp(r"^约 (\d+) kbps$").firstMatch(parts.last);
    tracks.add((
      file: old,
      format: parts.first,
      bitrate: (int.tryParse(bitrate?.group(1) ?? "") ?? 0) * 1000,
      variant: null,
      description: _cachedDescription(label),
    ));
  }
  if (tracks.isEmpty) {
    try {
      final previous =
          await _legacyAudioCache.getFileFromCache(music2cacheKey(music));
      final file = previous?.file;
      if (file != null && await file.exists()) {
        tracks.add((
          file: file,
          format: "",
          bitrate: 0,
          variant: null,
          description: _cachedDescription(""),
        ));
      }
    } catch (_) {
      // This cache was written by older releases and may be unavailable.
    }
  }

  int priority(String format) => switch (format) {
        "FLAC" => 0,
        "AAC" || "DASH" => 1,
        "杜比音轨" => 2,
        _ => 3,
      };
  tracks.sort((a, b) {
    final byFormat = priority(a.format).compareTo(priority(b.format));
    return byFormat == 0 ? b.bitrate.compareTo(a.bitrate) : byFormat;
  });
  return tracks;
}

String _cachedDescription(String label) =>
    label.isEmpty ? "本机缓存" : "$label · 本机缓存";

Future<String> _readLegacyDescription(File cache) async {
  try {
    return await File("${cache.path}.quality").readAsString();
  } on FileSystemException {
    return "";
  }
}
