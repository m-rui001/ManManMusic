import "package:bobomusic/modules/player/model.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

Future<void> showAudioOptions(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const _AudioDetails(),
    );

class _AudioDetails extends StatelessWidget {
  const _AudioDetails();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final description = player.sourceDescription;
    return SafeArea(
      top: false,
      child: ListTile(
        leading: const Icon(Icons.graphic_eq_rounded),
        title: const Text("当前音轨"),
        subtitle: Text(description.isEmpty ? "还没有载入歌曲" : description),
      ),
    );
  }
}
