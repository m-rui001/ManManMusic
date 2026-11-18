import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:bobomusic/modules/tabbar/app_navigation.dart";

/// 首页
///
/// 迷你播放器和底部三个 tab 都排进 AppNavigation 的纵向布局，
/// 不再用 FAB 浮在上面，避免两层控件挤在同一高度。
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: const Scaffold(body: AppNavigation()),
    );
  }
}
