import "package:bobomusic/modules/player/audio_equalizer.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

Future<void> showAudioOptions(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const _AudioOptions(),
    );

class _AudioOptions extends StatefulWidget {
  const _AudioOptions();

  @override
  State<_AudioOptions> createState() => _AudioOptionsState();
}

class _AudioOptionsState extends State<_AudioOptions> {
  String? _repairMessage;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final equalizer = player.equalizer;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
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
            if (AudioEqualizer.supported)
              SwitchListTile(
                secondary: const Icon(Icons.auto_awesome_outlined),
                title: const Text("自动高频补偿"),
                subtitle: const Text("在本机检测已缓存音轨，只补偿明显缺失的高频。"),
                value: player.automaticAudioRepair,
                onChanged: (enabled) async {
                  try {
                    final message =
                        await player.setAutomaticAudioRepair(enabled);
                    if (mounted) setState(() => _repairMessage = message);
                  } catch (_) {
                    if (mounted) setState(() => _repairMessage = "设置保存失败");
                  }
                },
              ),
            if (AudioEqualizer.supported && player.current != null) ...[
              const Divider(height: 1),
              ListTile(
                leading: player.repairingAudio
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.multitrack_audio_rounded),
                title: const Text("当前曲目试听"),
                subtitle: Text(player.repairingAudio
                    ? "正在本机处理，当前播放会继续"
                    : _repairMessage ?? "选择一种处理效果，切换时保留播放位置"),
              ),
              for (final mode in AudioPreviewMode.values)
                ListTile(
                  contentPadding: const EdgeInsetsDirectional.only(
                    start: 56,
                    end: 16,
                  ),
                  title: Text(mode.label),
                  subtitle: Text(mode.description),
                  selected: mode == player.audioPreviewMode,
                  trailing: mode == player.audioPreviewMode
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: player.repairingAudio || player.isLoading
                      ? null
                      : () async {
                          setState(() => _repairMessage = null);
                          final message = await player.setAudioRepair(mode);
                          if (mounted) setState(() => _repairMessage = message);
                        },
                ),
            ],
            if (AudioEqualizer.supported && equalizer != null) ...[
              const Divider(height: 1),
              for (final preset in AudioPreset.values)
                ListTile(
                  title: Text(preset.label),
                  subtitle: Text(preset.description),
                  trailing: preset == equalizer.preset
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () async {
                    if (!await equalizer.setPreset(preset)) {
                      BotToast.showText(text: "当前设备或音频输出无法应用这个音效");
                    } else if (mounted) {
                      setState(() {});
                    }
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}
