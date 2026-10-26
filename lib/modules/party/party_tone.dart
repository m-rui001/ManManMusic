import "dart:async";

import "package:flutter/services.dart";
import "package:just_audio/just_audio.dart";
import "package:shared_preferences/shared_preferences.dart";

/// 一起听进出的提示音
///
/// 单独用一个播放器、音量压得很低：和音乐混在一起，不打断播放，
/// 也不至于听不见。播放失败就退回系统点击音。
class PartyTone {
  PartyTone._();

  static final PartyTone instance = PartyTone._();

  static const String joinAsset = "assets/sounds/party_join.wav";
  static const String leaveAsset = "assets/sounds/party_leave.wav";

  AudioPlayer? _join;
  AudioPlayer? _leave;
  static const String _kEnabled = "manman_party_tone_enabled";

  Future<void>? _init;

  /// 开关（设置里可以关掉）
  bool enabled = true;

  /// 读取上次的设置
  Future<void> initFromStorage() async {
    final storage = await SharedPreferences.getInstance();
    enabled = storage.getBool(_kEnabled) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    final storage = await SharedPreferences.getInstance();
    await storage.setBool(_kEnabled, value);
  }

  Future<void> _ensure() {
    return _init ??= () async {
      try {
        _join = AudioPlayer();
        _leave = AudioPlayer();
        await _join!.setAsset(joinAsset);
        await _leave!.setAsset(leaveAsset);
        await _join!.setVolume(0.32);
        await _leave!.setVolume(0.24);
      } catch (_) {
        _join = null;
        _leave = null;
      }
    }();
  }

  Future<void> playJoin() => _play(join: true);

  Future<void> playLeave() => _play(join: false);

  Future<void> _play({required bool join}) async {
    if (!enabled) return;

    try {
      await _ensure();
      final player = join ? _join : _leave;
      if (player == null) throw Exception("no player");
      await player.seek(Duration.zero);
      await player.play();
    } catch (_) {
      SystemSound.play(SystemSoundType.click);
    }
  }
}
