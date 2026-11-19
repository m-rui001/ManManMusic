import "dart:math" as math;

import "package:flutter/material.dart";

/// 正在播放的三条跳动小柱
///
/// 静态图标只能说明「选中了这一行」，跳动的柱子才说明「正在响」。
/// 系统开了减少动态效果时退回静止高度。
class PlayingBars extends StatefulWidget {
  final bool playing;
  final Color color;
  final double size;

  const PlayingBars({
    super.key,
    required this.playing,
    required this.color,
    this.size = 16,
  });

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant PlayingBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    final animate = widget.playing &&
        TickerMode.of(context) &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_beat.isAnimating) {
      _beat.repeat();
    } else if (!animate && _beat.isAnimating) {
      _beat.stop();
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _beat,
        builder: (context, _) => CustomPaint(
          painter: _BarsPainter(
            phase: _beat.value,
            color: widget.color,
            playing: widget.playing,
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final double phase;
  final Color color;
  final bool playing;

  _BarsPainter({
    required this.phase,
    required this.color,
    required this.playing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const levels = [.42, .78, .55];
    const offsets = [0.0, .37, .71];
    final barWidth = size.width / 5;
    final gap = (size.width - barWidth * 3) / 2;
    for (var index = 0; index < 3; index++) {
      final wave = playing
          ? .5 + .5 * math.sin((phase + offsets[index]) * 2 * math.pi)
          : .5;
      final height = size.height * (.28 + .72 * wave * levels[index]);
      final left = index * (barWidth + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            left,
            size.height - height,
            barWidth,
            height,
          ),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.color != color ||
      oldDelegate.playing != playing;
}