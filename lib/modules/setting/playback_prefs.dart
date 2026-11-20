import "package:bobomusic/constants/cache_key.dart";
import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

/// 播放与界面偏好
///
/// 只放「用户能感知的行为开关」，播放状态本身仍在 BBPlayer 里。
/// 字幕自动匹配和触感反馈是默认体验，不做开关。
class PlaybackPrefs extends ChangeNotifier {
  PlaybackPrefs._();

  static final PlaybackPrefs instance = PlaybackPrefs._();

  /// 播放超过 3 秒时，「上一首」先回到本曲开头，再按一次才切上一首
  bool restartOnPrevious = true;

  Future<void> init() async {
    final storage = await SharedPreferences.getInstance();
    restartOnPrevious =
        storage.getBool(CacheKey.restartOnPrevious) ?? restartOnPrevious;
    notifyListeners();
  }

  Future<void> setRestartOnPrevious(bool value) async {
    restartOnPrevious = value;
    notifyListeners();
    final storage = await SharedPreferences.getInstance();
    await storage.setBool(CacheKey.restartOnPrevious, value);
  }
}
