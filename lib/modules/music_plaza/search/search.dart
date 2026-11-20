// ignore_for_file: use_build_context_synchronously

import "dart:async";

import "package:bobomusic/modules/player/artwork.dart";
import "package:bobomusic/constants/app_info.dart";

import "package:bobomusic/components/pressable.dart";
import "package:bobomusic/components/sheet/bottom_sheet.dart";
import "package:bobomusic/components/search_field.dart";
import "package:bobomusic/constants/cache_key.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/download/model.dart";
import "package:bobomusic/modules/music_order/utils.dart";
import "package:bobomusic/utils/check_music_local_repeat.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:bot_toast/bot_toast.dart";
import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:bobomusic/components/text_tags/tags.dart";
import "package:bobomusic/modules/music_plaza/components/detail.dart";
import "package:bobomusic/modules/player/player.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/origin_sdk/service.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:uuid/uuid.dart";

const uuid = Uuid();

class SearchView extends StatefulWidget {
  final String initialQuery;
  final bool searchOnOpen;

  const SearchView({
    super.key,
    this.initialQuery = "",
    this.searchOnOpen = false,
  });

  @override
  State<SearchView> createState() => SearchViewState();
}

class SearchViewState extends State<SearchView> {
  final ScrollController _scrollController = ScrollController();
  late final TextEditingController _keywordController;
  final _focusNode = FocusNode();
  int _current = 0;
  int _generation = 0;
  String _query = "";
  bool _hasMore = true;
  bool _loading = false;
  bool _searchFailed = false;
  int _playRequest = 0;
  int _seasonRequest = 0;
  final List<SearchItem> _searchItemList = [];
  List<String> _searchHistory = [];
  List<String> _searchSuggest = [];

