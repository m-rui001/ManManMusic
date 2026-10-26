import "dart:async";

import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/music_plaza/music_plaza.dart";
import "package:bobomusic/modules/player/player.dart";
import "package:bobomusic/modules/party/party_tab.dart";
import "package:bobomusic/modules/setting/setting.dart";
import "package:bobomusic/modules/tabbar/app_bottom_bar.dart";
import "package:flutter/material.dart";

/// 底部导航
///
/// 只留三个：首页 → 一起听 → 设置。
/// 歌单收进首页，作为首页里的一个分栏，和「历史播放」左右滑动切换。
class AppNavigation extends StatefulWidget {
  const AppNavigation({super.key});

  @override
  State<AppNavigation> createState() => AppNavigationState();
}

class AppNavigationState extends State<AppNavigation> {
  int _index = 0;
  final PageController _pageController = PageController();
  StreamSubscription? _switchSub;

  final List<MenuData> menus = const [
    MenuData(label: "首页", icon: Icon(Icons.home_outlined, size: 22)),
    MenuData(label: "一起听", icon: Icon(Icons.headphones_outlined, size: 22)),
    MenuData(label: "设置", icon: Icon(Icons.settings, size: 20)),
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
              SettingView(),
            ],
          ),
        ),
        // 迷你播放器放在导航栏正上方：
        // 以前它是 Scaffold 的 FAB，和三个 tab 叠在同一高度，
        // 想切 tab 或者收起播放页都得先上滑，很难点。
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: PlayerView(cancelMargin: true),
        ),
        AppBottomBar(
          currentIndex: _index,
          onItemTap: _onChangePage,
          menus: menus,
        )
      ],
    );
  }

  void _onChangePage(int index) {
    FocusScope.of(context).unfocus();
    _pageController.jumpToPage(index);
    setState(() {
      _index = index;
    });
  }
}
