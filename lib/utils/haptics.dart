import "package:flutter/services.dart";

/// 触感反馈
///
/// 收藏、播放/暂停、切歌、开面板这些「结果性」操作给一下震动，
/// 滚动和拖进度不给——否则手感会碎。
class AppHaptics {
  /// 选中 / 切 tab / 拖进度起点
  static void selection() => HapticFeedback.selectionClick();

  /// 播放、暂停、切歌、收藏
  static void action() => HapticFeedback.lightImpact();

  /// 打开操作面板、展开播放器
  static void open() => HapticFeedback.mediumImpact();

  /// 删除、移出歌单
  static void warning() => HapticFeedback.heavyImpact();
}
