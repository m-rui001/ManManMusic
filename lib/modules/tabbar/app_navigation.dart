import "dart:async";

import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/music_plaza/music_plaza.dart";
import "package:bobomusic/modules/music_order/music_order.dart";
import "package:bobomusic/modules/player/player.dart";
import "package:bobomusic/modules/party/party_tab.dart";
import "package:bobomusic/modules/setting/setting.dart";
import "package:bobomusic/modules/tabbar/app_bottom_bar.dart";
import "package:bobomusic/utils/haptics.dart";
import "package:flutter/material.dart";

class AppNavigation extends StatefulWidget {
  const AppNavigation({super.key});

  @override
  State<AppNavigation> createState() => AppNavigationState();
}

class AppNavigationState extends State<AppNavigation> {
  int _index = 0;
  final PageController _pageController = PageController();
  StreamSubscription? _switchSub;

  static const menus = [
    MenuData(
        label: "主页", icon: Icons.home_outlined, activeIcon: Icons.home_rounded),
    MenuData(
        label: "一起听",
        icon: Icons.headphones_outlined,
        activeIcon: Icons.headphones_rounded),
    MenuData(
        label: "歌单",
        icon: Icons.library_music_outlined,
        activeIcon: Icons.library_music_rounded),
    MenuData(
        label: "设置",
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings_rounded),
  ];

  @override
  void initState() {
    super.initState();
    // 任意位置都能请求切页（例如首页里点「去一起听」）
    _switchSub = eventBus.on<SwitchTab>().listen((event) {
      if (!mounted) return;
      _onChangePage(event.index);
    });
  }

  @override
  void dispose() {
    _switchSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: PageView(
            physics: const NeverScrollableScrollPhysics(),
            controller: _pageController,
            children: const [
              MusicPlazaView(),
              PartyTabView(),
              MusicOrderView(),
              SettingView(),
            ],
          ),
        ),
        const PlayerView(cancelMargin: true),
        AppBottomBar(
          currentIndex: _index,
          onItemTap: _onChangePage,
          menus: menus,
        )
      ],
    );
  }

  void _onChangePage(int index) {
    if (index == _index || index < 0 || index >= menus.length) return;
    AppHaptics.selection();
    FocusScope.of(context).unfocus();
    _pageController.jumpToPage(index);
    setState(() {
      _index = index;
    });
  }
}
