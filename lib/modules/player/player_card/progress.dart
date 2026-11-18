import "dart:async";

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

class _PlayerProgressState extends State<PlayerProgress> {
  double? _dragValue;
  int _seekRequest = 0;

  void _seek(PlayerModel player, Duration duration, double value) {
    final request = ++_seekRequest;
    unawaited(() async {
      try {
        await player.seek(
            Duration(milliseconds: (duration.inMilliseconds * value).round()));
      } catch (_) {
        if (mounted) BotToast.showText(text: "跳转失败，请稍后再试");
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
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    trackShape: const TadpoleTrackShape(),
                    thumbShape: SliderComponentShape.noThumb,
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 17),
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
                  child: Slider(
                    value: value,
                    secondaryTrackValue: progress(buffer.data ?? Duration.zero),
                    semanticFormatterCallback: (v) =>
                        seconds2duration((v * duration.inSeconds).round()),
                    onChangeStart: locked || total <= 0
                        ? null
                        : (v) => setState(() => _dragValue = v),
                    onChanged: locked || total <= 0
                        ? null
                        : (v) => setState(() => _dragValue = v),
                    onChangeEnd: locked || total <= 0
                        ? null
                        : (v) => _seek(player, duration, v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 17),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(seconds2duration((value * total / 1000).floor())),
                      Text(seconds2duration(duration.inSeconds)),
                    ],
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
  const TadpoleTrackShape();

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
    final head = Offset(thumb, centerY);
    final active = isEnabled
        ? sliderTheme.activeTrackColor!
        : sliderTheme.disabledActiveTrackColor!;
    paint
      ..strokeWidth = rect.height
      ..color = isEnabled
          ? sliderTheme.inactiveTrackColor!
          : sliderTheme.disabledInactiveTrackColor!;
    canvas.drawLine(Offset(start, centerY), Offset(end, centerY), paint);
    if (secondaryOffset != null) {
      paint.color = isEnabled
          ? sliderTheme.secondaryActiveTrackColor!
          : sliderTheme.disabledSecondaryActiveTrackColor!;
      final buffered = secondaryOffset.dx.clamp(rect.left, rect.right);
      canvas.drawLine(Offset(start, centerY), Offset(buffered, centerY), paint);
    }

    paint.color = active;
    final length = (thumb - start).abs();
    const radius = 5.0;
    if (length > 0) {
      final sign = rtl ? -1 : 1;
      final shoulder = thumb - length.clamp(0.0, 50.0) * sign;
      canvas.drawLine(Offset(start, centerY), Offset(shoulder, centerY), paint);
      final tail = Path()
        ..moveTo(shoulder, centerY - rect.height / 2)
        ..cubicTo(thumb - 15 * sign, centerY - 1, thumb - 6 * sign,
            centerY - radius, thumb, centerY - radius)
        ..lineTo(thumb, centerY + radius)
        ..cubicTo(thumb - 6 * sign, centerY + radius, thumb - 15 * sign,
            centerY + 1, shoulder, centerY + rect.height / 2)
        ..close();
      if (length > radius * 2) canvas.drawPath(tail, paint);
    }
    canvas.drawCircle(head, radius, paint);
  }
}
