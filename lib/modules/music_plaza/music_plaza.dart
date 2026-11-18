import "package:bobomusic/components/continuous_rounding.dart";
import "package:bobomusic/modules/bili_account/bili_login_gate.dart";
import "package:bobomusic/modules/history/history_tab.dart";
import "package:bobomusic/modules/music_plaza/search/search.dart";
import "package:bobomusic/modules/player/artwork.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/modules/player/player.dart";
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

class _ContinuePlaying extends StatelessWidget {
  const _ContinuePlaying();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final music = player.current;
    if (music == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    const foreground = Color(0xFFFFF4F5);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: const Color(0xFF30252D),
        shape: const ContinuousRounding(29),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF624152), Color(0xFF292638)],
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
                                music.name,
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
              const PlayButton(size: 42, color: foreground),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}
