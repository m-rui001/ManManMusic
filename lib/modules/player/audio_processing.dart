import "package:flutter/foundation.dart";

enum LocalAudioEffect {
  bandwidth("高频补偿"),
  noise("底噪减弱"),
  space("耳机空间");

  const LocalAudioEffect(this.label);
  final String label;
}

bool get supportsAudioProcessing =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
