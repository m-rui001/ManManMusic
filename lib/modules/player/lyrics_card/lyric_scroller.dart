import "dart:async";
import "dart:math" as math;

import "package:bobomusic/components/sheet/bottom_sheet.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/modules/player/utils.dart";
import "package:bobomusic/modules/party/party_control.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/origin_sdk/service.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:bobomusic/utils/haptics.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

/// Translate a displayed lyric timestamp back to the audio timeline.
Duration lyricSeekPosition(int lineMs, int offsetMs, Duration? duration) {
  final position = math.max(0, lineMs - offsetMs);
  final limit = duration?.inMilliseconds ?? 0;
  return Duration(
      milliseconds: limit > 0 ? math.min(position, limit) : position);
}

/// Follow and seek the sentence timestamps supplied by the video.
class LyricsScroller extends StatefulWidget {
  const LyricsScroller({super.key});

  @override
  State<LyricsScroller> createState() => _LyricsScrollerState();
}

class _LyricsScrollerState extends State<LyricsScroller> {
  String _text = "";
  List<Map<String, dynamic>> _lines = [];
  int _offset = 0;
  String? _offsetTrackId;
  MusicItem? _matchingTrack;
  int _matchRequest = 0;
  MusicItem? _attempted;
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
      _lines = parseLyrics(lyrics);
    }

    if (_lines.isEmpty) {
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
                key: ValueKey(music.id),
                builder: (context, snapshot) {
                  final position =
                      (snapshot.data ?? player.currentPosition).inMilliseconds +
                          _offset;
                  final index = _activeLine(position);
                  final end = index < 0 ? null : _lines[index]["end"] as int?;
                  return _SentenceList(
                    key: ObjectKey(_lines),
                    lines: _lines,
                    active: index,
                    highlighted: index >= 0 && (end == null || position < end),
                    onSeek: (index) async {
                      if (!_isCurrent(music) || PartyControl.blocked()) return;
                      AppHaptics.action();
                      try {
                        await player.seek(lyricSeekPosition(
                            _lines[index]["time"], _offset, player.duration));
                      } catch (_) {
                        if (mounted) BotToast.showText(text: "跳转失败，请稍后再试");
                      }
                    },
                  );
                },
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

  int _activeLine(int milliseconds) {
    var low = 0;
    var high = _lines.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_lines[mid]["time"] <= milliseconds) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low - 1;
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

class _SentenceList extends StatefulWidget {
  const _SentenceList(
      {super.key,
      required this.lines,
      required this.active,
      required this.highlighted,
      required this.onSeek});

  final List<Map<String, dynamic>> lines;
  final int active;
  final bool highlighted;
  final ValueChanged<int> onSeek;

  @override
  State<_SentenceList> createState() => _SentenceListState();
}

class _SentenceListState extends State<_SentenceList> {
  final scroll = ScrollController(keepScrollOffset: false);
  late final keys = List.generate(widget.lines.length, (_) => GlobalKey());
  late int anchor = math.max(0, widget.active);
  Timer? resume;
  bool browsing = false;
  int viewportGeneration = 0;

  @override
  void didUpdateWidget(_SentenceList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active && !browsing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
    }
  }

  void _follow() {
    if (!mounted || browsing) return;
    final index = math.max(0, widget.active);
    final row = keys[index].currentContext;
    if (row == null) {
      // A seek can jump well outside the lazily built rows.
      setState(() {
        anchor = index;
        viewportGeneration++;
      });
    } else {
      Scrollable.ensureVisible(row,
          alignment: .24,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut);
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      resume?.cancel();
      browsing = true;
    } else if (notification is ScrollEndNotification && browsing) {
      resume?.cancel();
      resume = Timer(const Duration(seconds: 3), () {
        browsing = false;
        _follow();
      });
    }
    return false;
  }

  @override
  void dispose() {
    resume?.cancel();
    scroll.dispose();
    super.dispose();
  }

  Widget _row(int index) {
    final colors = Theme.of(context).colorScheme;
    final selected = widget.highlighted && index == widget.active;
    return Semantics(
      key: keys[index],
      button: true,
      selected: selected,
      child: InkWell(
        onTap: () {
          resume?.cancel();
          browsing = false;
          widget.onSeek(index);
          if (selected) _follow();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Text(
            widget.lines[index]["text"].toString().trim(),
            style: TextStyle(
              fontSize: 26,
              height: 1.32,
              fontWeight: FontWeight.w700,
              color: selected
                  ? colors.onSurface
                  : colors.onSurface.withValues(alpha: .43),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = ValueKey(anchor);
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: CustomScrollView(
        key: ValueKey(viewportGeneration),
        controller: scroll,
        primary: false,
        anchor: .24,
        center: center,
        slivers: [
          SliverList.builder(
              itemCount: anchor, itemBuilder: (_, i) => _row(anchor - 1 - i)),
          SliverList.builder(
              key: center,
              itemCount: widget.lines.length - anchor,
              itemBuilder: (_, i) => _row(anchor + i)),
          const SliverFillRemaining(
              hasScrollBody: false, child: SizedBox.shrink()),
        ],
      ),
    );
  }
}
