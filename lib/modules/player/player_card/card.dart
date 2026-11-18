// ignore_for_file: use_build_context_synchronously, avoid_print, deprecated_member_use

import "dart:async";
import "dart:ui" as ui;

import "package:bobomusic/components/continuous_rounding.dart";
import "package:bobomusic/modules/bili_account/fav_sync.dart";
import "package:bobomusic/modules/party/party_page.dart";
import "package:bobomusic/constants/covers.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/download/model.dart";
import "package:bobomusic/modules/player/artwork.dart";
import "package:bobomusic/modules/player/audio_options.dart";
import "package:bobomusic/modules/player/player_card/progress.dart";
import "package:bobomusic/modules/player/player_card/vinyl_record.dart";
import "package:bobomusic/modules/player/utils.dart";
import "package:bobomusic/modules/share/share_sheet.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/check_music_local_repeat.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:bobomusic/modules/player/player.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:provider/provider.dart";
import "package:url_launcher/url_launcher.dart";
import "package:uuid/uuid.dart";

const uuid = Uuid();

class PlayerCard extends StatefulWidget {
  const PlayerCard({super.key});

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
  bool _savingLike = false;
  static const _fallbackTone = Color(0xFF81ADA1);
  Color _artTone = _fallbackTone;
  final List<StreamSubscription?> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _subscriptions.add(eventBus.on<RefreshPlayerCard>().listen((event) {
      _initCover();
      _initState();
    }));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCover();
      _initState();
    });
  }

  Future<void> _initState() async {
    final current = Provider.of<PlayerModel>(context, listen: false).current;
    if (current == null) return;

    final liked = await FavSyncService.isInMyMusic(current.id);
    if (!mounted || !identical(current, context.read<PlayerModel>().current)) {
      return;
    }
    setState(() => isLike = liked);
  }

  void _initCover() {
    if (!mounted) return;
    final current = context.read<PlayerModel>().current;
    if (current == null || identical(current, _artworkTrack)) return;
    _artworkTrack = current;
    _loadImage(musicArtwork(current.cover));
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

  Widget _buildTopBar(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 13),
        child: IconButton(
          tooltip: "收起播放器",
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Widget _moreActions(PlayerModel player, MusicItem music) {
    return PopupMenuButton<String>(
      tooltip: "更多播放选项",
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (action) {
        switch (action) {
          case "download":
            checkMusicLocalRepeat(context, music, () {
              context.read<DownloadModel>().download([music]);
            });
          case "bilibili":
            final bv = RegExp(r"BV[0-9A-Za-z]+").firstMatch(music.id);
            if (bv != null) _launchBilibiliVideo(bv.group(0)!, player);
          case "share":
            showShareSheet(context);
          case "vinyl":
            setState(() => _vinyl = !_vinyl);
        }
      },
      itemBuilder: (context) => [
        if (music.localPath.isEmpty)
          const PopupMenuItem(value: "download", child: Text("下载")),
        if (music.id.contains("BV"))
          const PopupMenuItem(value: "bilibili", child: Text("打开哔哩哔哩")),
        const PopupMenuItem(value: "share", child: Text("分享")),
        PopupMenuItem(
          value: "vinyl",
          child: Text(_vinyl ? "方形封面" : "黑胶封面"),
        ),
      ],
    );
  }

  Widget _buildArtwork(PlayerModel player) {
    if (_vinyl) {
      return VinylRecordWidget(
        imageInfo: _imageInfo,
        imageProvider: _imageProvider,
        errorCoverUrl: errorCoverUrl,
        isPlaying: player.isPlaying,
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest.shortestSide.clamp(0.0, 484.0);
      if (size == 0) return const SizedBox.shrink();
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
                  color: Color(0x3D000000),
                  blurRadius: 22,
                  offset: Offset(0, 8)),
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
    });
  }

  Widget _buildMusicInfo(
      BuildContext context, PlayerModel player, MusicItem music) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                music.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                  height: 1.13,
                ),
              ),
              if (music.author.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  music.author,
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
        IconButton.filledTonal(
          tooltip: isLike ? "移出满满音乐" : "收藏到满满音乐",
          color: isLike ? colors.primary : colors.onSurface,
          onPressed: _savingLike ? null : () => _toggleLike(music),
          icon: Icon(
              isLike ? Icons.favorite_rounded : Icons.favorite_border_rounded),
        ),
        const SizedBox(width: 4),
        _moreActions(player, music),
      ],
    );
  }

  Future<void> _toggleLike(MusicItem music) async {
    setState(() => _savingLike = true);
    final like = !isLike;
    try {
      if (like) {
        await FavSyncService.addMusic(music);
      } else {
        await FavSyncService.removeMusic(music.id);
      }
      if (mounted && identical(music, context.read<PlayerModel>().current)) {
        setState(() => isLike = like);
      }
      eventBus.fire(RefreshMusicList(tabName: TableName.myMusic));
      BotToast.showText(text: like ? "已加进满满音乐" : "已从满满音乐移除");
    } catch (_) {
      BotToast.showText(text: "收藏操作失败");
    } finally {
      if (mounted) setState(() => _savingLike = false);
    }
  }

  Future<void> _launchBilibiliVideo(String bvId, PlayerModel player) async {
    try {
      final res = await getLaunchBilibiliConfirm();

      if (res) {
        showDialog(
            context: context,
            builder: (ctx) => Container(
                  alignment: Alignment.bottomCenter,
                  child: CupertinoActionSheet(
                    title: const Text("打开哔哩哔哩",
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    message: Container(
                      margin: const EdgeInsets.only(top: 6),
                      child: const Text("请授权始终打开，授权后需要重新操作",
                          style: TextStyle(fontSize: 10)),
                    ),
                    actions: [
                      CupertinoActionSheetAction(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            setLaunchBilibiliConfirm(confirm: false);
                            final url = "bilibili://video/$bvId";
                            await launchUrl(Uri.parse(url));
                          },
                          child: const Text("确认且不再提示",
                              style: TextStyle(
                                  fontSize: 12, color: Colors.deepPurple))),
                    ],
                    cancelButton: CupertinoActionSheetAction(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: Text("取消",
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[800]))),
                  ),
                ));
      } else {
        final url = "bilibili://video/$bvId";
        await launchUrl(Uri.parse(url));
      }
    } catch (error) {
      final webUrl =
          "https://www.bilibili.com/video/$bvId/?spm_id_from=333.1007.tianma.1-2-2.click";
      await launchUrl(Uri.parse(webUrl));
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
              shape: const ContinuousRounding(27),
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
              label: const Text("音质与音效"),
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
    final tone = HSLColor.fromColor(_artTone);
    final colors = ColorScheme.fromSeed(
      seedColor: _artTone,
      brightness: Brightness.dark,
      surface: tone.withLightness(.145).toColor(),
    );
    final cover = _imageProvider;
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: colors,
        fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
      ),
      child: Material(
        color: colors.surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cover != null)
              RepaintBoundary(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                  child: Image(
                    image: ResizeImage(cover, width: 120),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    tone.withLightness(.24).toColor().withValues(alpha: .70),
                    colors.surface.withValues(alpha: .83),
                    colors.surface,
                  ],
                  stops: const [0, .60, 1],
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth > 640 &&
                    constraints.maxWidth > constraints.maxHeight;
                final artwork = Padding(
                  padding: EdgeInsets.fromLTRB(24, 12, 24, wide ? 12 : 16),
                  child: _buildArtwork(player),
                );
                final panel = Padding(
                  padding: const EdgeInsets.fromLTRB(24, 3, 24, 0),
                  child: _buildPanel(context, player, music),
                );
                return Column(
                  children: [
                    _buildTopBar(context),
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
            ),
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

    return StreamBuilder<void>(
      stream: session.changes,
      builder: (context, _) {
        if (!session.isLocked) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, size: 13, color: Colors.white70),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  "房主正在控制播放，只能跟着听",
                  style: TextStyle(fontSize: 10, color: Colors.white70),
                ),
              ),
              GestureDetector(
                onTap: () => PartySession.instance.leave(),
                child: const Text(
                  "退出一起听",
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
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
