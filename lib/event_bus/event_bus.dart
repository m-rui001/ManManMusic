import "package:event_bus/event_bus.dart";
import "package:flutter/material.dart";

// 创建事件总线实例
final EventBus eventBus = EventBus();

// 定义事件类
class RefreshMusicList {
  final String tabName;
  RefreshMusicList({required this.tabName});
}

class ClearMusicList {}
class ShowDeleteListDialog {
  final String tabName;
  ShowDeleteListDialog({required this.tabName});
}
class ScanLocalList {}
class ScanLocalListWithoutLoading {}
class ShowLocalAction {}
class RefreshTabList {}
class RefreshCollectionList {}
class RefreshPlayerCard {}
class ScrollLyric {}

class ThemeColorChanged {
  final Color newColor;

  ThemeColorChanged(this.newColor);
}

/// 切换底部导航页（0 首页 / 1 一起听 / 2 歌单 / 3 设置）
class SwitchTab {
  final int index;
  SwitchTab(this.index);
}

/// 历史播放有更新，首页可以据此刷新
class RefreshPlayHistory {}
