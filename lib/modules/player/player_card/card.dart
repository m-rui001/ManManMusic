// ignore_for_file: use_build_context_synchronously, avoid_print, deprecated_member_use

import "dart:async";
import "dart:ui";

import "package:bobomusic/components/ripple_icon/ripple_icon.dart";
import "package:bobomusic/icons/icons_svg.dart";
import "package:bobomusic/modules/bili_account/fav_sync.dart";
import "package:bobomusic/modules/party/party_page.dart";
import "package:bobomusic/constants/covers.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/download/model.dart";
import "package:bobomusic/modules/player/lyrics_card/lyric_scroller.dart";
import "package:bobomusic/modules/player/artwork.dart";
import "package:bobomusic/modules/player/audio_options.dart";
import "package:bobomusic/modules/player/player_card/progress.dart";
import "package:bobomusic/modules/player/player_card/vinyl_record.dart";
import "package:bobomusic/modules/player/utils.dart";
import "package:bobomusic/modules/share/share_sheet.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/origin_sdk/service.dart";
import "package:bobomusic/utils/check_music_local_repeat.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:bobomusic/modules/player/player.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:like_button/like_button.dart";
import "package:provider/provider.dart";
import "package:url_launcher/url_launcher.dart";
import "package:uuid/uuid.dart";

