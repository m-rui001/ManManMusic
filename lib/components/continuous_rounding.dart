import "dart:math" as math;

import "package:flutter/material.dart";

/// Straight sides blend into the corners through two cubic segments.
class ContinuousRounding extends OutlinedBorder {
  const ContinuousRounding(this.radius, {super.side});

  final double radius;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _outline(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _outline(rect.deflate(side.width));

  Path _outline(Rect rect) {
    if (rect.isEmpty) return Path();
    final x = math.min(radius, rect.width / 2);
    final y = math.min(radius, rect.height / 2);
    final path = Path()..moveTo(rect.left + x, rect.top);

    void corner(Offset start, Offset across, Offset down) {
      Offset at(double u, double v) => start + across * u + down * v;
      final first = at(.36, 0);
      final second = at(.56, 0);
      final middle = at(.78, .22);
      final fourth = at(1, .44);
      final fifth = at(1, .64);
      final end = at(1, 1);
      path.lineTo(start.dx, start.dy);
      path.cubicTo(
          first.dx, first.dy, second.dx, second.dy, middle.dx, middle.dy);
      path.cubicTo(fourth.dx, fourth.dy, fifth.dx, fifth.dy, end.dx, end.dy);
    }

    corner(rect.topRight - Offset(x, 0), Offset(x, 0), Offset(0, y));
    corner(rect.bottomRight - Offset(0, y), Offset(0, y), Offset(-x, 0));
    corner(rect.bottomLeft + Offset(x, 0), Offset(-x, 0), Offset(0, -y));
    corner(rect.topLeft + Offset(0, y), Offset(0, -y), Offset(x, 0));
    return path..close();
  }

  @override
  ContinuousRounding copyWith({BorderSide? side}) =>
      ContinuousRounding(radius, side: side ?? this.side);

  @override
  ContinuousRounding scale(double t) =>
      ContinuousRounding(radius * t, side: side.scale(t));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.solid) {
      canvas.drawPath(_outline(rect.deflate(side.width / 2)), side.toPaint());
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ContinuousRounding &&
      radius == other.radius &&
      side == other.side;

  @override
  int get hashCode => Object.hash(radius, side);
}
