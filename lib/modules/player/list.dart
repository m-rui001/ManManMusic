import "package:bobomusic/db/db.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/modules/player/artwork.dart";
import "package:bobomusic/modules/player/player_card/current_list.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class PlayerList extends StatefulWidget {
  const PlayerList({super.key});

  @override
  State<PlayerList> createState() => _PlayerListState();
}

class _PlayerListState extends State<PlayerList> {
  String? _order;
  Future<List<MusicItem>>? _music;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final current = player.current;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final order = current?.orderName ?? "";
    if (order != _order) {
      _order = order;
      _music = order.isNotEmpty && order != TableName.musicWaitPlay
          ? getUpdatedMusicList(tabName: order)
          : null;
    }

    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .77,
        child: DefaultTabController(
          length: 2,
          initialIndex: current == null ? 1 : 0,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 14, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "播放队列",
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: "关闭播放队列",
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (current != null && MediaQuery.sizeOf(context).height >= 520)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      TrackArtwork(music: current, size: 42),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("当前曲目", style: theme.textTheme.labelSmall),
                            Text(clearHtmlTags(current.name),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const TabBar(tabs: [
                Tab(text: "当前列表"),
                Tab(text: "待播放"),
              ]),
              Expanded(
                child: TabBarView(children: [
                  if (player.collectionQueue.isNotEmpty)
                    CurrentList(musicList: player.collectionQueue)
                  else if (order == TableName.musicWaitPlay)
                    CurrentList(musicList: player.playerList)
                  else if (_music != null)
                    FutureBuilder<List<MusicItem>>(
                      future: _music,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        return CurrentList(
                            musicList: snapshot.data ?? const []);
                      },
                    )
                  else
                    CurrentList(musicList: [if (current != null) current]),
                  CurrentList(musicList: player.playerList, waiting: true),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