const uuid = Uuid();
final DBOrder db = DBOrder();

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
  late PageController _pageController;
  int _currentPage = 0;
  final List<StreamSubscription?> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentPage);

    _subscriptions.add(eventBus.on<RefreshPlayerCard>().listen((event) {
      _initCoverAndLyric();
      _initState();
    }));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCoverAndLyric();
      _initState();
    });
  }

  Future<void> _initState() async {
    final current = Provider.of<PlayerModel>(context, listen: false).current;
    if (current == null) return;

    final liked = await FavSyncService.isInMyMusic(current.id);
    if (!mounted) return;
    setState(() => isLike = liked);
  }

  Future<void> _initCoverAndLyric() async {
    if (!mounted) return;
    final player = context.read<PlayerModel>();
    final current = player.current;
    if (current == null || identical(current, _artworkTrack)) return;
    _artworkTrack = current;

    final original = musicArtwork(current.cover);
    _loadImage(original, onError: () => _findArtwork(current));
    if (original == null) {
      await _findArtwork(current);
    } else if (current.lyric.isEmpty) {
      await _findArtwork(current, onlyLyrics: true);
    }
  }

  Future<void> _findArtwork(MusicItem current,
      {bool onlyLyrics = false}) async {
    try {
      final result = await lyricService.searchMusic(
        SearchParams(keyword: current.name, page: 1, pageSize: 10),
        silent: true,
      );
      if (!mounted ||
          !identical(_artworkTrack, current) ||
          result == null ||
          result.list.isEmpty) {
        return;
      }
      final match = result.list.first;
      if (!onlyLyrics && _imageInfo == null) {
        _loadImage(musicArtwork(match.albumcover));
      }
      if (current.lyric.isNotEmpty || current.orderName.isEmpty) return;
      final lyric = await lyricService.searchLyric(match.songmid);
      if (!mounted || !identical(_artworkTrack, current) || lyric == null) {
        return;
      }
      final id = await db.update(current.orderName,
          musicItem2Row(music: current.copyWith(lyric: lyric.lyric)));
      if (id > -1) eventBus.fire(ScrollLyric());
    } catch (_) {
      // 保留原封面。找不到匹配时使用内置占位图。
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
    _pageController.dispose();
    super.dispose();
  }

  void _loadImage(ImageProvider? provider, {VoidCallback? onError}) {
    _removeImageListener();
    setState(() {
      _imageInfo?.dispose();
      _imageInfo = null;
      _imageProvider = provider;
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
    }, onError: (_, __) => onError?.call());
    stream.addListener(_imageListener!);
  }

  Widget _buildTopBar(Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            tooltip: "收起播放器",
            color: primaryColor,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          IconButton(
            tooltip: "音质与音效",
            color: primaryColor,
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => showAudioOptions(context),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordWidget() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        child: VinylRecordWidget(
          imageInfo: _imageInfo,
          imageProvider: _imageProvider,
          errorCoverUrl: errorCoverUrl,
          isPlaying: Provider.of<PlayerModel>(context, listen: false).isPlaying,
        ),
      ),
    );
  }

  Widget _buildMusicInfo(Color primaryColor) {
    final player = context.read<PlayerModel>();
    final music = player.current!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 3),
      child: Column(
        children: [
          Text(
            music.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              color: primaryColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (music.author.isNotEmpty)
            Text(
              music.author,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
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

  Widget _buildActionButtons(Color primaryColor) {
    final player = Provider.of<PlayerModel>(context, listen: false);
    final musicItem = player.current as MusicItem;
    final isLocal = musicItem.localPath.isNotEmpty;

    return Container(
      padding: const EdgeInsets.only(left: 42, right: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          RippleIcon(
            size: 28,
            child: Transform.translate(
              offset: const Offset(0, 1),
              child:
                  Icon(Icons.download_outlined, color: primaryColor, size: 28),
            ),
            onTap: () {
              if (isLocal) {
                BotToast.showText(text: "本地音乐，无需下载");
                return;
              }

              checkMusicLocalRepeat(context, musicItem, () {
                final downloadModel =
                    Provider.of<DownloadModel>(context, listen: false);
                downloadModel.download([musicItem]);
              });
            },
          ),
          Padding(
              padding: const EdgeInsets.all(8),
              child: LikeButton(
                size: 28,
                animationDuration: const Duration(seconds: 1),
                circleColor: const CircleColor(
                    start: Color(0xff00ddff), end: Color(0xff0099cc)),
                bubblesColor: const BubblesColor(
                  dotPrimaryColor: Color(0xff33b5e5),
                  dotSecondaryColor: Color.fromARGB(255, 198, 121, 44),
                  dotThirdColor: Color.fromARGB(255, 204, 33, 33),
                  dotLastColor: Color.fromARGB(255, 44, 198, 80),
                ),
                likeBuilder: (bool isLiked) {
                  return isLike
                      ? const Icon(Icons.favorite,
                          size: 28, color: Colors.redAccent)
                      : Icon(Icons.favorite_border_rounded,
                          color: primaryColor, size: 28);
                },
                onTap: (bool isLiked) async {
                  final music = player.current;
                  if (music == null) return isLike;

                  try {
                    if (!isLike) {
                      await FavSyncService.addMusic(music);
                      if (!mounted) return isLike;

                      setState(() => isLike = true);
                      BotToast.showText(text: "已加进满满音乐");
                    } else {
                      await FavSyncService.removeMusic(music.id);
                      if (!mounted) return isLike;

                      setState(() => isLike = false);
                      BotToast.showText(text: "已从满满音乐移除");
                    }

                    eventBus.fire(RefreshMusicList(tabName: TableName.myMusic));
                  } catch (error) {
                    print(error);
                  }

                  return isLike;
                },
              )),
          RippleIcon(
            size: 28,
            child: SvgPicture.string(
              IconsSVG.bilibili,
              color: primaryColor,
              width: 28,
              height: 28,
            ),
            onTap: () {
              final biliVIDs = player.current!.id
                  .split("_")
                  .where((e) => e.startsWith("BV"))
                  .toList();

              if (biliVIDs.isNotEmpty) {
                _launchBilibiliVideo(biliVIDs[0], player);
              } else {
                BotToast.showText(text: "找不到视频");
              }
            },
          ),
          RippleIcon(
            size: 28,
            child: Icon(Icons.ios_share, size: 27, color: primaryColor),
            onTap: () {
              showShareSheet(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons(Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ModeButton(size: 23, color: color),
        PrevButton(size: 30, color: color),
        PlayButton(size: 48, color: color),
        NextButton(size: 30, color: color),
        PlayerListButton(size: 23, color: color),
      ],
    );
  }

  // 构建轮播组件内的指示器
  Widget _buildCarouselIndicator(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          2, // 总页数
          (index) => Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index == _currentPage
                  ? primaryColor
                  : primaryColor.withOpacity(0.3),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final music = player.current;
    if (music == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final color = colors.onSurface;

    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Image(
            image: _imageInfo != null
                ? _imageProvider!
                : AssetImage(errorCoverUrl),
            fit: BoxFit.cover,
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.surface.withValues(alpha: .70),
                colors.surface.withValues(alpha: .90),
                colors.surface,
              ],
            ),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth > 520 &&
                constraints.maxWidth > constraints.maxHeight;
            final carousel = Column(
              children: [
                _buildCarouselIndicator(color),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) =>
                        setState(() => _currentPage = index),
                    children: [_buildRecordWidget(), const LyricsScroller()],
                  ),
                ),
              ],
            );
            final panel = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMusicInfo(color),
                _buildActionButtons(color),
                PlayerProgress(key: ValueKey(music.id), color: color),
                _buildControlButtons(color),
              ],
            );
            return Column(
              children: [
                _buildTopBar(color),
                const PartyLockBanner(),
                if (wide)
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: carousel),
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(child: panel),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Expanded(child: carousel),
                  panel,
                ],
                const SizedBox(height: 8),
              ],
            );
          }),
        ),
      ],
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
