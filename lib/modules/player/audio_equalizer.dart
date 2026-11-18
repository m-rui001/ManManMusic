import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:just_audio/just_audio.dart";
import "package:shared_preferences/shared_preferences.dart";

enum AudioPreset {
  original("原声"),
  clear("清晰人声"),
  warm("柔和高频");

  const AudioPreset(this.label);
  final String label;
}

class AudioEqualizer {
  static const _channel = MethodChannel("manman/audio");
  static const _key = "audio_equalizer_preset";
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final AudioPlayer player;
  StreamSubscription<int?>? _sessions;
  AudioPreset preset = AudioPreset.original;

  AudioEqualizer(this.player);

  Future<void> init() async {
    if (!supported) return;
    final prefs = await SharedPreferences.getInstance();
    preset = AudioPreset.values.firstWhere(
      (value) => value.name == prefs.getString(_key),
      orElse: () => AudioPreset.original,
    );
    _sessions = player.androidAudioSessionIdStream.listen((session) {
      unawaited(_apply(preset, session));
    });
  }

  Future<bool> setPreset(AudioPreset value) async {
    if (!await _apply(value, player.androidAudioSessionId)) return false;
    preset = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.name);
    return true;
  }

  Future<bool> _apply(AudioPreset value, int? session) async {
    try {
      return await _channel.invokeMethod<bool>("equalizer", {
            "session": session,
            "preset": value.name,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  void dispose() {
    _sessions?.cancel();
    if (supported) unawaited(_apply(AudioPreset.original, null));
  }
}
