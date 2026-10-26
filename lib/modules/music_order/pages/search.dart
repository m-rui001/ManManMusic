import "dart:async";

import "package:bobomusic/components/music_list_tile/music_list_tile.dart";
import "package:bobomusic/components/sheet/bottom_sheet.dart";
import "package:bobomusic/constants/cache_key.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/modules/music_order/components/edit_music.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:flutter/material.dart";
import "package:bobomusic/modules/player/player.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/origin_sdk/service.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";

final db = DBOrder();

class SearchOrderMusicView extends StatefulWidget {
  const SearchOrderMusicView({super.key});

  @override
  State<SearchOrderMusicView> createState() => SearchOrderMusicViewState();
}

class SearchOrderMusicViewState extends State<SearchOrderMusicView> {
  final ScrollController _scrollController = ScrollController();
  final _keywordController = TextEditingController(text: "");
  final _focusNode = FocusNode();
  bool _loading = false;
  final List<MusicItem> searchMusicList = [];
  List<String> _searchHistory = [];
  List<SearchSuggestItem> _searchSuggest = [];

  // 搜索事件
  void _searchHandler(bool clean) async {
    var keyword = _keywordController.text;
    if (keyword.isEmpty) {
      setState(() {
        searchMusicList.clear();
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
    });

    final musicLocal = await findMusicFromLocalOrders(param: keyword);
    final musicCommon = await findMusicFromNotLocalOrders(param: keyword);

    setState(() {
      if (clean) {
        searchMusicList.clear();
      }

      updateSearchHistory(keyword);

      if (musicLocal.isNotEmpty || musicCommon.isNotEmpty) {
        searchMusicList.addAll([...musicLocal, ...musicCommon]);
      }

      _focusNode.unfocus();
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels ==
          _scrollController.position.maxScrollExtent) {
        _searchHandler(false);
      }
    });
    getSearchHistory();
    // 输入框选中
    _focusNode.requestFocus();
  }

  getSearchHistory() async {
    final list = await getSearchHistoryData();

    setState(() {
      _searchHistory = list;
    });
  }

  updateSearchHistory(String keyword, {bool isDelete = false}) async {
    final localStorage = await SharedPreferences.getInstance();
    final list = localStorage.getStringList(CacheKey.searchOrderMusicHistory) ?? [];
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
    await localStorage.setStringList(CacheKey.searchOrderMusicHistory, list);
    setState(() {
      _searchHistory = list;
    });
  }

  @override
  void dispose() {
    _keywordController.dispose();
    _focusNode.unfocus();
    _focusNode.dispose();
    super.dispose();
  }

  Timer? _debounceTimer;
  _onInputChange(String value) {
    // 防抖
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      service.searchSuggest(_keywordController.text).then((list) {
        setState(() {
          _searchSuggest = list;
        });
      });
    });
  }

  Widget buildSearchHistory() {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 10, bottom: 70),
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
                  Text(keyword, style: const TextStyle(fontSize: 16, color: Color.fromARGB(255, 146, 146, 145), overflow: TextOverflow.ellipsis)),
                  InkWell(
                    child: const Icon(Icons.delete_forever, size: 16, color: Color.fromARGB(255, 146, 146, 145)),
                    onTap: () {
                      updateSearchHistory(keyword, isDelete: true);
                    },
                  )
                ],
              ),
            ),
          );
        }).toList(),
      )
    );
  }

  Widget buildSearchSuggest() {
    return ListView(
      children: _searchSuggest.map((item) {
        // 渲染 html
        return ListTile(
          title: Text(item.value),
          onTap: () {
            _keywordController.text = item.value;
            _searchHandler(true);
            _focusNode.unfocus();
          },
        );
      }).toList(),
    );
  }

  void showItemSheet(BuildContext context, MusicItem data) {
    final player = Provider.of<PlayerModel>(context, listen: false);
    openBottomSheet(context, [
      SheetItem(
        title: Text(
          data.name,
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.bold,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      SheetItem(
        title: const Text("播放"),
        onPressed: () {
          player.play(music: data);
        },
      ),
      SheetItem(
        title: const Text("添加到歌单"),
        onPressed: () {
          collectToMusicOrder(context: context, musicList: [data]);
        },
      ),
      SheetItem(
        title: const Text("添加到待播放列表"),
        onPressed: () {
          player.addPlayerList([data], showToast: true);
        },
      ),
      SheetItem(
        title: const Text("编辑"),
        onPressed: () {
          Navigator.of(context).push(
            ModalBottomSheetRoute(
              isScrollControlled: true,
              builder: (context) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: EditMusic(
                    musicItem: data,
                    onOk: (music) async {
                      await db.update(TableName.musicLocal, musicItem2Row(music: music));

                      if (player.current != null && player.current!.playId == music.playId) {
                        player.current = music;
                      }

                      _searchHandler(true);
                    },
                  )
                );
              },
            )
          );
        },
      ),
    ]);
  }

  Widget buildBody(BuildContext context) {
    if (_focusNode.hasFocus && _searchSuggest.isNotEmpty) {
      return buildSearchSuggest();
    }
    if (searchMusicList.isEmpty && _focusNode.hasFocus) {
      return buildSearchHistory();
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: searchMusicList.length + 1,
      itemBuilder: (ctx, index) {
        if (searchMusicList.isEmpty) {
          return SizedBox(
            height: MediaQuery.of(context).size.height - 200,
            child: const Center(child: Text("没有匹配的歌曲"))
          );
        }
        if (index == searchMusicList.length) {
          return SizedBox(
            height: 40,
            child: Center(
              child: _loading ? const Text("加载中") : const Text("到底了"),
            ),
          );
        }
        final item = searchMusicList[index];

        return MusicListTile(
          item,
          showOrderName: true,
          showOrgin: false,
          onMore: () {
            showItemSheet(context, item);
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
        hintText: "请输入歌曲名或歌手名搜索曲目",
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
  final list = localStorage.getStringList(CacheKey.searchOrderMusicHistory);
  return list ?? [];
}

Future updateSearchHistoryData(List<String> list) async {
  final localStorage = await SharedPreferences.getInstance();
  await localStorage.setStringList(CacheKey.searchOrderMusicHistory, list);
}
