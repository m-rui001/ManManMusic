import "package:bobomusic/modules/music_order/track_metadata.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:flutter/material.dart";

class CollectionSubtitle extends StatelessWidget {
  final MusicItem music;
  final String description;
  final TextStyle? style;
  final bool restoreLegacy;
  final bool showCollectionName;

  const CollectionSubtitle({
    super.key,
    required this.music,
    required this.description,
    required this.style,
    this.restoreLegacy = false,
    this.showCollectionName = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!showCollectionName) return _label("");
    final known = music.collectionName;
    final lookup = restoreLegacy && known.isEmpty
        ? restoreTrackMetadata(music, includeCollection: true)
        : null;
    if (lookup == null) return _label(known);
    return FutureBuilder<TrackMetadata?>(
      key: ValueKey(music.id),
      future: lookup,
      builder: (_, snapshot) => _label(snapshot.data?.collectionName ?? ""),
    );
  }

  Widget _label(String name) {
    final collection = clearHtmlTags(name).trim();
    final text =
        collection.isEmpty || collection == clearHtmlTags(music.name).trim()
            ? description
            : collection;
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(text,
        maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
  }
}
