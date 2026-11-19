import "dart:math" as math;
import "dart:ui" as ui;

import "package:bobomusic/modules/setting/playback_prefs.dart";
import "package:flutter/material.dart";

/// 播放页背景：封面缓慢流动的色块
///
/// Cirro 的背景不是「一张封面糊一下」，而是同一张封面取三份，
/// 各自以 120s / 70s / 90s 的周期旋转、缩放、偏移，叠成一张会呼吸的色网，
/// 再做饱和度处理、压暗、抖动去色带。这里用 CustomPainter 画同一件事：
/// 源图只有 72px，放大后本身就是软的，省掉一次全屏高斯模糊。
class ArtworkBackdrop extends StatefulWidget {
  final ImageProvider? provider;
  final Color surface;
  final Color tone;
  final Brightness brightness;

  const ArtworkBackdrop({
    super.key,
    required this.provider,
    required this.surface,
    required this.tone,
    required this.brightness,
  });

  @override
  State<ArtworkBackdrop> createState() => _ArtworkBackdropState();
}

class _ArtworkBackdropState extends State<ArtworkBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 120),
  );
  ui.Image? _mesh;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    PlaybackPrefs.instance.addListener(_onPrefs);
    _resolve();
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ArtworkBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) _resolve();
  }

  @override
  void dispose() {
    PlaybackPrefs.instance.removeListener(_onPrefs);
    _detach();
    _drift.dispose();
    super.dispose();
  }

  void _detach() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _listener = null;
    _stream = null;
    _mesh?.dispose();
    _mesh = null;
  }

  void _resolve() {
    _detach();
    final provider = widget.provider;
    if (provider == null) return;
    final stream =
        ResizeImage(provider, width: 72).resolve(createLocalImageConfiguration(context));
    _stream = stream;
    _listener = ImageStreamListener((info, _) {
      if (!mounted || !identical(stream, _stream)) {
        info.dispose();
        return;
      }
      setState(() {
        _mesh?.dispose();
        _mesh = info.image.clone();
      });
      info.dispose();
    }, onError: (_, __) {
      if (mounted && identical(stream, _stream)) _detach();
    });
    stream.addListener(_listener!);
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.brightness == Brightness.dark;
    final animate = PlaybackPrefs.instance.fluidBackground &&
        TickerMode.of(context) &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_drift.isAnimating) {
      _drift.repeat();
    } else if (!animate && _drift.isAnimating) {
      _drift.stop();
    }
    final mesh = _mesh;
    return ColoredBox(
      color: widget.surface,
      child: mesh == null
          ? const SizedBox.expand()
          : RepaintBoundary(
              child: AnimatedBuilder(
                animation: _drift,
                builder: (context, _) => ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.matrix(_saturation),
                    child: CustomPaint(
                      painter: _MeshPainter(mesh, _drift.value, dark),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// 先提饱和再压回来，中间留一点余量，颜色浓但不脏
const _saturation = <double>[
  1.32, -0.24, -0.08, 0, 0, //
  -0.16, 1.24, -0.08, 0, 0, //
  -0.16, -0.24, 1.40, 0, 0, //
  0, 0, 0, 1, 0, //
];

class _MeshPainter extends CustomPainter {
  final ui.Image image;
  final double phase;
  final bool dark;

  _MeshPainter(this.image, this.phase, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final side = math.max(size.width, size.height);
    // 三份副本：主份铺满，两份小的绕着它转，周期互质所以不会看出循环
    const copies = [
      (scale: 1.45, period: 1.0, dx: 0.0, dy: 0.0, parent: false),
      (scale: 0.78, period: 120 / 70, dx: -0.26, dy: 0.16, parent: false),
      (scale: 0.72, period: 120 / 90, dx: 0.34, dy: -0.22, parent: true),
    ];
    for (final copy in copies) {
      final angle = phase * 2 * math.pi * copy.period +
          (copy.parent ? phase * 2 * math.pi : 0);
      canvas.save();
      canvas.translate(
        size.width * (0.5 + copy.dx),
        size.height * (0.5 + copy.dy),
      );
      canvas.rotate(angle);
      final extent = side * copy.scale;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromCenter(
            center: Offset.zero, width: extent, height: extent),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MeshPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.image != image ||
      oldDelegate.dark != dark;
}

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