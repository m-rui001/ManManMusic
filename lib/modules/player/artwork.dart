import "package:bobomusic/components/continuous_rounding.dart";
import "package:bobomusic/constants/app_info.dart";
import "package:flutter/material.dart";

ImageProvider? musicArtwork(String cover) {
  final value = cover.trim();
  final uri = Uri.tryParse(value.startsWith("//") ? "https:$value" : value);
  if (uri == null || !uri.hasAuthority) return null;
  if (uri.scheme != "http" && uri.scheme != "https") return null;

  final secure = uri.replace(scheme: "https");
  return NetworkImage(
    secure.toString(),
    headers: secure.host.endsWith(".hdslb.com")
        ? const {"Referer": "https://www.bilibili.com/"}
        : null,
  );
}

class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    super.key,
    required this.cover,
    required this.size,
    this.radius = 12,
  });

  final String cover;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final image = musicArtwork(cover);
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
