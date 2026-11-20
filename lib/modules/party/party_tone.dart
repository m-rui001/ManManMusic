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

  Future<void> _ensure() => _init ??= () async {
        final players = <AudioPlayer>[];
        try {
          // A cue must never steal focus or interrupt the music player.
          final join = AudioPlayer(
            handleInterruptions: false,
            handleAudioSessionActivation: false,
          );
          players.add(join);
          final leave = AudioPlayer(
            handleInterruptions: false,
            handleAudioSessionActivation: false,
          );
          players.add(leave);
          await join.setAsset(joinAsset);
          await leave.setAsset(leaveAsset);
          await join.setVolume(0.32);
          await leave.setVolume(0.24);
          _join = join;
          _leave = leave;
        } catch (_) {
          // A transient decoder/channel failure should not permanently disable
          // all later arrival sounds.
          _init = null;
          _join = null;
          _leave = null;
          for (final player in players) {
            await player.dispose();
          }
          rethrow;
        }
      }();

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
