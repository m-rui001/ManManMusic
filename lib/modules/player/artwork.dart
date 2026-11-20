import "package:bobomusic/origin_sdk/bili/utils.dart";
import "package:bobomusic/components/continuous_rounding.dart";
import "package:bobomusic/constants/app_info.dart";
import "package:bobomusic/modules/music_order/track_metadata.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:flutter/material.dart";

NetworkImage? musicArtwork(String cover) {
  final url = firstBiliCover([cover]);
  if (url.isEmpty) return null;
  return NetworkImage(url,
      headers: Uri.parse(url).host.endsWith(".hdslb.com")
          ? const {"Referer": "https://www.bilibili.com/"}
          : null);
}

class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    super.key,
    required this.music,
    required this.size,
    this.radius = 12,
  });

  final MusicItem music;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final image = musicArtwork(music.cover);
    if (image != null) return _artwork(context, image);
    final lookup = restoreTrackMetadata(music);
    if (lookup == null) return _artwork(context, null);
    return FutureBuilder<TrackMetadata?>(
      key: ValueKey(music.id),
      future: lookup,
      builder: (context, snapshot) =>
          _artwork(context, musicArtwork(snapshot.data?.cover ?? "")),
    );
  }

  Widget _artwork(BuildContext context, ImageProvider? image) {
    final width = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final placeholder = Image.asset(
      appLogoAsset,
      fit: BoxFit.cover,
      cacheWidth: width,
    );
    return ClipPath(
      clipper: ShapeBorderClipper(shape: ContinuousRounding(radius)),
      child: SizedBox.square(
        dimension: size,
        child: image == null
            ? placeholder
            : Image(
                image: ResizeImage(image, width: width),
                fit: BoxFit.cover,
                frameBuilder: (_, child, frame, __) =>
                    frame == null ? placeholder : child,
                errorBuilder: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}
