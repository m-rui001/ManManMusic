// ignore_for_file: use_build_context_synchronously, avoid_print, deprecated_member_use

import "dart:async";
import "dart:math" as math;
import "dart:ui" as ui;

import "package:bobomusic/components/continuous_rounding.dart";
import "package:bobomusic/components/pressable.dart";
import "package:bobomusic/components/sheet/bottom_sheet.dart";
import "package:bobomusic/modules/bili_account/fav_sync.dart";
import "package:bobomusic/modules/party/party_page.dart";
import "package:bobomusic/constants/covers.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/download/model.dart";
import "package:bobomusic/modules/music_order/track_metadata.dart";
import "package:bobomusic/modules/player/artwork.dart";
import "package:bobomusic/modules/player/audio_options.dart";
import "package:bobomusic/modules/player/lyrics_card/lyric_scroller.dart";
import "package:bobomusic/modules/player/player_card/progress.dart";
import "package:bobomusic/modules/player/player_card/vinyl_record.dart";
import "package:bobomusic/modules/player/utils.dart";
import "package:bobomusic/modules/share/share_sheet.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/check_music_local_repeat.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:bobomusic/utils/copy_track_name.dart";
import "package:bobomusic/utils/haptics.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:bobomusic/modules/player/player.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:provider/provider.dart";
import "package:url_launcher/url_launcher.dart";
import "package:uuid/uuid.dart";

const uuid = Uuid();

class PlayerCard extends StatefulWidget {
  const PlayerCard({super.key, this.transitionController});

  final AnimationController? transitionController;

  @override
  State<PlayerCard> createState() => PlayerCardState();
}

class PlayerCardState extends State<PlayerCard> {
  bool isLike = false;
  String errorCoverUrl = Covers.getLocalCover();
  ImageProvider? _imageProvider;
  ImageStream? _imageStream;
  ImageInfo? _imageInfo;
  ImageStreamListener? _imageListener;
  MusicItem? _artworkTrack;
  bool _vinyl = false;
  bool _lyrics = false;
  bool _savingLike = false;
  int _favoriteRead = 0;
  static const _fallbackTone = Color(0xFF81ADA1);
  Color _artTone = _fallbackTone;
  final List<StreamSubscription?> _subscriptions = [];

  static Widget _noDither(BuildContext _, Object __, StackTrace? ___) =>
      const SizedBox.shrink();

  @override
  void initState() {
    super.initState();
    _subscriptions.add(eventBus.on<RefreshPlayerCard>().listen((event) {
      _initCover();
      _initState();
    }));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = context.watch<PlayerModel>().current;
    if (identical(current, _artworkTrack)) return;
    // Clear the old image before painting the new track's title.
    _initCover();
    _initState();
  }

  Future<void> _initState() async {
    if (!mounted) return;
    final current = context.read<PlayerModel>().current;
    if (current == null) return;

    final request = ++_favoriteRead;
    try {
      final liked = await FavSyncService.isInMyMusic(current.id);
      if (mounted &&
          request == _favoriteRead &&
          identical(current, context.read<PlayerModel>().current)) {
        setState(() => isLike = liked);
      }
    } catch (_) {
      // A tap retries the lookup before changing the library.
    }
  }

  Future<void> _initCover() async {
    if (!mounted) return;
    final current = context.read<PlayerModel>().current;
    if (identical(current, _artworkTrack)) return;
    _artworkTrack = current;
    isLike = false;
    final image = current == null ? null : musicArtwork(current.cover);
    _loadImage(image);
    if (image != null || current == null) return;
    final lookup = restoreTrackMetadata(current);
    if (lookup == null) return;
    final restored = musicArtwork((await lookup)?.cover ?? "");
    if (restored != null && mounted && identical(current, _artworkTrack)) {
      _loadImage(restored);
    }
  }

