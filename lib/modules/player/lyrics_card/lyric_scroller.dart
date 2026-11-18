import "dart:math";

import "package:bobomusic/modules/player/lyrics_card/lyric_search.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:flutter_lyric/lyric_ui/ui_netease.dart";
import "package:flutter_lyric/lyrics_model_builder.dart";
import "package:flutter_lyric/lyrics_reader_model.dart";
import "package:flutter_lyric/lyrics_reader_widget.dart";
import "package:provider/provider.dart";

class LyricsScroller extends StatefulWidget {
  const LyricsScroller({super.key});

  @override
  State<LyricsScroller> createState() => _LyricsScrollerState();
}

class _LyricsScrollerState extends State<LyricsScroller> {
  final _lyricUi = UINetease(defaultSize: 16);
  String _text = "";
  LyricsReaderModel? _model;
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final music = player.current;
    if (music == null) return const SizedBox.shrink();
    final lyrics = music.lyric.trim();
    if (lyrics != _text) {
      _text = lyrics;
      _model = lyrics.isEmpty
          ? null
          : LyricsModelBuilder.create().bindLyricToMain(lyrics).getModel();
    }
    final model = _model;

    if (model == null) {
      return Center(
        child: TextButton.icon(
          icon: const Icon(Icons.lyrics_outlined),
          label: const Text("匹配歌词"),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => SearchLyricMusicView(track: music),
          )),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxHeight <= 0) return const SizedBox.shrink();
            return StreamBuilder<Duration>(
              stream: player.positions,
              initialData: player.currentPosition,
              builder: (context, snapshot) => KeyedSubtree(
                key: ValueKey(lyrics),
                child: LyricsReader(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  model: model,
                  position: max(
                    0,
                    (snapshot.data ?? player.currentPosition).inMilliseconds +
                        _offset,
                  ),
                  lyricUi: _lyricUi,
                  playing: player.isPlaying,
                  size: constraints.biggest,
                ),
              ),
            );
          }),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _adjust(
                Icons.keyboard_double_arrow_left_rounded, -2000, "歌词后移 2 秒"),
            _adjust(Icons.keyboard_arrow_left_rounded, -500, "歌词后移 0.5 秒"),
            _adjust(Icons.keyboard_arrow_right_rounded, 500, "歌词前移 0.5 秒"),
            _adjust(
                Icons.keyboard_double_arrow_right_rounded, 2000, "歌词前移 2 秒"),
            PopupMenuButton<String>(
              tooltip: "歌词选项",
              onSelected: (action) async {
                if (action == "reset") {
                  setState(() => _offset = 0);
                  return;
                }
                try {
                  await player.setLyrics(music, "");
                } catch (_) {
                  BotToast.showText(text: "歌词删除失败");
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: "reset", child: Text("重置歌词偏移")),
                PopupMenuItem(value: "clear", child: Text("移除当前歌词")),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _adjust(IconData icon, int delta, String label) => IconButton(
        tooltip: label,
        icon: Icon(icon),
        onPressed: () {
          setState(() => _offset += delta);
          BotToast.showText(
              text: "歌词偏移 ${(_offset / 1000).toStringAsFixed(1)} 秒");
        },
      );
}
