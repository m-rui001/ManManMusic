import "dart:ui" as ui;

import "package:flutter/material.dart";

/// 封面下方的一次倒影
///
/// 越往下越糊、越淡，糊的程度用「清晰层 + 模糊层」按渐变交叉淡化得到，
/// 比整块统一模糊更像玻璃台面。
class ArtworkReflection extends StatelessWidget {
  final ImageProvider? provider;
  final double width;
  final double height;
  final Widget fallback;

  const ArtworkReflection({
    super.key,
    required this.provider,
    required this.width,
    required this.height,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final provider = this.provider;
    if (provider == null || height <= 0) return const SizedBox.shrink();
    Widget source(double sigma) => ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Image(
            image: ResizeImage(provider, width: 220),
            width: width,
            height: height,
            fit: BoxFit.cover,
            // 取封面底边做镜像，倒影的第一行才接得上封面最后一行
            alignment: Alignment.bottomCenter,
            errorBuilder: (_, __, ___) => fallback,
          ),
        );
    return SizedBox(
      width: width,
      height: height,
      child: ClipRect(
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.transparent],
            stops: [0, .82],
          ).createShader(bounds),
          child: Transform.flip(
            flipY: true,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.white],
                    stops: [.1, .62],
                  ).createShader(bounds),
                  child: source(13),
                ),
                ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.transparent],
                    stops: [0, .4],
                  ).createShader(bounds),
                  child: source(2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
