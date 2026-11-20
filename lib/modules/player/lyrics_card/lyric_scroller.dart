import "dart:async";
import "dart:math" as math;

import "package:bobomusic/components/sheet/bottom_sheet.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/origin_sdk/service.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:bobomusic/utils/haptics.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:flutter_lyric/lyric_ui/lyric_ui.dart";
import "package:flutter_lyric/lyric_ui/ui_netease.dart";
import "package:flutter_lyric/lyrics_model_builder.dart";
import "package:flutter_lyric/lyrics_reader_model.dart";
import "package:flutter_lyric/lyrics_reader_widget.dart";
import "package:provider/provider.dart";

/// 播放页的歌词模式
///
/// 歌词来自这条视频自己的 B 站字幕，切歌后静默自动匹配，
/// 没有手动搜索——匹配不上就如实说没有。当前行放大加粗逐字点亮，
/// 其余行压暗；上下边缘渐隐，拖动可以挑一句直接跳过去。
class LyricsScroller extends StatefulWidget {
  const LyricsScroller({super.key});

  @override
  State<LyricsScroller> createState() => _LyricsScrollerState();
}

class _LyricsScrollerState extends State<LyricsScroller> {
  String _text = "";
  LyricsReaderModel? _model;
  int _offset = 0;
  String? _offsetTrackId;
  MusicItem? _matchingTrack;
  int _matchRequest = 0;
  MusicItem? _attempted;
  _LyricStyle? _style;
  ({Color text, Color highlight})? _styleSeed;

  _LyricStyle _styleFor(ColorScheme colors) {
    // onSurface 在深浅主题里是写死的，只盯它会让换主题色后高亮色不更新
    final seed = (text: colors.onSurface, highlight: colors.primary);
    final cached = _style;
    if (cached != null && _styleSeed == seed) return cached;
    _styleSeed = seed;
    return _style = _LyricStyle(
      main: seed.text,
      highlightColor: seed.highlight,
    );
  }

  Future<void> _autoMatch(MusicItem music) async {
    if (!_isCurrent(music) || identical(_matchingTrack, music)) return;
    final request = ++_matchRequest;
    setState(() => _matchingTrack = music);
    try {
      final lrc = await service.getSubtitleLrc(music.id);
      if (lrc == null || lrc.isEmpty || !mounted) return;
      if (request != _matchRequest || !_isCurrent(music)) return;
      await context.read<PlayerModel>().setLyrics(music, lrc);
    } catch (_) {
      // 自动匹配失败不打扰，面板里还能再试一次
    } finally {
      if (mounted && request == _matchRequest) {
        setState(() => _matchingTrack = null);
      }
    }
  }

  bool _isCurrent(MusicItem music) =>
      mounted && identical(music, context.read<PlayerModel>().current);

  void _openOptions(MusicItem music) {
    openBottomSheet(
      context,
      [
        SheetItem(
          title: "歌词前移 0.5 秒",
          icon: Icons.fast_forward_rounded,
          onPressed: () => _shift(music, 500),
        ),
        SheetItem(
          title: "歌词后移 0.5 秒",
          icon: Icons.fast_rewind_rounded,
          onPressed: () => _shift(music, -500),
        ),
        SheetItem(
          title: "重置偏移",
          subtitle: _offset == 0 ? null : "当前 ${_offsetLabel()}",
          icon: Icons.restart_alt_rounded,
          onPressed: _offset == 0 ? null : () => _shift(music, -_offset),
        ),
        SheetItem(
          title: "重新匹配字幕",
          subtitle: "再取一次这条视频的字幕",
          icon: Icons.subtitles_outlined,
          onPressed: () => _autoMatch(music),
        ),
        SheetItem(
          title: "移除当前歌词",
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onPressed: () async {
            if (!_isCurrent(music)) return;
            ++_matchRequest;
            setState(() {
              _matchingTrack = null;
              _attempted = music;
            });
            try {
              await context.read<PlayerModel>().setLyrics(music, "");
            } catch (_) {
              BotToast.showText(text: "歌词删除失败");
            }
          },
        ),
      ],
      header: SheetHeader(
        title: clearHtmlTags(music.name),
        subtitle: clearHtmlTags(music.author),
      ),
    );
  }

  String _offsetLabel() {
    final seconds = _offset / 1000;
    return "${seconds > 0 ? "+" : ""}${seconds.toStringAsFixed(1)} 秒";
  }

