import "dart:async";

import "package:bobomusic/components/continuous_rounding.dart";
import "package:bobomusic/modules/party/party_control.dart";
import "package:bobomusic/modules/party/party_page.dart";
import "package:bobomusic/modules/player/artwork.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:bobomusic/modules/player/player_card/card.dart";
import "package:bobomusic/modules/player/list.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:provider/provider.dart";

class PlayerView extends StatelessWidget {
  final bool cancelMargin;

  const PlayerView({super.key, this.cancelMargin = false});
  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final music = player.current;
    if (music == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 4, 14, cancelMargin ? 6 : 34),
      child: Material(
        color: colors.surfaceContainerHigh,
        shape: const ContinuousRounding(42),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => showPlayerCard(context),
                      child: const PlayInfo(),
                    ),
                  ),
                  const PartyLockBadge(),
                  PlayButton(size: 26, color: colors.onSurface, flat: true),
                  NextButton(size: 26, color: colors.onSurface),
                  const SizedBox(width: 7),
                ],
              ),
            ),
            StreamBuilder<Duration>(
              stream: player.positions,
              initialData: player.currentPosition,
              builder: (context, snapshot) {
                final total = player.duration?.inMilliseconds ?? 0;
                final position = snapshot.data?.inMilliseconds ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 27),
                  child: LinearProgressIndicator(
                    value: total > 0 ? (position / total).clamp(0.0, 1.0) : 0,
                    minHeight: 2,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(3)),
                    color: colors.primary,
                    backgroundColor:
                        colors.outlineVariant.withValues(alpha: .35),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 一起听「只能听」的小标记
///
/// 被房主锁住时，迷你播放器上会挂一个锁，点一下说明原因。
class PartyLockBadge extends StatelessWidget {
  const PartyLockBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final session = PartySession.instance;

    return StreamBuilder<void>(
      stream: session.changes,
      builder: (context, _) {
        if (!session.isLocked) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () => PartyControl.blocked(),
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 11, color: Colors.grey),
                SizedBox(width: 3),
                Text("房主控制", style: TextStyle(fontSize: 9, color: Colors.grey)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class PlayInfo extends StatelessWidget {
  const PlayInfo({super.key});

  @override
  Widget build(BuildContext context) {
    final music = context.watch<PlayerModel>().current;
    if (music == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: Row(
        children: [
          TrackArtwork(music: music, size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(music.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
                if (music.author.isNotEmpty)
                  Text(music.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 播放/暂停按钮
class PlayButton extends StatelessWidget {
  final double? size;
  final Color? color;
  final bool prominent;
  final bool flat;

  const PlayButton({
    super.key,
    this.size = 40,
    this.color,
    this.prominent = false,
    this.flat = false,
  });

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).primaryColor;

    return Consumer<PlayerModel>(
      builder: (context, player, child) {
        final label = player.isPlaying ? "暂停" : "播放";
        void toggle() {
          if (PartyControl.blocked()) return;
          if (player.isPlaying) {
            player.pause();
          } else {
            player.play();
          }
        }

        if (prominent) {
          final colors = Theme.of(context).colorScheme;
          return IconButton.filled(
            tooltip: label,
            onPressed: toggle,
            style: IconButton.styleFrom(
              minimumSize: const Size(0, 68),
              shape: const ContinuousRounding(28),
              backgroundColor: colors.onSurface,
              foregroundColor: colors.surface,
            ),
            iconSize: 34,
            icon: Icon(player.isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded),
          );
        }
        return IconButton(
          tooltip: label,
          color: color ?? primaryColor,
          iconSize: size,
          padding: const EdgeInsets.only(bottom: 0),
          icon: Icon(flat
              ? (player.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded)
              : (player.isPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled)),
          onPressed: toggle,
        );
      },
    );
  }
}

class PrevButton extends StatelessWidget {
  final double? size;
  final Color? color;
  const PrevButton({super.key, this.size = 30, this.color});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    return IconButton(
      tooltip: "上一首",
      color: color ?? Theme.of(context).primaryColor,
      iconSize: size,
      onPressed: player.current == null ? null : player.prev,
      icon: const Icon(Icons.skip_previous_rounded),
    );
  }
}

class NextButton extends StatelessWidget {
  final double? size;
  final Color? color;
  const NextButton({super.key, this.size = 30, this.color});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final music = player.current;
    final canSkip = music != null &&
        (music.orderName.isNotEmpty ||
            player.collectionQueue.isNotEmpty ||
            player.playerList.isNotEmpty);
    return IconButton(
      tooltip: "下一首",
      color: color ?? Theme.of(context).primaryColor,
      iconSize: size,
      onPressed: canSkip ? player.next : null,
      icon: const Icon(Icons.skip_next_rounded),
    );
  }
}

/// 待播放列表
class PlayerListButton extends StatelessWidget {
  final double? size;
  final Color? color;

  const PlayerListButton({super.key, this.size = 30.0, this.color});

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).primaryColor;

    return Consumer<PlayerModel>(
      builder: (context, player, child) {
        return IconButton(
          color: color ?? primaryColor,
          iconSize: size,
          tooltip: "播放队列",
          onPressed: () {
            showPlayerList(context);
          },
          icon: const Icon(
            Icons.queue_music,
          ),
        );
      },
    );
  }
}

/// 播放模式
class ModeButton extends StatelessWidget {
  final double? size;
  final Color? color;

  const ModeButton({super.key, this.size = 30.0, this.color});

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).primaryColor;

    return Consumer<PlayerModel>(
      builder: (context, player, child) {
        return IconButton(
          color: color ?? primaryColor,
          iconSize: size,
          tooltip: player.playerMode.name,
          onPressed: () {
            player.togglePlayerMode();
            BotToast.showText(text: "${player.playerMode.name}模式");
          },
          icon: Icon(
            player.playerMode.icon,
          ),
        );
      },
    );
  }
}

/// 显示待播放列表
Future<void> showPlayerList(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => const PlayerList(),
    );

/// 显示播放卡片
Future<void>? showPlayerCard(BuildContext context) {
  final NavigatorState navigator = Navigator.of(context, rootNavigator: false);
  final player = Provider.of<PlayerModel>(context, listen: false);
  if (player.current == null) return null;
  return navigator.push(PageRouteBuilder<void>(
    fullscreenDialog: true,
    pageBuilder: (_, __, ___) => const PlayerCard(),
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic))
          .animate(animation),
      child: child,
    ),
  ));
}
