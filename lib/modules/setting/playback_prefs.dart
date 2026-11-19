import "package:bobomusic/constants/cache_key.dart";
import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

/// 播放与界面偏好
///
/// 只放「用户能感知的行为开关」，播放状态本身仍在 BBPlayer 里。
/// 用 ChangeNotifier 是为了设置页改完，播放器立刻跟着变，不用重启。
class PlaybackPrefs extends ChangeNotifier {
  PlaybackPrefs._();

  static final PlaybackPrefs instance = PlaybackPrefs._();

  /// 播放超过 3 秒时，「上一首」先回到本曲开头，再按一次才切上一首
  bool restartOnPrevious = true;

  /// 切歌后自动去匹配歌词（静默，失败不打扰）
  bool autoLyrics = true;

  /// 播放页封面流动背景
  bool fluidBackground = true;

  /// 触感反馈
  bool haptics = true;

  Future<void> init() async {
    final storage = await SharedPreferences.getInstance();
    restartOnPrevious =
        storage.getBool(CacheKey.restartOnPrevious) ?? restartOnPrevious;
    autoLyrics = storage.getBool(CacheKey.autoLyrics) ?? autoLyrics;
    fluidBackground =
        storage.getBool(CacheKey.fluidBackground) ?? fluidBackground;
    haptics = storage.getBool(CacheKey.haptics) ?? haptics;
    notifyListeners();
  }

  Future<void> setRestartOnPrevious(bool value) =>
      _write(CacheKey.restartOnPrevious, value, () => restartOnPrevious = value);

  Future<void> setAutoLyrics(bool value) =>
      _write(CacheKey.autoLyrics, value, () => autoLyrics = value);

  Future<void> setFluidBackground(bool value) =>
      _write(CacheKey.fluidBackground, value, () => fluidBackground = value);

  Future<void> setHaptics(bool value) =>
      _write(CacheKey.haptics, value, () => haptics = value);

  Future<void> _write(String key, bool value, VoidCallback apply) async {
    apply();
    notifyListeners();
    final storage = await SharedPreferences.getInstance();
    await storage.setBool(key, value);
  }
}