  void _shift(MusicItem music, int delta) {
    if (!_isCurrent(music)) return;
    setState(() => _offset += delta);
    BotToast.showText(text: "歌词偏移 ${_offsetLabel()}");
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final music = player.current;
    if (music == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    if (_offsetTrackId != music.id) {
      _offsetTrackId = music.id;
      _offset = 0;
    }
    final lyrics = music.lyric.trim();
    if (lyrics != _text) {
      _text = lyrics;
      _model = lyrics.isEmpty
          ? null
          : LyricsModelBuilder.create().bindLyricToMain(lyrics).getModel();
    }
    final model = _model;

    if (model == null) {
      final matchable = music.origin == OriginType.bili &&
          music.localPath.isEmpty &&
          int.tryParse(music.id.split("_").first) != null;
      if (!identical(_matchingTrack, music) &&
          matchable &&
          !identical(_attempted, music)) {
        _attempted = music;
        WidgetsBinding.instance.addPostFrameCallback((_) => _autoMatch(music));
      }
      return _empty(context, music, colors, matchable);
    }

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxHeight <= 0) return const SizedBox.shrink();
            return ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: [0, .09, .88, 1],
              ).createShader(bounds),
              child: StreamBuilder<Duration>(
                stream: player.positions,
                initialData: player.currentPosition,
                builder: (context, snapshot) => KeyedSubtree(
                  key: ValueKey(lyrics),
                  child: LyricsReader(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    model: model,
                    position: math.max(
                      0,
                      (snapshot.data ?? player.currentPosition).inMilliseconds +
                          _offset,
                    ),
                    lyricUi: _styleFor(colors),
                    playing: player.isPlaying,
                    size: constraints.biggest,
                    selectLineBuilder: (startTime, cancel) =>
                        _seekBar(context, player, colors, startTime, cancel),
                  ),
                ),
              ),
            );
          }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 12, 0),
          child: Row(
            children: [
              if (_offset != 0)
                Text(
                  "偏移 ${_offsetLabel()}",
                  style:
                      TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                ),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: "歌词设置",
                onPressed: () => _openOptions(music),
                icon: const Icon(Icons.tune_rounded, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _seekBar(
    BuildContext context,
    PlayerModel player,
    ColorScheme colors,
    int startTime,
    VoidCallback cancel,
  ) {
    final stamp = Duration(milliseconds: startTime);
    String two(int value) => value.toString().padLeft(2, "0");
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: "从这里播放",
            iconSize: 20,
            style: IconButton.styleFrom(
              backgroundColor: colors.onSurface.withValues(alpha: .12),
              foregroundColor: colors.onSurface,
              minimumSize: const Size.square(38),
            ),
            onPressed: () {
              AppHaptics.action();
              cancel();
              player.seek(stamp);
            },
            icon: const Icon(Icons.play_arrow_rounded),
          ),
          const SizedBox(width: 10),
          Text(
            "${two(stamp.inMinutes)}:${two(stamp.inSeconds % 60)}",
            style: TextStyle(
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: colors.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: "继续跟随播放",
            iconSize: 18,
            color: colors.onSurfaceVariant,
            onPressed: cancel,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _empty(
    BuildContext context,
    MusicItem music,
    ColorScheme colors,
    bool matchable,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (identical(_matchingTrack, music)) ...[
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Text("正在匹配字幕",
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
          ] else ...[
            Icon(Icons.subtitles_outlined,
                size: 30, color: colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              matchable ? "这条视频没有可用字幕" : "这首歌没有歌词",
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            ),
            if (matchable) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  _attempted = music;
                  _autoMatch(music);
                },
                child: const Text("重新匹配", style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// 歌词排版：当前行大、亮、逐字点亮，其余行小、暗
class _LyricStyle extends UINetease {
  final Color main;
  final Color highlightColor;

  _LyricStyle({required this.main, required this.highlightColor})
      : super(
          defaultSize: 28,
          otherMainSize: 27,
          defaultExtSize: 15,
          bias: .24,
          lineGap: 24,
          inlineGap: 18,
          lyricAlign: LyricAlign.LEFT,
        );

  // 当前行没唱到的部分也要比别的行亮，唱到的部分再点成主题色，
  // 否则一行刚开头时反而比上下文暗，看不出唱到哪了。
  @override
  TextStyle getPlayingMainTextStyle() => TextStyle(
        color: main.withValues(alpha: .78),
        fontSize: defaultSize,
        fontWeight: FontWeight.w700,
        height: 1.32,
      );

  @override
  TextStyle getOtherMainTextStyle() => TextStyle(
        color: main.withValues(alpha: .38),
        fontSize: otherMainSize,
        fontWeight: FontWeight.w600,
        height: 1.32,
      );

  @override
  TextStyle getPlayingExtTextStyle() =>
      TextStyle(color: main.withValues(alpha: .3), fontSize: defaultExtSize);

  @override
  TextStyle getOtherExtTextStyle() =>
      TextStyle(color: main.withValues(alpha: .3), fontSize: defaultExtSize);

  @override
  Color getLyricHightlightColor() => highlightColor;

  // 歌词比视口短时，包里的 baseOffset 会把可偏移上限算成正数，
  // 随后 clamp(正数, 0) 直接抛 ArgumentError。关掉这个「保底半屏」即可。
  @override
  bool halfSizeLimit() => false;
}
