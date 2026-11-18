import "dart:async";

import "package:bobomusic/constants/cache_key.dart";
import "package:bobomusic/modules/player/lyrics_card/lyric_preview.dart";
import "package:bobomusic/origin_sdk/lyric/client.dart";
import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:bobomusic/modules/player/player.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/origin_sdk/service.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:uuid/uuid.dart";

const uuid = Uuid();

class SearchLyricMusicView extends StatefulWidget {
  const SearchLyricMusicView({super.key, required this.track});
  final MusicItem track;

  @override
  State<SearchLyricMusicView> createState() => SearchLyricMusicViewState();
}

class SearchLyricMusicViewState extends State<SearchLyricMusicView> {
  final ScrollController _scrollController = ScrollController();
  final _keywordController = TextEditingController(text: "");
  final _focusNode = FocusNode();
  int _current = 1;
  int _generation = 0;
  bool _loading = false;
  final List<SongItem> _searchItemList = [];
  List<String> _searchHistory = [];

  // 搜索事件
  void _searchHandler(bool clean) async {
    if (!clean && _loading) return;
    final generation = clean ? ++_generation : _generation;
    if (clean) _current = 1;
    var keyword = _keywordController.text.trim();
    if (keyword.isEmpty) {
      setState(() {
        _searchItemList.clear();
        _loading = false;
      });
      return;
    }

    final p = SearchParams(keyword: keyword, page: _current, pageSize: 10);
    setState(() {
      _loading = true;
    });
    lyricService.searchMusic(p).then((value) {
      if (!mounted || generation != _generation) return;
      if (clean) updateSearchHistory(keyword);
      setState(() {
        if (clean) {
          _searchItemList.clear();
        }
        _searchItemList.addAll(value?.list != null ? value!.list : []);
        _loading = false;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _keywordController.text = widget.track.name;
    _scrollController.addListener(() {
      if (!_loading &&
          _scrollController.position.pixels ==
              _scrollController.position.maxScrollExtent) {
        _current += 1;
        _searchHandler(false);
      }
    });
    getSearchHistory();
    // 输入框选中
    _focusNode.requestFocus();
  }

  getSearchHistory() async {
    final list = await getSearchHistoryData();
    if (!mounted) return;

    setState(() {
      _searchHistory = list;
    });
  }

  updateSearchHistory(String keyword, {bool isDelete = false}) async {
    final localStorage = await SharedPreferences.getInstance();
    final list =
        localStorage.getStringList(CacheKey.searchLyricMusicHistory) ?? [];
    if (list.contains(keyword)) {
      list.remove(keyword);
    }
    // 添加
    if (!isDelete) {
      list.insert(0, keyword);
      // 最多 40 条
      if (list.length > 20) {
        list.removeLast();
      }
    }
    await localStorage.setStringList(CacheKey.searchLyricMusicHistory, list);
    if (!mounted) return;
    setState(() {
      _searchHistory = list;
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.dispose();
    _keywordController.dispose();
    _focusNode.unfocus();
    _focusNode.dispose();
    super.dispose();
  }

  Timer? _debounceTimer;
  _onInputChange(String value) {
    // 防抖
    _debounceTimer?.cancel();
  }

  Widget buildSearchHistory() {
    return Container(
        padding: const EdgeInsets.only(left: 10, right: 10),
        width: double.infinity,
        child: ListView(
          children: _searchHistory.map((keyword) {
            return InkWell(
              borderRadius: const BorderRadius.all(Radius.circular(4)),
              onTap: () {
                _keywordController.text = keyword;
                _searchHandler(true);
              },
              child: Container(
                padding: const EdgeInsets.only(
                  top: 6,
                  bottom: 6,
                  left: 18,
                  right: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(keyword,
                        style: const TextStyle(
                            fontSize: 16,
                            color: Color.fromARGB(255, 146, 146, 145),
                            overflow: TextOverflow.ellipsis)),
                    InkWell(
                      child: const Icon(Icons.delete_forever,
                          size: 16, color: Color.fromARGB(255, 146, 146, 145)),
                      onTap: () {
                        updateSearchHistory(keyword, isDelete: true);
                      },
                    )
                  ],
                ),
              ),
            );
          }).toList(),
        ));
  }

  Widget buildBody(BuildContext context) {
    if (_searchItemList.isEmpty) {
      return buildSearchHistory();
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: _searchItemList.length + 1,
      itemBuilder: (ctx, index) {
        if (_searchItemList.isEmpty) {
          return null;
        }
        if (index == _searchItemList.length) {
          return SizedBox(
            height: 40,
            child: Center(
              child: _loading ? const Text("加载中") : const Text("到底了"),
            ),
          );
        }
        final item = _searchItemList[index];
        String cover = item.albumcover.isNotEmpty ? item.albumcover : "";
        String name = item.songname;
        final List<String> tags = [
          ...item.singer.map((s) {
            return s.name;
          })
        ];

        return ListTile(
          leading: cover.startsWith("http")
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: CachedNetworkImage(
                    imageUrl: cover,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                  ))
              : Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4)),
                  child: const Center(
                      child: Text("无",
                          style: TextStyle(fontSize: 12, color: Colors.grey)))),
          title: Text(
            name,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          subtitle: Text(tags.join("、"),
              style: const TextStyle(
                  overflow: TextOverflow.ellipsis,
                  fontSize: 10,
                  color: Colors.grey)),
          onTap: () async {
            final lyric = await lyricService.searchLyric(item.songmid);

            if (lyric != null && context.mounted) {
              final NavigatorState navigator =
                  Navigator.of(context, rootNavigator: false);
              navigator.push(ModalBottomSheetRoute(
                isScrollControlled: true,
                builder: (context) {
                  return LyricPreview(lyric: lyric.lyric, track: widget.track);
                },
              ));
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    var navigator = Navigator.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: _SearchForm(
          keywordController: _keywordController,
          onSearch: () {
            _searchHandler(true);
          },
          onInput: _onInputChange,
          focusNode: _focusNode,
        ),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(),
            child: const Text("取消"),
          )
        ],
        toolbarHeight: 70,
      ),
      body: buildBody(context),
      floatingActionButton: const PlayerView(cancelMargin: true),
    );
  }
}

class _SearchForm extends StatefulWidget {
  final TextEditingController keywordController;
  final Function() onSearch;
  final Function(String value) onInput;
  final FocusNode focusNode;

  const _SearchForm({
    required this.keywordController,
    required this.onSearch,
    required this.onInput,
    required this.focusNode,
  });

  @override
  State<_SearchForm> createState() => _SearchFormState();
}

class _SearchFormState extends State<_SearchForm> {
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.keywordController,
      onSubmitted: (value) => widget.onSearch(),
      focusNode: widget.focusNode,
      decoration: const InputDecoration(
        filled: true,
        fillColor: Color.fromARGB(255, 239, 240, 241),
        constraints: BoxConstraints(maxHeight: 35),
        border: UnderlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        hintText: "请输入歌曲名查询对应的歌词",
        hintStyle: TextStyle(fontSize: 12),
        contentPadding: EdgeInsets.symmetric(vertical: 13.5, horizontal: 16),
      ),
      onChanged: (value) {
        if (value.isEmpty) {
          widget.onSearch();
          return;
        }

        widget.onInput(value);
      },
    );
  }
}

Future<List<String>> getSearchHistoryData() async {
  final localStorage = await SharedPreferences.getInstance();
  final list = localStorage.getStringList(CacheKey.searchLyricMusicHistory);
  return list ?? [];
}

Future updateSearchHistoryData(List<String> list) async {
  final localStorage = await SharedPreferences.getInstance();
  await localStorage.setStringList(CacheKey.searchLyricMusicHistory, list);
}