  Future<void> _searchHandler(bool clean) async {
    if (!clean && (_loading || !_hasMore || _query.isEmpty)) return;
    final generation = clean ? ++_generation : _generation;
    final keyword = clean ? _keywordController.text.trim() : _query;
    if (clean) {
      _debounceTimer?.cancel();
      _focusNode.unfocus();
      _query = keyword;
      _current = 0;
      _hasMore = true;
    }
    if (keyword.isEmpty) {
      setState(() {
        _searchItemList.clear();
        _searchSuggest.clear();
        _loading = false;
      });
      return;
    }

    final page = _current + 1;
    setState(() {
      _loading = true;
      _searchFailed = false;
      if (clean) _searchItemList.clear();
    });
    try {
      final result =
          await service.search(SearchParams(keyword: keyword, page: page));
      if (!mounted || generation != _generation) return;
      setState(() {
        _searchItemList.addAll(result.data);
        _current = page;
        _hasMore = result.data.isNotEmpty &&
            result.pageSize > 0 &&
            page * result.pageSize < result.total;
      });
      if (clean && result.data.isNotEmpty) {
        unawaited(updateSearchHistory(keyword));
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _searchFailed = true);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  // 轻点音频直接切换播放；曲目选项保留给长按。
  Future<void> _onClickMusic(SearchItem item) async {
    final request = ++_playRequest;
    try {
      // 搜索摘要没有每一 P 的 cid，详情才包含可播放的真实音轨。
      final detail = await service.searchDetail(item.id);
      if (!mounted || request != _playRequest) return;
      final tracks = _musicListFromSearch(detail);
      await context.read<PlayerModel>().play(
            music: tracks.first,
            collection: tracks.length > 1 ? tracks : null,
          );
    } catch (_) {
      if (mounted && request == _playRequest)
        BotToast.showText(text: "音频详情加载失败");
    }
  }

  List<MusicItem> _musicListFromSearch(SearchItem detail) {
    final tracks = detail.musicList;
    if (tracks != null && tracks.isNotEmpty) return tracks;
    return [_musicFromSearch(detail)];
  }

  MusicItem _musicFromSearch(SearchItem detail) {
    final tracks = detail.musicList;
    if (tracks != null && tracks.isNotEmpty) return tracks.first;
    return MusicItem(
      id: detail.id,
      cover: detail.cover,
      name: detail.name,
      collectionName: detail.ugcSeason?.title ?? "",
      duration: detail.duration,
      author: detail.author,
      origin: detail.origin,
    );
  }

  void _showMusicActions(SearchItem detail) {
    final player = Provider.of<PlayerModel>(context, listen: false);
    final tracks = _musicListFromSearch(detail);
    final music = tracks.first;
    openBottomSheet(
      context,
      [
        SheetItem(
          title: "播放",
          icon: Icons.play_arrow_rounded,
          onPressed: () {
            player.play(
              music: music,
              collection: tracks.length > 1 ? tracks : null,
            );
          },
        ),
        SheetItem(
          title: "添加到待播放",
          icon: Icons.playlist_add_rounded,
          onPressed: () {
            player.addPlayerList(tracks, showToast: true);
          },
        ),
        SheetItem(
          title: "收藏到歌单",
          icon: Icons.favorite_border_rounded,
          onPressed: () {
            collectToMusicOrder(context: context, musicList: [music]);
          },
        ),
        SheetItem(
          title: "下载",
          icon: Icons.download_rounded,
          onPressed: () {
            checkMusicLocalRepeat(context, music, () {
              final downloadModel =
                  Provider.of<DownloadModel>(context, listen: false);
              downloadModel.download([music]);
            });
          },
        ),
        if (detail.isSeasonDisplay && detail.ugcSeason != null)
          SheetItem(
            title: "查看所在合集",
            icon: Icons.video_library_outlined,
            onPressed: () => _openSeason(detail, collect: false),
          ),
        if (detail.isSeasonDisplay && detail.ugcSeason != null)
          SheetItem(
            title: "收藏所在合集",
            icon: Icons.library_add_outlined,
            onPressed: () => _openSeason(detail, collect: true),
          ),
      ],
      header: SheetHeader(
        title: clearHtmlTags(music.name),
        subtitle: clearHtmlTags(music.author),
        track: music,
      ),
    );
  }

  // 歌单合集点击
  void _onClickCollection(SearchItem detail) {
    final collection = detail.musicList?.isNotEmpty == true
        ? detail
        : SearchItem(
            id: detail.id,
            cover: detail.cover,
            name: detail.name,
            duration: detail.duration,
            author: detail.author,
            origin: detail.origin,
            isSeasonDisplay: detail.isSeasonDisplay,
            ugcSeason: detail.ugcSeason,
            musicList: _musicListFromSearch(detail),
            type: SearchType.orderName,
          );
    openBottomSheet(
      context,
      [
        SheetItem(
          title: "查看合集",
          icon: Icons.video_library_outlined,
          onPressed: () {
            viewCollectionList(collection);
          },
        ),
        SheetItem(
          title: "收藏合集",
          icon: Icons.library_add_outlined,
          onPressed: () async {
            await collectionList(collection);
          },
        ),
      ],
      header: SheetHeader(
        title: clearHtmlTags(detail.name),
        subtitle: clearHtmlTags(detail.author),
      ),
    );
  }

  Future<void> _openSeason(SearchItem detail, {required bool collect}) async {
    final season = detail.ugcSeason;
    if (season == null) return;
    final request = ++_seasonRequest;
    final generation = _generation;
    bool active() =>
        mounted &&
        request == _seasonRequest &&
        generation == _generation &&
        ModalRoute.of(context)?.isCurrent == true;
    try {
      final collection =
          await service.searchSeason(season.mid, season.seasonId);
      if (!active()) return;
      if (collection == null) {
        BotToast.showText(text: "合集加载失败，请重试");
        return;
      }
      final result = SearchItem(
        id: "${collection.meta.seasonId}",
        cover: collection.meta.cover,
        name: collection.meta.name,
        duration: 0,
        author: "",
        origin: OriginType.bili,
        isSeasonDisplay: false,
        musicList: collection.musicList,
      );
      if (collect) {
        await collectionList(result);
      } else {
        viewCollectionList(result);
      }
    } catch (_) {
      if (active()) BotToast.showText(text: "合集加载失败，请重试");
    }
  }

  /// 查看合集详情
  viewCollectionList(SearchItem detail) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MusicOrderDetail(
          shouldLoadData: false,
          musicOrderItem: MusicOrderItem(
            id: detail.id,
            cover: detail.cover,
            name: detail.name,
            author: detail.author,
            desc: "",
            musicList: detail.musicList ?? [],
          ),
        ),
      ),
    );
  }

  /// 把整个合集加进「满满音乐」
  ///
  /// v3 起只有一张歌单，不再为每个合集单独建表，
  /// 也就不会再出现 "table 收藏夹_xxx already exists" 这种错。
  Future<void> collectionList(SearchItem detail) async {
    final list = detail.musicList ?? [];
    if (list.isEmpty) {
      BotToast.showText(text: "这个合集里没有可播放的音频");
      return;
    }

    EasyLoading.show(maskType: EasyLoadingMaskType.black);
    final int added;
    try {
      added = await addToMyMusic(list);
    } catch (_) {
      if (mounted) BotToast.showText(text: "收藏失败，请重试");
      return;
    } finally {
      EasyLoading.dismiss();
    }

    BotToast.showText(
      text: added > 0 ? "已收藏 $added 首" : "这些曲目已收藏",
    );

    eventBus.fire(RefreshMusicList(tabName: TableName.myMusic));
    if (added > 0) {
      eventBus.fire(RefreshTabList());
    }
  }

  @override
  void initState() {
    super.initState();
    _keywordController = TextEditingController(text: widget.initialQuery);
    _scrollController.addListener(() {
      if (_scrollController.hasClients &&
          !_searchFailed &&
          _scrollController.position.extentAfter < 160) {
        unawaited(_searchHandler(false));
      }
    });
    getSearchHistory();
    if (widget.searchOnOpen && widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchHandler(true);
      });
    } else {
      _focusNode.requestFocus();
    }
  }

  getSearchHistory() async {
    final list = await getSearchHistoryData();
    if (!mounted) return;
    setState(() {
      _searchHistory = list;
    });
  }

  Future<void> updateSearchHistory(String keyword,
      {bool isDelete = false}) async {
    final localStorage = await SharedPreferences.getInstance();
    final list = localStorage.getStringList(CacheKey.searchHistory) ?? [];
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
    await localStorage.setStringList(CacheKey.searchHistory, list);
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
    _focusNode.dispose();
    super.dispose();
  }

  Timer? _debounceTimer;
  void _onInputChange(String value) {
    _generation++;
    _debounceTimer?.cancel();
    final keyword = value.trim();
    setState(() {
      _searchItemList.clear();
      _query = "";
      _searchFailed = false;
      _current = 0;
      _hasMore = true;
      _loading = false;
    });
    if (keyword.isEmpty) {
      setState(() => _searchSuggest = []);
      return;
    }
    final matchingHistory = _searchHistory
        .where((item) => item.toLowerCase().contains(keyword.toLowerCase()))
        .toList();
    setState(() {
      _searchSuggest = matchingHistory;
      _loading = false;
    });
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final generation = _generation;
      try {
        final results = await service.searchSuggest(keyword);
        if (!mounted ||
            generation != _generation ||
            !_focusNode.hasFocus ||
            _keywordController.text.trim() != keyword) {
          return;
        }
        final suggestions = <String>{
          ...matchingHistory,
          ...results.map((item) => item.value),
        }.where((item) => item.isNotEmpty).take(12).toList();
        setState(() => _searchSuggest = suggestions);
      } catch (_) {
        // Local history suggestions remain available offline.
      }
    });
  }

  Widget buildSearchHistory() {
    return ListView.builder(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
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
      itemCount: _searchSuggest.length,
      itemBuilder: (context, index) {
        final suggestion = _searchSuggest[index];
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

  Widget _retrySearch(bool clean) => TextButton.icon(
        onPressed: () => _searchHandler(clean),
        icon: const Icon(Icons.refresh_rounded),
        label: Text(clean ? "搜索失败，点击重试" : "加载失败，点击重试"),
      );

  Widget buildBody(BuildContext context) {
    if (_focusNode.hasFocus && _searchSuggest.isNotEmpty) {
      return buildSearchSuggest();
    }
    if (_searchItemList.isEmpty) {
      if (_loading) {
        return Padding(
          padding: EdgeInsets.only(
              top: SearchOverlayScaffold.contentTopInset(context)),
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      if (_query.isNotEmpty && !_focusNode.hasFocus) {
        return Padding(
          padding: EdgeInsets.only(
              top: SearchOverlayScaffold.contentTopInset(context)),
          child: Center(
              child:
                  _searchFailed ? _retrySearch(true) : const Text("没有找到相关视频")),
        );
      }
      return buildSearchHistory();
    }

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: SearchOverlayScaffold.contentTopInset(context),
        bottom: 100,
      ),
      itemCount: _searchItemList.length + 1,
      itemBuilder: (ctx, index) {
        if (_searchItemList.isEmpty) {
          return null;
        }
        if (index == _searchItemList.length) {
          return SizedBox(
            height: 48,
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : _searchFailed
                      ? _retrySearch(false)
                      : !_hasMore
                          ? const Text("到底了")
                          : null,
            ),
          );
        }
        final item = _searchItemList[index];
        final cover = musicArtwork(item.cover);
        final pixels = (50 * MediaQuery.devicePixelRatioOf(context)).round();
        final placeholder =
            Image.asset(appLogoAsset, fit: BoxFit.cover, cacheWidth: pixels);
        final tags = [item.origin.name, item.author];

        final radius = BorderRadius.vertical(
          top: Radius.circular(index == 0 ? 20 : 6),
          bottom: Radius.circular(index == _searchItemList.length - 1 ? 20 : 6),
        );
        return Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 3),
            child: Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                shape: RoundedRectangleBorder(borderRadius: radius),
                clipBehavior: Clip.antiAlias,
                child: Pressable(
                  pressScale: .985,
                  pressedColor: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .07),
                  pressedBorderRadius: radius,
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: radius),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox.square(
                          dimension: 50,
                          child: cover == null
                              ? placeholder
                              : CachedNetworkImage(
                                  imageUrl: cover.url,
                                  httpHeaders: cover.headers,
                                  memCacheWidth: pixels,
                                  placeholder: (_, __) => placeholder,
                                  errorWidget: (_, __, ___) => placeholder,
                                  fit: BoxFit.cover,
                                )),
                    ),
                    title: Text(
                      clearHtmlTags(item.name),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    subtitle: TextTags(tags: tags),
                    onTap: () => _onClickMusic(item),
                    onLongPress: () async {
                      try {
                        final detail = await service.searchDetail(item.id);
                        if (!mounted) return;
                        if (detail.type == SearchType.orderName) {
                          _onClickCollection(detail);
                        } else {
                          _showMusicActions(detail);
                        }
                      } catch (_) {
                        if (mounted) BotToast.showText(text: "音频详情加载失败");
                      }
                    },
                  ),
                )));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SearchOverlayScaffold(
      keywordController: _keywordController,
      focusNode: _focusNode,
      hintText: "搜索 B 站歌曲、UP 主",
      onSearch: () => _searchHandler(true),
      onInput: _onInputChange,
      onClose: () => Navigator.of(context).pop(),
      body: buildBody(context),
      floatingActionButton: const PlayerView(cancelMargin: true),
    );
  }
}

Future<List<String>> getSearchHistoryData() async {
  final localStorage = await SharedPreferences.getInstance();
  final list = localStorage.getStringList(CacheKey.searchHistory);
  return list ?? [];
}

Future updateSearchHistoryData(List<String> list) async {
  final localStorage = await SharedPreferences.getInstance();
  await localStorage.setStringList(CacheKey.searchHistory, list);
}
