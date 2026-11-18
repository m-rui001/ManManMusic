import "package:bobomusic/modules/player/audio_equalizer.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

Future<void> showAudioOptions(BuildContext context) async {
  final player = context.read<PlayerModel>();
  final equalizer = player.equalizer;
  final selected = await showModalBottomSheet<AudioPreset>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.graphic_eq_rounded),
              title: const Text("当前音轨"),
              subtitle: Text(player.sourceDescription.isEmpty
                  ? "还没有载入歌曲"
                  : player.sourceDescription),
            ),
            if (AudioEqualizer.supported && equalizer != null) ...[
              const Divider(height: 1),
              for (final preset in AudioPreset.values)
                ListTile(
                  title: Text(preset.label),
                  subtitle: Text(preset.description),
                  trailing: preset == equalizer.preset
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, preset),
                ),
            ],
          ],
        ),
      ),
    ),
  );
  if (selected == null || equalizer == null || !context.mounted) return;
  if (!await equalizer.setPreset(selected)) {
    BotToast.showText(text: "当前设备或音频输出无法应用这个音效");
  }
}
