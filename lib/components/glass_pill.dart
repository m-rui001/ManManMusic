import "dart:ui" as ui;

import "package:flutter/material.dart";

class GlassPill extends StatelessWidget {
  const GlassPill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipPath(
      clipper: const ShapeBorderClipper(shape: StadiumBorder()),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Material(
          type: MaterialType.transparency,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(
                shape: StadiumBorder(
              side: BorderSide(color: colors.onSurface.withValues(alpha: .10)),
            )),
            child: Ink(
              decoration: ShapeDecoration(
                shape: const StadiumBorder(),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colors.surfaceContainerHighest.withValues(alpha: .82),
                    colors.surfaceContainerHigh.withValues(alpha: .56),
                  ],
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
