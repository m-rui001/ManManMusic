import "package:flutter/material.dart";

class MenuData {
  final String label;
  final Icon icon;
  const MenuData({
    required this.label,
    required this.icon,
  });
}

class AppBottomBar extends StatelessWidget {
  final int currentIndex;
  final List<MenuData> menus;
  final ValueChanged<int>? onItemTap;

  const AppBottomBar({
    super.key,
    this.onItemTap,
    this.currentIndex = 0,
    required this.menus,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Material(
      color: Colors.white,
      elevation: 3,
      child: SafeArea(
        top: false,
        bottom: true,
        // 再留 4px，避免和全面屏手势条 / 三键导航贴在一起
        minimum: const EdgeInsets.only(bottom: 4),
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              for (var i = 0; i < menus.length; i++)
                Expanded(child: _buildItem(i, primaryColor)),
            ],
          ),
        ),
      ),
    );
  }

  /// 自己画每一项
  ///
  /// 以前用 BottomNavigationBar，它在固定高度里会自己再算一遍安全区，
  /// 结果整栏被顶到系统导航栏上，三个 tab 和返回键叠在一起。
  Widget _buildItem(int index, Color primaryColor) {
    final menu = menus[index];
    final selected = index == currentIndex;
    final color = selected ? primaryColor : const Color(0xFF9E9E9E);

    return InkWell(
      onTap: onItemTap == null ? null : () => onItemTap!(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(menu.icon.icon, size: 22, color: color),
          const SizedBox(height: 2),
          Text(
            menu.label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
