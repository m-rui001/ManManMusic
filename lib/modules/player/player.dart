import "dart:async";

import "package:bobomusic/modules/party/party_control.dart";
import "package:bobomusic/modules/party/party_page.dart";
import "package:bobomusic/modules/player/const.dart";
import "package:bobomusic/utils/color.dart";
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
    // Color primaryColor = Theme.of(context).primaryColor;
    return GestureDetector(
      onTap: () {
        showPlayerCard(context);
      },
      child: Container(
        height: 50,
        width: MediaQuery.of(context).size.width - 32,
        margin: EdgeInsets.only(bottom: cancelMargin ? 0 : 34),
        padding: const EdgeInsets.only(left: 15, right: 10),
        decoration: BoxDecoration(
          borderRadius: cancelMargin ? const BorderRadius.all(Radius.circular(4)) : const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
          color: ColorPallette.colorMix(context, 0.1),
        ),
        child: const Flex(
          direction: Axis.horizontal,
          children: [
            PlayInfo(),
            PartyLockBadge(),
            Row(children: [
              PlayButton(),
              NextButton(),
              PlayerListButton(),
            ]),
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

/// 音乐信息
class PlayInfo extends StatelessWidget {
  const PlayInfo({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerModel>(
      builder: (context, player, child) {
        String name = player.current?.name ?? "暂无歌曲";

        return Expanded(
          flex: 1,
          child: Text(
            name,
            style: TextStyle(
              fontSize: 16,
              overflow: TextOverflow.ellipsis,
              color: Theme.of(context).primaryColor,
            ),
          ),
        );
      },
    );
  }
}

/// 播放/暂停按钮
class PlayButton extends StatelessWidget {
  final double? size;
  final Color? color;

  const PlayButton({super.key, this.size = 40, this.color});

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).primaryColor;

    return Consumer<PlayerModel>(
      builder: (context, player, child) {
        return IconButton(
          color: color ?? primaryColor,
          iconSize: size,
          padding: const EdgeInsets.only(bottom: 0),
          icon: player.isPlaying
            ? const Icon(Icons.pause_circle_filled)
            : const Icon(Icons.play_circle_filled),
          onPressed: () {
            if (PartyControl.blocked()) return;
            if (player.isPlaying) {
              player.pause();
            } else {
              player.play();
            }
          },
        );
      },
    );
  }
}

/// 上一首
class PrevButton extends StatefulWidget {
  final double? size;
  final Color? color;

  const PrevButton({super.key, this.size = 30.0, this.color});

  @override
  PrevButtonState createState() => PrevButtonState();
}

class PrevButtonState extends State<PrevButton> {
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).primaryColor;

    return Consumer<PlayerModel>(
      builder: (context, player, child) {
        final disabled = (player.playerMode == PlayerMode.random || player.playerMode == PlayerMode.signalLoop || (player.current?.prev != null && player.current!.prev.isEmpty));

        return IconButton(
          color: widget.color ?? primaryColor,
          iconSize: widget.size,
          onPressed: () {
            if (PartyControl.blocked()) return;
            if (player.current == null) {
              BotToast.showText(text: "没有正在听的歌曲，无法播放下一曲");
              return;
            }

            if (player.playerMode == PlayerMode.signalLoop) {
              BotToast.showText(text: "单曲循环中，重新播放");
              player.prev();
              return;
            }

            if (disabled) {
              BotToast.showText(text: "网络歌曲不支持此操作，请先收藏到歌单或收藏合集或添加整个合集到待播放列表", duration: const Duration(seconds: 8));
              return;
            }

            player.prev();
          },
          icon: const Icon(Icons.skip_previous),
        );
      },
    );
  }
}

/// 下一首
class NextButton extends StatefulWidget {
  final double? size;
  final Color? color;

  const NextButton({super.key, this.size = 30.0, this.color});

  @override
  NextButtonState createState() => NextButtonState();
}

class NextButtonState extends State<NextButton> {
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).primaryColor;

    return Consumer<PlayerModel>(
      builder: (context, player, child) {
        final disabled = player.current?.next != null && player.current!.next.isEmpty;

        return IconButton(
          color: widget.color ?? primaryColor,
          iconSize: widget.size,
          onPressed: () {
            if (PartyControl.blocked()) return;
            if (player.current == null) {
              BotToast.showText(text: "没有正在听的歌曲，无法播放下一曲");
              return;
            }

            if (player.playerMode == PlayerMode.signalLoop) {
              BotToast.showText(text: "单曲循环中，重新播放");
              player.next();
              return;
            }

            if (disabled) {
              BotToast.showText(text: "网络歌曲不支持此操作，请先收藏到歌单或收藏合集或添加整个合集到待播放列表", duration: const Duration(seconds: 8));
              return;
            }

            player.next();
          },
          icon: const Icon(Icons.skip_next),
        );
      },
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
Future showPlayerList(BuildContext context) {
  final NavigatorState navigator = Navigator.of(context, rootNavigator: false);
  return navigator.push(ModalBottomSheetRoute(
    isScrollControlled: true,
    builder: (context) {
      return const PlayerList();
    },
  ));
}

/// 显示播放卡片
Future<void>? showPlayerCard(BuildContext context) {
  final NavigatorState navigator = Navigator.of(context, rootNavigator: false);
  final player = Provider.of<PlayerModel>(context, listen: false);
  if (player.current == null) return null;
  final screenSize = MediaQuery.of(context).size;
  final isLandscape = screenSize.width > screenSize.height;

  if (isLandscape) {
    return navigator.push(ModalBottomSheetRoute(
      isScrollControlled: true,
      // 自定义形状
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(0),
        ),
      ),
      // 设置背景颜色
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // 设置弹框的约束条件
      constraints: BoxConstraints(
        minWidth: MediaQuery.of(context).size.width,
        maxWidth: MediaQuery.of(context).size.width,
      ),
      builder: (context) {
        return const PlayerCard();
      },
    ));
  } else {
    return navigator.push(ModalBottomSheetRoute(
      isScrollControlled: true,
      builder: (context) {
        return const PlayerCard();
      },
    ));
  }
}