  void _removeImageListener() {
    final listener = _imageListener;
    if (listener != null) _imageStream?.removeListener(listener);
    _imageListener = null;
    _imageStream = null;
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub?.cancel();
    }
    _removeImageListener();
    _imageInfo?.dispose();
    super.dispose();
  }

  void _loadImage(ImageProvider? provider) {
    _removeImageListener();
    setState(() {
      _imageInfo?.dispose();
      _imageInfo = null;
      _imageProvider = provider;
      _artTone = _fallbackTone;
    });
    if (provider == null) return;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    _imageStream = stream;
    _imageListener = ImageStreamListener((info, _) {
      if (!mounted || !identical(_imageStream, stream)) {
        info.dispose();
        return;
      }
      setState(() {
        _imageInfo?.dispose();
        _imageInfo = info;
      });
      unawaited(_updateArtworkTone(info.image, stream));
    }, onError: (_, __) {
      if (mounted && identical(stream, _imageStream)) {
        _removeImageListener();
        setState(() => _imageProvider = null);
      }
    });
    stream.addListener(_imageListener!);
  }

  Future<void> _updateArtworkTone(ui.Image image, ImageStream stream) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      const Rect.fromLTWH(0, 0, 16, 16),
      Paint()..filterQuality = FilterQuality.low,
    );
    final picture = recorder.endRecording();
    ui.Image? preview;
    try {
      preview = await picture.toImage(16, 16);
      final pixels = await preview.toByteData();
      if (!mounted || !identical(stream, _imageStream) || pixels == null) {
        return;
      }
      var red = 0.0;
      var green = 0.0;
      var blue = 0.0;
      var total = 0.0;
      for (var index = 0; index < pixels.lengthInBytes; index += 4) {
        if (pixels.getUint8(index + 3) < 128) continue;
        final r = pixels.getUint8(index);
        final g = pixels.getUint8(index + 1);
        final b = pixels.getUint8(index + 2);
        final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));
        if (hsl.lightness < .09 || hsl.lightness > .94) continue;
        final weight = .12 + hsl.saturation * hsl.saturation;
        red += r * weight;
        green += g * weight;
        blue += b * weight;
        total += weight;
      }
      if (total < 3) return;
      final average = HSLColor.fromColor(Color.fromARGB(
        255,
        (red / total).round(),
        (green / total).round(),
        (blue / total).round(),
      ));
      setState(() => _artTone = average
          .withLightness(.62)
          .withSaturation(average.saturation < .08 ? .035 : .43)
          .toColor());
    } catch (_) {
      // Preview decode can fail independently of the artwork widget.
    } finally {
      preview?.dispose();
      picture.dispose();
    }
  }

  void _toggleStage() {
    AppHaptics.selection();
    setState(() => _lyrics = !_lyrics);
  }

  void _showSleepTimer() {
    final player = context.read<PlayerModel>();
    final deadline = player.sleepDeadline;
    final time = deadline == null
        ? null
        : TimeOfDay.fromDateTime(deadline).format(context);
    openBottomSheet(
        context,
        [
          for (final minutes in [15, 30, 60])
            SheetItem(
                title: "$minutes 分钟后",
                icon: Icons.timer_outlined,
                onPressed: () {
                  player.autoCloseHandler(Duration(minutes: minutes));
                  BotToast.showText(text: "已设置 $minutes 分钟定时暂停");
                }),
          SheetItem(
              title: "到时播完本首再暂停",
              icon: player.playDoneAutoClose
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
              onPressed: player.waitingForTrackEnd
                  ? null
                  : player.togglePlayDoneAutoClose),
          if (time != null || player.waitingForTrackEnd)
            SheetItem(
                title: "取消定时",
                icon: Icons.timer_off_outlined,
                onPressed: player.cancelSleepTimer),
        ],
        header: SheetHeader(
            title: "定时暂停",
            subtitle: player.waitingForTrackEnd
                ? "将在本首结束时暂停"
                : time == null
                    ? null
                    : "定时到期时间 $time"));
  }

  Widget _moreActions(MusicItem music) {
    return Pressable(
      child: IconButton(
        tooltip: "更多播放选项",
        icon: const Icon(Icons.more_horiz_rounded),
        onPressed: () => openBottomSheet(
          context,
          [
            SheetItem(
                title: "定时暂停",
                icon: Icons.bedtime_outlined,
                onPressed: _showSleepTimer),
            if (music.localPath.isEmpty)
              SheetItem(
                title: "下载",
                subtitle: "存到本地，没网也能听",
                icon: Icons.download_rounded,
                onPressed: () {
                  checkMusicLocalRepeat(context, music, () {
                    context.read<DownloadModel>().download([music]);
                  });
                },
              ),
            if (music.id.contains("BV"))
              SheetItem(
                title: "打开哔哩哔哩",
                subtitle: "去看这条视频",
                icon: Icons.smart_display_outlined,
                onPressed: () {
                  final bv = RegExp(r"BV[0-9A-Za-z]+").firstMatch(music.id);
                  if (bv != null) _launchBilibiliVideo(bv.group(0)!);
                },
              ),
            SheetItem(
              title: "分享",
              icon: Icons.ios_share_rounded,
              onPressed: () => showShareSheet(context),
            ),
            SheetItem(
              title: _vinyl ? "方形封面" : "黑胶封面",
              icon: _vinyl ? Icons.crop_square_rounded : Icons.album_outlined,
              onPressed: () => setState(() => _vinyl = !_vinyl),
            ),
          ],
          header: SheetHeader(
            title: clearHtmlTags(music.name),
            subtitle: clearHtmlTags(music.author),
            track: music,
          ),
        ),
      ),
    );
  }

  Widget _buildStage(PlayerModel player, MusicItem music, double safeTop) {
    final stage = _lyrics
        ? LyricsScroller(key: ValueKey(music.id))
        : LayoutBuilder(builder: (context, constraints) {
            final side = math.min(constraints.maxWidth, constraints.maxHeight);
            if (side <= 0) return const SizedBox.shrink();
            final cover = Semantics(
              button: true,
              label: "查看歌词",
              container: true,
              child: GestureDetector(
                onTap: _toggleStage,
                child: SizedBox.square(
                    dimension: side, child: _buildArtwork(player, side)),
              ),
            );
            final animation = widget.transitionController;
            if (animation == null) return Center(child: cover);
            return AnimatedBuilder(
              animation: animation,
              child: cover,
              builder: (context, child) {
                final t = animation.value;
                final end = Offset((constraints.maxWidth - side) / 2,
                    (constraints.maxHeight - side) / 2);
                // The stage starts 24dp from the card edge and below its safe area.
                final origin = Offset(-12, 8 - 12 - safeTop);
                return Align(
                  alignment: Alignment.topLeft,
                  child: Transform.translate(
                    offset: Offset.lerp(origin, end, t)!,
                    child: Transform.scale(
                      alignment: Alignment.topLeft,
                      scale: ui.lerpDouble(44 / side, 1, t)!,
                      child: child,
                    ),
                  ),
                );
              },
            );
          });
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: .975, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(_lyrics), child: stage),
    );
  }

  Widget _dismissGesture(Widget child) {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        final controller = widget.transitionController;
        if (controller == null) return;
        controller.value = (controller.value -
                details.delta.dy / MediaQuery.sizeOf(context).height)
            .clamp(.001, 1.0);
      },
      onVerticalDragCancel: () {
        if (ModalRoute.of(context)?.isCurrent == true) {
          widget.transitionController?.forward();
        }
      },
      onVerticalDragEnd: (details) {
        final controller = widget.transitionController;
        if (controller == null) return;
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 500 || (velocity >= -500 && controller.value < .78)) {
          Navigator.of(context).maybePop();
        } else {
          controller.fling(velocity: 1.5);
        }
      },
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }

  Widget _buildArtwork(PlayerModel player, double size) {
    if (_vinyl) {
      return VinylRecordWidget(
        imageInfo: _imageInfo,
        imageProvider: _imageProvider,
        errorCoverUrl: errorCoverUrl,
        isPlaying: player.isPlaying,
      );
    }
    if (size <= 0) return const SizedBox.shrink();
    final provider = _imageProvider;
    const shape = ContinuousRounding(26);
    final placeholder = Image.asset(errorCoverUrl,
        width: size, height: size, fit: BoxFit.cover);
    return Center(
      child: DecoratedBox(
        decoration: const ShapeDecoration(
          shape: shape,
          shadows: [
            BoxShadow(
                color: Color(0x3D000000), blurRadius: 22, offset: Offset(0, 8)),
          ],
        ),
        child: ClipPath(
          clipper: const ShapeBorderClipper(shape: shape),
          child: SizedBox.square(
            dimension: size,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: provider == null
                  ? placeholder
                  : Image(
                      key: ValueKey(provider),
                      image: provider,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      frameBuilder: (_, child, frame, __) =>
                          frame == null ? placeholder : child,
                      errorBuilder: (_, __, ___) => placeholder,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMusicInfo(
      BuildContext context, PlayerModel player, MusicItem music) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        if (_lyrics) ...[
          Semantics(
              button: true,
              label: "回到封面",
              container: true,
              child: GestureDetector(
                  onTap: _toggleStage,
                  child: TrackArtwork(music: music, size: 46, radius: 9))),
          const SizedBox(width: 10)
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onLongPress: () => copyTrackName(music),
                child: Text(
                  clearHtmlTags(music.name),
                  maxLines: _lyrics ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: (_lyrics
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.headlineSmall)
                      ?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                    height: 1.13,
                  ),
                ),
              ),
              if (music.author.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  clearHtmlTags(music.author),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant, letterSpacing: .15),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Pressable(
          enabled: !_savingLike,
          child: IconButton.filledTonal(
            tooltip: isLike ? "取消收藏" : "收藏",
            color: isLike ? colors.primary : colors.onSurface,
            onPressed: _savingLike ? null : () => _toggleLike(music),
            icon: Icon(isLike
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded),
          ),
        ),
        const SizedBox(width: 4),
        _moreActions(music),
      ],
    );
  }

  Future<void> _toggleLike(MusicItem music) async {
    AppHaptics.action();
    setState(() => _savingLike = true);
    try {
      final like = !await FavSyncService.isInMyMusic(music.id);
      if (like) {
        await FavSyncService.addMusic(music);
      } else {
        await FavSyncService.removeMusic(music.id);
      }
      if (mounted && identical(music, context.read<PlayerModel>().current)) {
        ++_favoriteRead;
        setState(() => isLike = like);
      }
      eventBus.fire(RefreshMusicList(tabName: TableName.myMusic));
      BotToast.showText(text: like ? "已收藏" : "已取消收藏");
    } catch (_) {
      BotToast.showText(text: "收藏操作失败");
    } finally {
      if (mounted) setState(() => _savingLike = false);
    }
  }

  Future<void> _launchBilibiliVideo(String bvId) async {
    try {
      final needsConfirmation = await getLaunchBilibiliConfirm();
      if (!mounted) return;
      if (needsConfirmation) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text("打开哔哩哔哩"),
            content: const Text("将打开当前视频。未安装哔哩哔哩时，会使用网页。"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text("取消")),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text("打开且不再提示")),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      final opened = await openBilibiliVideo(
          bvId, (uri) => launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!opened) {
        if (mounted) BotToast.showText(text: "无法打开视频，请检查浏览器是否可用");
        return;
      }
      if (needsConfirmation) await setLaunchBilibiliConfirm(confirm: false);
    } catch (_) {
      if (mounted) BotToast.showText(text: "打开视频时遇到问题");
    }
  }

  Widget _buildPanel(
      BuildContext context, PlayerModel player, MusicItem music) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMusicInfo(context, player, music),
        const SizedBox(height: 7),
        PlayerProgress(key: ValueKey(music.id), color: colors.onSurface),
        const SizedBox(height: 18),
        IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButton.styleFrom(
              fixedSize: const Size.square(56),
              backgroundColor: colors.onSurface.withValues(alpha: .10),
              shape: const StadiumBorder(),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Center(
                    child: PrevButton(size: 29, color: colors.onSurface)),
              ),
              const SizedBox(width: 13),
              const Expanded(flex: 5, child: PlayButton(prominent: true)),
              const SizedBox(width: 13),
              Expanded(
                flex: 3,
                child: Center(
                    child: NextButton(size: 29, color: colors.onSurface)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ModeButton(size: 22, color: colors.onSurfaceVariant),
            TextButton.icon(
              onPressed: () => showAudioOptions(context),
              icon: const Icon(Icons.graphic_eq_rounded, size: 18),
              label: const Text("音质"),
            ),
            PlayerListButton(size: 24, color: colors.onSurfaceVariant),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final music = player.current;
    if (music == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final dark = theme.brightness == Brightness.dark;
    final tone = HSLColor.fromColor(_artTone);
    final colors = ColorScheme.fromSeed(
      seedColor: _artTone,
      brightness: theme.brightness,
      surface: tone.withLightness(dark ? .145 : .95).toColor(),
    );
    return Theme(
      data: theme.copyWith(
        colorScheme: colors,
        primaryColor: colors.primary,
        bottomSheetTheme: theme.bottomSheetTheme.copyWith(
          backgroundColor: colors.surfaceContainer,
        ),
      ),
      child: Material(
        color: colors.surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_imageProvider != null)
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                  child: Opacity(
                    opacity: .64,
                    child: Image(
                      image: ResizeImage(_imageProvider!, width: 180),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    tone
                        .withLightness(dark ? .24 : .88)
                        .toColor()
                        .withValues(alpha: dark ? .38 : .58),
                    colors.surface.withValues(alpha: dark ? .60 : .80),
                    colors.surface,
                  ],
                  stops: const [0, .55, 1],
                ),
              ),
            ),
            // 8bit 渐变在大面积纯色上会出色带，铺一层极淡的噪点打散
            const IgnorePointer(
              child: SizedBox.expand(
                child: Image(
                  image: AssetImage("assets/images/dither.png"),
                  fit: BoxFit.none,
                  repeat: ImageRepeat.repeat,
                  errorBuilder: _noDither,
                ),
              ),
            ),
            _dismissGesture(SafeArea(
              child: LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth > 640 &&
                    constraints.maxWidth > constraints.maxHeight;
                final artwork = Padding(
                  padding: EdgeInsets.fromLTRB(24, 12, 24, wide ? 12 : 10),
                  child: _buildStage(player, music, safeTop),
                );
                final panel = Padding(
                  padding: const EdgeInsets.fromLTRB(24, 3, 24, 0),
                  child: _buildPanel(context, player, music),
                );
                return Column(
                  children: [
                    const PartyLockBanner(),
                    Expanded(
                      child: wide
                          ? Row(
                              children: [
                                Expanded(child: artwork),
                                Expanded(
                                  child: Center(
                                    child: SingleChildScrollView(child: panel),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                Expanded(child: artwork),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: constraints.maxHeight * .66,
                                  ),
                                  child: SingleChildScrollView(child: panel),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 5),
                  ],
                );
              }),
            )),
          ],
        ),
      ),
    );
  }
}

/// 一起听：只能听时的提示条
///
/// 想自己换歌 / 拖进度，必须先退出房间——规则写在这里，别让人到处找。
class PartyLockBanner extends StatelessWidget {
  const PartyLockBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final session = PartySession.instance;
    final colors = Theme.of(context).colorScheme;

    return StreamBuilder<void>(
      stream: session.changes,
      builder: (context, _) {
        if (!session.isLocked) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline,
                  size: 13, color: colors.onTertiaryContainer),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "房主正在控制播放，只能跟着听",
                  style: TextStyle(
                      fontSize: 10, color: colors.onTertiaryContainer),
                ),
              ),
              GestureDetector(
                onTap: () => PartySession.instance.leave(),
                child: Text(
                  "退出一起听",
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.onTertiaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
