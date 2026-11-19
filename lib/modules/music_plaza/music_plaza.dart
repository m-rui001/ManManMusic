import "dart:math" as math;

import "package:bobomusic/components/continuous_rounding.dart";
import "package:bobomusic/modules/bili_account/bili_login_gate.dart";
import "package:bobomusic/modules/history/history_tab.dart";
import "package:bobomusic/modules/music_plaza/search/search.dart";
import "package:bobomusic/modules/player/artwork.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/modules/player/player.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class MusicPlazaView extends StatefulWidget {
  const MusicPlazaView({super.key});

  @override
  State<MusicPlazaView> createState() => _MusicPlazaViewState();
}

class _MusicPlazaViewState extends State<MusicPlazaView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) BiliLoginGate.maybePromptOnStartup(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Material(
                  color: colors.surfaceContainer,
                  shape: const ContinuousRounding(21),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: const Icon(Icons.search_rounded),
                    title: const Text("搜索歌曲、UP 主"),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SearchView()),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: HistoryTab(
                  header: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _ContinuePlaying(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
                        child: Text(
                          "最近播放",
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 首页「继续播放」卡的配色
///
/// 取主题色的色相、压到暗部，白字在深浅主题里都读得清。
/// 深空黑本身没有色相，保持中性灰，别硬造出一个颜色来。
({Color top, Color bottom, Color foreground}) continuePlayingPalette(
    Color primary) {
  final seed = HSLColor.fromColor(primary);
  final neutral = seed.saturation < .08;
  final saturation = neutral ? 0.0 : math.max(seed.saturation, .34);
  final foreground =
      HSLColor.fromAHSL(1, seed.hue, neutral ? 0.0 : .16, .965).toColor();
  return (
    top: _darkEnough(
        HSLColor.fromAHSL(1, seed.hue, saturation, .30), foreground),
    bottom: _darkEnough(
        HSLColor.fromAHSL(1, (seed.hue + 26) % 360, saturation * .8, .155),
        foreground),
    foreground: foreground,
  );
}

/// 黄色系在同一 HSL 亮度下比蓝色亮得多，写死亮度会让白字读不清，
/// 所以按实测对比度往暗里收，收到够为止。
Color _darkEnough(HSLColor color, Color foreground) {
  var hsl = color;
  while (_contrast(foreground, hsl.toColor()) < 4.6 && hsl.lightness > .04) {
    hsl = hsl.withLightness(hsl.lightness - .015);
  }
  return hsl.toColor();
}

double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

class _ContinuePlaying extends StatelessWidget {
  const _ContinuePlaying();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final music = player.current;
    if (music == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final palette = continuePlayingPalette(theme.colorScheme.primary);
    final foreground = palette.foreground;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: palette.bottom,
        shape: const ContinuousRounding(29),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [palette.top, palette.bottom],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => showPlayerCard(context),
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Row(
                      children: [
                        TrackArtwork(music: music, size: 64, radius: 13),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                player.isPlaying ? "正在播放" : "继续播放",
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: foreground.withValues(alpha: .86),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                clearHtmlTags(music.name),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: foreground,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              PlayButton(size: 42, color: foreground),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}
