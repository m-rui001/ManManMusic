import "dart:ui" as ui;
import "package:bobomusic/components/continuous_rounding.dart";
import "package:flutter/material.dart";

class MenuData {
  const MenuData({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class AppBottomBar extends StatelessWidget {
  const AppBottomBar({
    super.key,
    required this.currentIndex,
    this.page,
    required this.menus,
    required this.onItemTap,
  });

  final int currentIndex;
  final double? page;
  final List<MenuData> menus;
  final ValueChanged<int> onItemTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 11),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 1, 14, 5),
        child: Material(
          color: Colors.transparent,
          shape: const ContinuousRounding(40),
          clipBehavior: Clip.antiAlias,
          child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: ColoredBox(
                  color: colors.surfaceContainerHigh.withValues(alpha: .64),
                  child: SizedBox(
                    height: 58,
                    child: LayoutBuilder(builder: (context, constraints) {
                      const inset = 5.0;
                      final count = menus.length;
                      final slot = (constraints.maxWidth - inset * 2) / count;
                      final progress = (page ?? currentIndex.toDouble())
                          .clamp(0.0, (count - 1).toDouble());
                      return Stack(
                        children: [
                          Positioned(
                            left: inset + slot * progress,
                            top: inset,
                            bottom: inset,
                            width: slot,
                            child: DecoratedBox(
                              decoration: ShapeDecoration(
                                color: colors.onSurface.withValues(alpha: .10),
                                shape: const ContinuousRounding(27),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(inset),
                            child: Row(
                              children: [
                                for (var i = 0; i < count; i++)
                                  Expanded(
                                    child: _destination(
                                        context, menus[i], i, progress),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }),
                  ))),
        ),
      ),
    );
  }

  Widget _destination(
      BuildContext context, MenuData menu, int index, double progress) {
    final selected = index == currentIndex;
    final distance = (progress - index).abs().clamp(0.0, 1.0);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = (1 - distance).clamp(0.0, 1.0);
    final ink = Color.lerp(
        colors.onSurfaceVariant, colors.onSecondaryContainer, active)!;
    const shape = ContinuousRounding(27);
    final iconOffset = (progress - index).clamp(-1.0, 1.0) * 2.5 * active;
    return Semantics(
      button: true,
      selected: selected,
      label: menu.label,
      child: Tooltip(
        message: menu.label,
        excludeFromSemantics: true,
        preferBelow: false,
        child: InkWell(
          customBorder: shape,
          onTap: () => onItemTap(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Transform.translate(
                  offset: Offset(iconOffset, 0),
                  child: SizedBox.square(
                    dimension: 26,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.scale(
                          scale: .88 + .12 * (1 - active),
                          child: Icon(menu.icon,
                              color: ink.withValues(alpha: 1 - active),
                              size: 22),
                        ),
                        Transform.scale(
                          scale: .88 + .12 * active,
                          child: Icon(menu.activeIcon,
                              color: ink.withValues(alpha: active), size: 22),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
