import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:just_audio/just_audio.dart";
import "package:shared_preferences/shared_preferences.dart";

enum AudioPreviewMode {
  original("原轨", "播放未处理的音轨"),
  bandwidth("高频补偿", "轻度补偿明显截断的高频"),
  noise("底噪减弱", "轻度减弱稳定的嘶声，保留原有声道"),
  space("耳机空间", "拓宽立体声，单声道模拟少量早期反射");

  const AudioPreviewMode(this.label, this.description);
  final String label;
  final String description;
}

enum AudioPreset {
  original("原声", "使用音轨原有的动态和频响"),
  warm("柔和高频", "减弱刺耳的高频"),
  night("夜间均衡", "压低突出的响声，让小音量时更容易听清");

  const AudioPreset(this.label, this.description);
  final String label;
  final String description;
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
