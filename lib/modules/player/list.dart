import "package:bobomusic/db/db.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/modules/player/player_card/current_list.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
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
        height: MediaQuery.sizeOf(context).height * .68,
        child: DefaultTabController(
          length: 2,
          initialIndex: current == null ? 1 : 0,
          child: Column(
            children: [
              const TabBar(tabs: [
                Tab(text: "当前播放"),
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
