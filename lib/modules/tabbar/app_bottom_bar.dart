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
    required this.menus,
    required this.onItemTap,
  });

  final int currentIndex;
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
          color: colors.surfaceContainerHigh,
          shape: const ContinuousRounding(40),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 62,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Row(
                children: [
                  for (var i = 0; i < menus.length; i++)
                    Expanded(
                      child: _destination(context, menus[i], i),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _destination(BuildContext context, MenuData menu, int index) {
    final selected = index == currentIndex;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ink =
        selected ? colors.onSecondaryContainer : colors.onSurfaceVariant;
    final shape = ContinuousRounding(selected ? 27 : 18);
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        decoration: ShapeDecoration(
          color: selected ? colors.secondaryContainer : Colors.transparent,
          shape: shape,
        ),
        child: InkWell(
          customBorder: shape,
          onTap: () => onItemTap(index),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? menu.activeIcon : menu.icon,
                  color: ink, size: 22),
              const SizedBox(height: 3),
              Text(
                menu.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ink,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
