import "dart:async";

import "package:bobomusic/components/continuous_rounding.dart";
import "package:bobomusic/components/pressable.dart";
import "package:bobomusic/constants/motion.dart";
import "package:bobomusic/modules/party/party_control.dart";
import "package:bobomusic/modules/party/party_page.dart";
import "package:bobomusic/modules/player/artwork.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:bobomusic/utils/copy_track_name.dart";
import "package:bobomusic/utils/haptics.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:bobomusic/modules/player/player_card/card.dart";
import "package:bobomusic/modules/player/list.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:provider/provider.dart";

class PlayerView extends StatefulWidget {
  final bool cancelMargin;

  const PlayerView({super.key, this.cancelMargin = false});

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> with TickerProviderStateMixin {
  final GlobalKey _barKey = GlobalKey();
  AnimationController? _unfold;
  OverlayEntry? _preview;
  Rect? _source;
  int? _pointer;
  double _dragStartX = 0;
  double _dragStartY = 0;
  double _previousY = 0;
  double _dragDistance = 0;
  double _viewportHeight = 1;
  double _dragVelocity = 0;
  Duration _previousMoveAt = Duration.zero;
  bool _routeOpenedByDrag = false;

  @override
  void dispose() {
    _preview?.remove();
    _preview?.dispose();
    _unfold?.dispose();
    super.dispose();
  }

  void _onMiniPointerDown(PointerDownEvent event) {
    if (_pointer != null || _unfold != null) return;
    _pointer = event.pointer;
    _dragStartX = event.position.dx;
    _dragStartY = event.position.dy;
    _previousY = _dragStartY;
    _previousMoveAt = event.timeStamp;
    _viewportHeight = MediaQuery.sizeOf(context).height;
    _dragDistance = 0;
    _dragVelocity = 0;
    _routeOpenedByDrag = false;
  }

  void _onMiniPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final displacement = _dragStartY - event.position.dy;
    if (!_routeOpenedByDrag &&
        (displacement <= kTouchSlop ||
            displacement < (event.position.dx - _dragStartX).abs() * 1.1)) {
      return;
    }

    _dragDistance = displacement.clamp(0.0, _viewportHeight);
    final elapsed = event.timeStamp - _previousMoveAt;
    if (elapsed.inMicroseconds > 0) {
      _dragVelocity =
          (event.position.dy - _previousY) / elapsed.inMicroseconds * 1000000;
    }
    _previousY = event.position.dy;
    _previousMoveAt = event.timeStamp;

    if (!_routeOpenedByDrag) {
      _viewportHeight = MediaQuery.sizeOf(context).height;
      _unfold = AnimationController(
        vsync: Navigator.of(context),
        duration: AppMotion.unfold,
        reverseDuration: AppMotion.medium,
      );
      _routeOpenedByDrag = true;
      _source = _rectForKey(_barKey);
      final animation = _unfold!;
      _preview = OverlayEntry(
          builder: (_) => IgnorePointer(
                child: _UnfoldTransition(
                    animation: animation,
                    source: _source,
                    interactive: true,
                    child: PlayerCard(transitionController: animation)),
              ));
      Navigator.of(context).overlay!.insert(_preview!);
    }
    _unfold?.value = (_dragDistance / _viewportHeight).clamp(0.0, .94);
  }

