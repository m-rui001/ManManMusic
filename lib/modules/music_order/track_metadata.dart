import "dart:async";

import "package:bobomusic/db/db.dart";
import "package:bobomusic/modules/history/play_history.dart";
import "package:bobomusic/origin_sdk/bili/utils.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/bili_link.dart";
import "package:bobomusic/utils/clear_html_tags.dart";

typedef TrackMetadata = ({String collectionName, String cover});

final _videoId = RegExp(r"^(\d+)_(BV[0-9A-Za-z]+)(?:_(\d+))?$");
final _partTitle = RegExp(
  r"^(第\s*[零〇一二三四五六七八九十百两\d]+\s*(乐章|樂章|部|首|集|章|幕|曲|段)|p\s*\d+\b|(?:movement|part|act|chapter)\s+[\divx]+\b|(?:[IVX]+|\d+)[.、．：:])",
  caseSensitive: false,
);
final _trackLookups = <String, Future<TrackMetadata?>>{};
final _videoLookups = <String, Future<BiliVideoDetail?>>{};
Future<void> _previousLookup = Future.value();

/// Old rows may have no collection name or artwork. Deduplicate the lookup by
/// video so scrolling through several parts can share a single request.
Future<TrackMetadata?>? restoreTrackMetadata(MusicItem music,
    {bool includeCollection = false}) {
  if (music.origin != OriginType.bili) return null;
  final match = _videoId.firstMatch(music.id);
  if (match == null) return null;
  final cid = match[3];
  final missingCover = firstBiliCover([music.cover]).isEmpty;
  final missingCollection = includeCollection &&
      music.collectionName.isEmpty &&
      (cid != null || _partTitle.hasMatch(clearHtmlTags(music.name).trim()));
  if (!missingCover && !missingCollection) return null;
  return _trackLookups.putIfAbsent(music.id, () async {
    final bvid = match[2]!;
    final detail = await _videoLookups.putIfAbsent(bvid, () {
      final next = _previousLookup.then((_) => fetchBiliVideoDetail(
            BiliLinkInfo(aid: match[1]!, bvid: bvid),
          ));
      _previousLookup = next.then((_) {});
      return next;
    });
    if (detail == null) return null;
    final collection = clearHtmlTags(cid != null && detail.pages.length > 1
            ? detail.title
            : detail.seasonTitle)
        .trim();
    final cover = detail.coverFor(cid);
    if (collection.isNotEmpty || cover.isNotEmpty) {
      unawaited(_persist(music.id, collection, cover));
    }
    return (collectionName: collection, cover: cover);
  });
}

Future<void> _persist(String id, String collection, String cover) async {
  try {
    await Future.wait([
      DBOrder()
          .fillFavoriteMetadata(id, collectionName: collection, cover: cover),
      PlayHistory.instance
          .fillMetadata(id, collectionName: collection, cover: cover),
    ]);
  } catch (_) {
    // The restored metadata is still available for this session.
  }
}
