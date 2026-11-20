import "package:bobomusic/modules/player/const.dart";
import "dart:async";

import "package:bobomusic/components/music_list_tile/music_list_tile.dart";
import "package:bobomusic/components/search_field.dart";
import "package:bobomusic/components/sheet/bottom_sheet.dart";
import "package:bobomusic/constants/cache_key.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/modules/music_order/components/edit_music.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:bobomusic/modules/music_plaza/search/search.dart"
    as bili_search;
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:flutter/material.dart";
import "package:bobomusic/modules/player/player.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";

final db = DBOrder();

class SearchOrderMusicView extends StatefulWidget {
  final String initialQuery;
  final bool searchOnOpen;

  const SearchOrderMusicView({
    super.key,
    this.initialQuery = "",
    this.searchOnOpen = false,
  });

  @override
  State<SearchOrderMusicView> createState() => SearchOrderMusicViewState();
}

class SearchOrderMusicViewState extends State<SearchOrderMusicView> {
  late final TextEditingController _keywordController;
  final _focusNode = FocusNode();
  bool _loading = false;
  bool _searchFailed = false;
  int _generation = 0;
  final List<MusicItem> searchMusicList = [];
  List<String> _searchHistory = [];
  List<String> _localSuggestions = [];

  // 本地资料库没有页码；只执行一次查询，避免触底重复追加同一批结果。
  Future<void> _searchHandler(bool clean) async {
    final keyword = _keywordController.text.trim();
    if (!clean) return;
    final generation = ++_generation;
    _debounceTimer?.cancel();
    _searchFailed = false;

    if (keyword.isEmpty) {
      setState(() {
        searchMusicList.clear();
        _loading = false;
      });
      return;
    }

    _focusNode.unfocus();
    setState(() {
      _loading = true;
      searchMusicList.clear();
      _localSuggestions = [];
    });

    try {
      final musicLocal = await findMusicFromLocalOrders(param: keyword);
      final musicCommon = await findMusicFromNotLocalOrders(param: keyword);
      if (!mounted || generation != _generation) return;
      setState(() {
        searchMusicList.addAll([...musicLocal, ...musicCommon]);
        _loading = false;
      });
      unawaited(updateSearchHistory(keyword));
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _searchFailed = true;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _keywordController = TextEditingController(text: widget.initialQuery);
    _focusNode.addListener(_refreshFocus);
    getSearchHistory();
    if (widget.searchOnOpen && widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchHandler(true);
      });
    } else {
      _focusNode.requestFocus();
    }
  }

  void _refreshFocus() => setState(() {});

  Future<void> getSearchHistory() async {
    final list = await getSearchHistoryData();
    if (!mounted) return;
    setState(() => _searchHistory = list);
  }

  updateSearchHistory(String keyword, {bool isDelete = false}) async {
    final localStorage = await SharedPreferences.getInstance();
    final list =
        localStorage.getStringList(CacheKey.searchOrderMusicHistory) ?? [];
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
    if (!mounted) return;
    setState(() => _searchHistory = list);
  }

  @override
  void dispose() {
    _generation++;
    _debounceTimer?.cancel();
    _keywordController.dispose();
    _focusNode.removeListener(_refreshFocus);
    _focusNode.dispose();
    super.dispose();
  }

  Timer? _debounceTimer;
  void _onInputChange(String value) {
    _searchFailed = false;
    searchMusicList.clear();
    _generation++;
    _debounceTimer?.cancel();
    final keyword = value.trim();
    if (keyword.isEmpty) {
      setState(() {
        _localSuggestions = [];
        _loading = false;
      });
      return;
    }

    final matchingHistory = _searchHistory
        .where((item) => item.toLowerCase().contains(keyword.toLowerCase()))
        .toList();
    setState(() {
      _localSuggestions = matchingHistory;
      _loading = false;
    });
    _debounceTimer = Timer(const Duration(milliseconds: 250), () async {
      final generation = _generation;
      try {
        final local = await findMusicFromLocalOrders(param: keyword);
        final common = await findMusicFromNotLocalOrders(param: keyword);
        if (!mounted ||
            generation != _generation ||
            !_focusNode.hasFocus ||
            _keywordController.text.trim() != keyword) {
          return;
        }
        final suggestions = <String>{
          ...matchingHistory,
          ...local.map((item) => clearHtmlTags(item.name)),
          ...common.map((item) => clearHtmlTags(item.name)),
        }.where((item) => item.isNotEmpty).take(12).toList();
        setState(() => _localSuggestions = suggestions);
      } catch (_) {
        // History suggestions remain useful if the local database is unavailable.
      }
    });
  }

  Widget buildSearchHistory() {
    return ListView.builder(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        bottom: 70,
        top: SearchOverlayScaffold.contentTopInset(context),
      ),
      itemCount: _searchHistory.length,
      itemBuilder: (context, index) {
        final keyword = _searchHistory[index];
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
                Expanded(
                  child: Text(keyword,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 16,
                          color: Color.fromARGB(255, 146, 146, 145),
                          overflow: TextOverflow.ellipsis)),
                ),
                IconButton(
                  tooltip: "删除搜索记录",
                  icon: const Icon(Icons.delete_forever,
                      size: 16, color: Color.fromARGB(255, 146, 146, 145)),
                  onPressed: () => updateSearchHistory(keyword, isDelete: true),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget buildSearchSuggest() {
    return ListView.builder(
      padding: EdgeInsets.only(
        top: SearchOverlayScaffold.contentTopInset(context),
        bottom: 100,
      ),
      itemCount: _localSuggestions.length,
      itemBuilder: (context, index) {
        final suggestion = _localSuggestions[index];
        return ListTile(
          leading: const Icon(Icons.history_rounded),
          title: Text(suggestion, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () {
            _keywordController.text = suggestion;
            _searchHandler(true);
          },
        );
      },
    );
  }

  void showItemSheet(BuildContext context, MusicItem data) {
    final player = Provider.of<PlayerModel>(context, listen: false);
    openBottomSheet(
      context,
      [
        SheetItem(
          title: "播放",
          icon: Icons.play_arrow_rounded,
          onPressed: () {
            player.play(music: data);
          },
        ),
        SheetItem(
          title: "添加到待播放",
          icon: Icons.playlist_add_rounded,
          onPressed: () {
            player.addPlayerList([data], showToast: true);
          },
        ),
        SheetItem(
          title: "收藏到歌单",
          icon: Icons.favorite_border_rounded,
          onPressed: () {
            collectToMusicOrder(context: context, musicList: [data]);
          },
        ),
        SheetItem(
          title: "编辑信息",
          icon: Icons.edit_outlined,
          onPressed: () {
            Navigator.of(context).push(ModalBottomSheetRoute(
              isScrollControlled: true,
              builder: (context) {
                return Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: EditMusic(
                      musicItem: data,
                      onOk: (music) async {
                        await db.update(
                            TableName.musicLocal, musicItem2Row(music: music));

                        if (queueEntryIndex([data], player.current) == 0) {
                          player.current = music;
                        }

                        _searchHandler(true);
                      },
                    ));
              },
            ));
          },
        ),
      ],
      header: SheetHeader(
        title: clearHtmlTags(data.name),
        subtitle: clearHtmlTags(data.author),
        track: data,
      ),
    );
  }

  Widget buildBody(BuildContext context) {
    if (_focusNode.hasFocus) {
      if (_keywordController.text.trim().isEmpty) return buildSearchHistory();
      return buildSearchSuggest();
    }
    if (_keywordController.text.trim().isEmpty) return buildSearchHistory();
    if (searchMusicList.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(
            top: SearchOverlayScaffold.contentTopInset(context)),
        child: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : _searchFailed
                    ? TextButton.icon(
                        onPressed: () => _searchHandler(true),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text("资料库读取失败，点击重试"))
                    : const Text("没有匹配的歌曲")),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.only(
        top: SearchOverlayScaffold.contentTopInset(context),
        bottom: 100,
      ),
      itemCount: searchMusicList.length + 1,
      itemBuilder: (ctx, index) {
        if (index == searchMusicList.length) {
          return const SizedBox(height: 40, child: Center(child: Text("到底了")));
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

  void _switchScope(SearchScope scope) {
    if (scope == SearchScope.library) return;
    final query = _keywordController.text;
    final searchOnOpen = !_focusNode.hasFocus;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => bili_search.SearchView(
          initialQuery: query,
          searchOnOpen: searchOnOpen,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SearchOverlayScaffold(
      keywordController: _keywordController,
      focusNode: _focusNode,
      hintText: "搜索",
      onSearch: () => _searchHandler(true),
      onInput: _onInputChange,
      scope: SearchScope.library,
      onScopeChanged: _switchScope,
      onClose: () => Navigator.of(context).pop(),
      body: buildBody(context),
      floatingActionButton: const PlayerView(cancelMargin: true),
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