  void _onMiniPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final controller = _unfold;
    if (controller != null) _dismissPreview(controller);
  }

  void _removePreview() {
    _preview?.remove();
    _preview?.dispose();
    _preview = null;
  }

  Future<void> _dismissPreview(AnimationController controller) async {
    try {
      await controller.reverse().orCancel;
    } on TickerCanceled {
      return;
    }
    _removePreview();
    _unfold = null;
    controller.dispose();
  }

  void _onMiniPointerEnd(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final controller = _unfold;
    if (controller == null) return;
    final recentMove = event.timeStamp - _previousMoveAt;
    final flick =
        recentMove <= const Duration(milliseconds: 100) && _dragVelocity < -850;
    if (_dragDistance > _viewportHeight * .16 || flick) {
      _removePreview();
      _unfold = null;
      if (showPlayerCard(context,
              controller: controller, sourceRect: _source) ==
          null) {
        controller.dispose();
      } else {
        controller.forward();
      }
    } else {
      _dismissPreview(controller);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final music = player.current;
    if (music == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 4, 14, widget.cancelMargin ? 6 : 34),
      // 往上拖迷你播放器（含进度细线）直接展开播放页，和点一下等价
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onMiniPointerDown,
        onPointerMove: _onMiniPointerMove,
        onPointerUp: _onMiniPointerEnd,
        onPointerCancel: _onMiniPointerCancel,
        child: Material(
          key: _barKey,
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
                      child: Pressable(
                        pressScale: .97,
                        child: InkWell(
                          onTap: () => showPlayerCard(context),
                          onLongPress: () => copyTrackName(music),
                          child: const PlayInfo(),
                        ),
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
                    // 胶囊底边只有中间一段是直的，缩进小于圆角会被裁掉两头
                    padding: const EdgeInsets.symmetric(horizontal: 34),
                    child: LinearProgressIndicator(
                      value: total > 0 ? (position / total).clamp(0.0, 1.0) : 0,
                      minHeight: 2,
                      borderRadius: BorderRadius.circular(1),
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
    final colors = Theme.of(context).colorScheme;

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
              color: colors.onSurface.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline,
                    size: 11, color: colors.onSurfaceVariant),
                const SizedBox(width: 3),
                Text(
                  "房主控制",
                  style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant),
                ),
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
                Text(clearHtmlTags(music.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
                if (music.author.isNotEmpty)
                  Text(clearHtmlTags(music.author),
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
          AppHaptics.action();
          if (player.isPlaying) {
            player.pause();
          } else {
            player.play();
          }
        }

        // 播放/暂停之间做一次缩放交叉淡化，图标不是「啪」地换掉
        Widget morph(IconData data) => AnimatedSwitcher(
              duration: AppMotion.fast,
              switchInCurve: AppMotion.standard,
              switchOutCurve: AppMotion.exit,
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: Tween(begin: .62, end: 1.0).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(data, key: ValueKey(data)),
            );

        if (prominent) {
          final colors = Theme.of(context).colorScheme;
          return Pressable(
            pressScale: .95,
            pressedColor: colors.onSurface.withValues(alpha: .08),
            pressedBorderRadius: BorderRadius.circular(38),
            child: IconButton.filled(
              tooltip: label,
              onPressed: toggle,
              style: IconButton.styleFrom(
                minimumSize: const Size(0, 68),
                shape: const ContinuousRounding(22),
                backgroundColor: colors.onSurface,
                foregroundColor: colors.surface,
              ),
              iconSize: 34,
              icon: morph(player.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded),
            ),
          );
        }
        if (flat) {
          final colors = Theme.of(context).colorScheme;
          return Pressable(
            pressScale: .9,
            pressedColor: (color ?? colors.onSurface).withValues(alpha: .15),
            child: IconButton.filledTonal(
              tooltip: label,
              onPressed: toggle,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(40),
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
                backgroundColor: colors.onSurface.withValues(alpha: .11),
                foregroundColor: color ?? colors.onSurface,
              ),
              iconSize: 23,
              icon: morph(player.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded),
            ),
          );
        }
        return Pressable(
          pressScale: .9,
          pressedColor: (color ?? Theme.of(context).colorScheme.onSurface)
              .withValues(alpha: .14),
          child: IconButton(
            tooltip: label,
            color: color ?? primaryColor,
            iconSize: size,
            padding: const EdgeInsets.only(bottom: 0),
            icon: morph(player.isPlaying
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled),
            onPressed: toggle,
          ),
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
    return Pressable(
      enabled: player.current != null,
      child: IconButton(
        tooltip: "上一首",
        color: color ?? Theme.of(context).primaryColor,
        iconSize: size,
        onPressed: player.current == null ? null : player.prev,
        icon: const Icon(Icons.skip_previous_rounded),
      ),
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
    return Pressable(
      enabled: canSkip,
      child: IconButton(
        tooltip: "下一首",
        color: color ?? Theme.of(context).primaryColor,
        iconSize: size,
        onPressed: canSkip ? player.next : null,
        icon: const Icon(Icons.skip_next_rounded),
      ),
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
        return Pressable(
          child: IconButton(
            color: color ?? primaryColor,
            iconSize: size,
            tooltip: "播放队列",
            onPressed: () {
              showPlayerList(context);
            },
            icon: const Icon(
              Icons.queue_music,
            ),
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
        return Pressable(
          child: IconButton(
            color: color ?? primaryColor,
            iconSize: size,
            tooltip: player.playerMode.name,
            onPressed: () {
              AppHaptics.selection();
              player.togglePlayerMode();
              BotToast.showText(text: "${player.playerMode.name}模式");
            },
            icon: Icon(
              player.playerMode.icon,
            ),
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
///
/// 迷你播放器和整页共享同一只动画控制器；上拉时它跟随手指展开，
/// 点按则从同一胶囊位置柔和过渡到全屏。
Future<void>? showPlayerCard(
  BuildContext context, {
  AnimationController? controller,
  Rect? sourceRect,
}) {
  final NavigatorState navigator = Navigator.of(context, rootNavigator: false);
  final player = Provider.of<PlayerModel>(context, listen: false);
  if (player.current == null) return null;
  final source = sourceRect ?? _barRect(context);
  final animation = controller ??
      AnimationController(
        vsync: navigator,
        duration: AppMotion.unfold,
        reverseDuration: AppMotion.medium,
      );
  AppHaptics.open();
  return navigator.push(_PlayerCardRoute(
    controller: animation,
    source: source,
    dragDriven: controller != null,
  ));
}

class _PlayerCardRoute extends PageRouteBuilder<void> {
  _PlayerCardRoute({
    required this.controller,
    required this.source,
    required this.dragDriven,
  }) : super(
          fullscreenDialog: true,
          opaque: false,
          pageBuilder: (_, __, ___) =>
              PlayerCard(transitionController: controller),
          transitionDuration: AppMotion.unfold,
          reverseTransitionDuration: AppMotion.medium,
          transitionsBuilder: (_, animation, __, child) => _UnfoldTransition(
            animation: animation,
            source: source,
            interactive: dragDriven,
            child: child,
          ),
        );

  @override
  final AnimationController controller;
  final Rect? source;
  final bool dragDriven;

  @override
  AnimationController createAnimationController() => controller;

  @override
  TickerFuture didPush() =>
      dragDriven ? TickerFuture.complete() : super.didPush();
}

/// 被点的迷你播放器的屏幕矩形
Rect? _rectForKey(GlobalKey key) {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

Rect? _barRect(BuildContext context) {
  RenderBox? box;
  context.visitAncestorElements((element) {
    if (element.widget is Material) {
      box = element.renderObject as RenderBox?;
      return false;
    }
    return true;
  });
  final target = box;
  if (target == null || !target.hasSize || !target.attached) return null;
  return target.localToGlobal(Offset.zero) & target.size;
}

class _UnfoldTransition extends StatelessWidget {
  final Animation<double> animation;
  final Rect? source;
  final bool interactive;
  final Widget child;

  const _UnfoldTransition({
    required this.animation,
    required this.source,
    required this.interactive,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Cirro keeps a narrow rim around its full-screen player instead of
    // flattening the corners against the device edge.
    final target = Rect.fromLTRB(
      8,
      5,
      size.width - 8,
      size.height - 8,
    );
    final from = source;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = interactive
            ? animation.value
            : AppMotion.emphasized.transform(animation.value);
        final rect = from == null ? target : Rect.lerp(from, target, t)!;
        final radius = 42 + (36 - 42) * t;
        // 内容晚一点浮现，先让容器长到位，避免小窗口里塞满字
        final opacity = from == null ? animation.value : t;
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black.withValues(alpha: .28 * t),
            ),
            Positioned.fromRect(
              rect: rect,
              child: ClipPath(
                clipBehavior: Clip.antiAlias,
                clipper: ShapeBorderClipper(
                  shape: ContinuousRounding(radius),
                ),
                child: Opacity(
                  opacity: opacity,
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    maxWidth: size.width,
                    maxHeight: size.height,
                    // 内容钉在屏幕原位，只有窗口在长大，字不会跟着跑
                    child: Transform.translate(
                      offset: -rect.topLeft,
                      child: SizedBox(
                        width: size.width,
                        height: size.height,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
