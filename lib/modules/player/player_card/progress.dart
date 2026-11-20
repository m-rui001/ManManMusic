import "dart:async";
import "dart:math" as math;

import "package:bobomusic/modules/party/party_page.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class PlayerProgress extends StatefulWidget {
  final Color color;

  const PlayerProgress({super.key, required this.color});

  @override
  State<PlayerProgress> createState() => _PlayerProgressState();
}

class _PlayerProgressState extends State<PlayerProgress>
    with SingleTickerProviderStateMixin {
  late final _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  double? _dragValue;
  int _seekRequest = 0;

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  void _seek(PlayerModel player, Duration duration, double value) {
    final request = ++_seekRequest;
    unawaited(() async {
      try {
        await player.seek(
            Duration(milliseconds: (duration.inMilliseconds * value).round()));
      } catch (_) {
        if (mounted && request == _seekRequest) {
          BotToast.showText(text: "跳转失败，请稍后再试");
        }
      } finally {
        if (mounted && request == _seekRequest) {
          setState(() => _dragValue = null);
        }
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final animate = player.isPlaying &&
        TickerMode.of(context) &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_wave.isAnimating) {
      _wave.repeat();
    } else if (!animate && _wave.isAnimating) {
      _wave.stop();
    }
    return StreamBuilder<void>(
      stream: PartySession.instance.changes,
      builder: (context, _) => StreamBuilder<Duration>(
        stream: player.positions,
        initialData: player.currentPosition,
        builder: (context, snapshot) {
          final duration = player.duration ?? Duration.zero;
          final total = duration.inMilliseconds;
          final position = snapshot.data ?? Duration.zero;
          double progress(Duration value) =>
              total <= 0 ? 0 : (value.inMilliseconds / total).clamp(0.0, 1.0);
          final value = _dragValue ?? progress(position);
          final locked = PartySession.instance.isLocked;
          return StreamBuilder<Duration>(
            stream: player.bufferedPositions,
            initialData: player.bufferedPosition,
            builder: (context, buffer) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _wave,
                    builder: (context, slider) => SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.8,
                        trackShape: TadpoleTrackShape(
                          phase: _wave.value * 2 * math.pi,
                          amplitude: animate && _dragValue == null ? 2.35 : 0,
                        ),
                        thumbShape: SliderComponentShape.noThumb,
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 11),
                        activeTrackColor: widget.color,
                        inactiveTrackColor: widget.color.withValues(alpha: .18),
                        secondaryActiveTrackColor:
                            widget.color.withValues(alpha: .34),
                        disabledActiveTrackColor:
                            widget.color.withValues(alpha: .55),
                        disabledInactiveTrackColor:
                            widget.color.withValues(alpha: .14),
                        disabledSecondaryActiveTrackColor:
                            widget.color.withValues(alpha: .24),
                        overlayColor: widget.color.withValues(alpha: .12),
                      ),
                      child: slider!,
                    ),
                    child: Slider(
                      value: value,
                      secondaryTrackValue:
                          progress(buffer.data ?? Duration.zero),
                      semanticFormatterCallback: (v) =>
                          "播放进度 ${seconds2duration((v * total / 1000).floor())} / ${seconds2duration(duration.inSeconds)}",
                      onChangeStart: locked || total <= 0
                          ? null
                          : (v) {
                              ++_seekRequest;
                              setState(() => _dragValue = v);
                            },
                      onChanged: locked || total <= 0
                          ? null
                          : (v) => setState(() => _dragValue = v),
                      onChangeEnd: locked || total <= 0
                          ? null
                          : (v) => _seek(player, duration, v),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: widget.color.withValues(alpha: .70),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(seconds2duration((value * total / 1000).floor())),
                        Text(seconds2duration(duration.inSeconds)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A tapered active track and rounded head, using Flutter's normal Slider gestures.
class TadpoleTrackShape extends RoundedRectSliderTrackShape {
  const TadpoleTrackShape({this.phase = 0, this.amplitude = 0});

  final double phase;
  final double amplitude;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.isEmpty) return;
    final canvas = context.canvas;
    final paint = Paint()..strokeCap = StrokeCap.round;
    final centerY = rect.center.dy;
    final rtl = textDirection == TextDirection.rtl;
    final start = rtl ? rect.right : rect.left;
    final end = rtl ? rect.left : rect.right;
    final thumb = thumbCenter.dx.clamp(rect.left, rect.right);
    final sign = rtl ? -1.0 : 1.0;
    final active = isEnabled
        ? sliderTheme.activeTrackColor!
        : sliderTheme.disabledActiveTrackColor!;
    paint
      ..strokeWidth = rect.height
      ..color = isEnabled
          ? sliderTheme.inactiveTrackColor!
          : sliderTheme.disabledInactiveTrackColor!;
    final remaining = (end - thumb).abs();
    final tailStart = thumb + remaining.clamp(0.0, 7.0) * sign;
    if (remaining > 7) {
      canvas.drawLine(Offset(tailStart, centerY), Offset(end, centerY), paint);
    }
    if (secondaryOffset != null) {
      paint.color = isEnabled
          ? sliderTheme.secondaryActiveTrackColor!
          : sliderTheme.disabledSecondaryActiveTrackColor!;
      final buffered = secondaryOffset.dx.clamp(rect.left, rect.right);
      if ((buffered - tailStart) * sign > 0) {
        canvas.drawLine(
            Offset(tailStart, centerY), Offset(buffered, centerY), paint);
      }
    }

    paint.color = active;
    final length = (thumb - start).abs();
    if (length > 0) {
      final shoulder = thumb - length.clamp(0.0, 14.0) * sign;
      final waveLength = (shoulder - start).abs();
      if (amplitude == 0 || waveLength < 12 || !isEnabled) {
        canvas.drawLine(
            Offset(start, centerY), Offset(shoulder, centerY), paint);
      } else {
        final path = Path()..moveTo(start, centerY);
        for (var x = 3.0; x < waveLength; x += 3) {
          final edge = math.min(x, waveLength - x) / 15;
          final y = amplitude *
              edge.clamp(0.0, 1.0) *
              math.sin(x * math.pi / 17 - phase);
          path.lineTo(start + x * sign, centerY + y);
        }
        path.lineTo(shoulder, centerY);
        paint
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(path, paint);
        paint.style = PaintingStyle.fill;
      }
      canvas.drawLine(Offset(shoulder, centerY), Offset(thumb, centerY), paint);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(thumb, centerY), width: 3.4, height: 21),
        const Radius.circular(2),
      ),
      paint,
    );
  }
}
