import "package:flutter/animation.dart";

/// 全 App 共用的动效节奏
///
/// 之前每个组件各写各的 duration / curve，同一个界面里能出现三种速度。
/// 这里只留四档，展开类动画一律走 emphasized，反馈类走 fast。
class AppMotion {
  static const fast = Duration(milliseconds: 120);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);
  static const unfold = Duration(milliseconds: 520);

  /// Material 3 emphasized decelerate：起步快、收尾长，卡片展开用这条
  static const emphasized = Cubic(0.05, 0.7, 0.1, 1.0);
  static const standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const exit = Cubic(0.3, 0.0, 0.8, 0.15);
}