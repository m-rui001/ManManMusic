import "dart:ui" show SemanticsFlag;

import "package:bobomusic/modules/tabbar/app_bottom_bar.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("底栏在页间拖动时连续移动图标并混合选中态", (tester) async {
    const menus = [
      MenuData(label: "主页", icon: Icons.home_outlined, activeIcon: Icons.home),
      MenuData(
        label: "一起听",
        icon: Icons.headphones_outlined,
        activeIcon: Icons.headphones,
      ),
      MenuData(
        label: "歌单",
        icon: Icons.library_music_outlined,
        activeIcon: Icons.library_music,
      ),
      MenuData(
        label: "设置",
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
      ),
    ];
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AppBottomBar(
              currentIndex: 0,
              page: .5,
              menus: menus,
              onItemTap: _ignoreTap,
            ),
          ),
        ),
      ),
    );

    final home = tester.getSemantics(find.bySemanticsLabel("主页"));
    final settings = tester.getSemantics(find.bySemanticsLabel("设置"));
    expect(home.hasFlag(SemanticsFlag.isSelected), isTrue);
    expect(settings.hasFlag(SemanticsFlag.isSelected), isFalse);

    final offsets = tester.widgetList<Transform>(find.byType(Transform)).where(
          (transform) => transform.transform.getTranslation().x != 0,
        );
    expect(offsets, hasLength(2));
    final xOffsets = offsets
        .map((transform) => transform.transform.getTranslation().x)
        .toList();
    expect(xOffsets, contains(.625));
    expect(xOffsets, contains(-.625));

    final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
    expect(icons[0].color!.a, closeTo(.5, .01));
    expect(icons[1].color!.a, closeTo(.5, .01));
    await tester.longPress(find.byTooltip("设置"));
    await tester.pumpAndSettle();
    expect(find.text("设置"), findsOneWidget);
  });
}

void _ignoreTap(int _) {}
