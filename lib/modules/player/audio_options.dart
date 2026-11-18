import "package:bobomusic/modules/player/audio_processing.dart";
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

class _AudioOptions extends StatelessWidget {
  const _AudioOptions();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final effects = player.activeAudioEffects;
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
            if (supportsAudioProcessing) ...[
              SwitchListTile(
                secondary: const Icon(Icons.auto_awesome_outlined),
                title: const Text("自动音效"),
                subtitle: const Text("在手机上检查缓存音轨，可同时应用适合的高频补偿、底噪减弱和耳机空间。"),
                value: player.automaticAudioProcessing,
                onChanged: (enabled) async {
                  try {
                    await player.setAutomaticAudioProcessing(enabled);
                  } catch (_) {
                    BotToast.showText(text: "暂时无法切换自动音效");
                  }
                },
              ),
              if (player.current != null)
                ListTile(
                  leading:
                      player.processingAudio && player.automaticAudioProcessing
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.multitrack_audio_rounded),
                  title: Text(effects.isEmpty ? "原轨" : "已应用音效"),
                  subtitle: Text(
                    effects.isNotEmpty
                        ? effects.map((effect) => effect.label).join(" · ")
                        : !player.automaticAudioProcessing
                            ? "自动音效已关闭"
                            : player.processingAudio
                                ? "正在检查和处理，播放会继续"
                                : player.audioProcessingStatus ?? "音轨缓存后自动检查",
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
