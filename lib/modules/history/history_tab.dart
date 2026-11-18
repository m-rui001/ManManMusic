import "dart:async";

import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/history/play_history.dart";
import "package:bobomusic/modules/player/artwork.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

/// 历史播放分栏
///
/// 交互：
/// - 点击播放
/// - 长按进入多选，可单选、可全选、可批量删除
/// - 「清空」按钮一次性清空
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key, this.header});

  final Widget? header;

  @override
  State<HistoryTab> createState() => HistoryTabState();
}

class HistoryTabState extends State<HistoryTab> {
  StreamSubscription? _sub;
  StreamSubscription? _playerSub;

  /// 多选模式下已选中的条目（用 id+时间戳做 key）
  final Set<String> _selected = {};
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    PlayHistory.instance.init().then((_) {
      if (mounted) setState(() {});
    });
    _sub = PlayHistory.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _playerSub = eventBus.on<RefreshPlayerCard>().listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _playerSub?.cancel();
    super.dispose();
  }

  String _keyOf(HistoryEntry e) =>
      "${e.music.id}_${e.music.playId}_${e.playedAt.millisecondsSinceEpoch}";

  void _enterSelect(HistoryEntry e) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(_keyOf(e));
    });
  }

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;

    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("删除播放记录", style: TextStyle(fontSize: 14)),
        content: Text(
          "确定删除选中的 $count 条播放记录？歌曲本身不受影响。",
          style: const TextStyle(fontSize: 12, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("删除"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await PlayHistory.instance.removeWhere(
      (e) => _selected.contains(_keyOf(e)),
    );

    if (!mounted) return;
    _exitSelect();
    BotToast.showText(text: "已删除 $count 条记录");
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("清空播放记录", style: TextStyle(fontSize: 14)),
        content: const Text(
          "确定清空全部播放记录？歌曲本身不受影响。",
          style: TextStyle(fontSize: 12, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("清空"),
          ),
        ],
      ),
    );

    if (ok == true) await PlayHistory.instance.clear();
  }

  @override
  Widget build(BuildContext context) {
    final entries = PlayHistory.instance.entries;
    final primaryColor = Theme.of(context).primaryColor;
    final player = Provider.of<PlayerModel>(context);

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      children: [
        if (_selecting) _buildSelectBar(entries, primaryColor),
        Expanded(
          child: CustomScrollView(
            slivers: [
              if (!_selecting && widget.header != null)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(child: widget.header),
                ),
              if (entries.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: _buildEmpty()),
              if (entries.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  sliver: SliverList.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final music = entry.music;
                      final key = _keyOf(entry);
                      final selected = _selected.contains(key);
                      final current = player.current?.id == music.id;
                      void toggle() => setState(() {
                            if (!_selected.remove(key)) _selected.add(key);
                          });

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 9),
                          selected: selected || current,
                          selectedTileColor: selected
                              ? colors.primaryContainer
                              : colors.surfaceContainer,
                          onTap: _selecting
                              ? toggle
                              : () => player.play(music: music),
                          onLongPress:
                              _selecting ? toggle : () => _enterSelect(entry),
                          leading: _selecting
                              ? Icon(selected
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined)
                              : TrackArtwork(cover: music.cover, size: 47),
                          title: Text(
                            clearHtmlTags(music.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight:
                                  current ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          subtitle: music.author.isEmpty
                              ? null
                              : Text(
                                  clearHtmlTags(music.author),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                          trailing: _selecting
                              ? null
                              : current
                                  ? Icon(player.isPlaying
                                      ? Icons.graphic_eq_rounded
                                      : Icons.pause_rounded)
                                  : Text(
                                      _relativeTime(entry.playedAt),
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                        ),
                      );
                    },
                  ),
                ),
              if (!_selecting && entries.isNotEmpty)
                SliverToBoxAdapter(
                  child: Center(
                    child: TextButton(
                      onPressed: _clearAll,
                      child: const Text("清空播放记录"),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 多选工具条
  Widget _buildSelectBar(List<HistoryEntry> entries, Color primaryColor) {
    final allSelected =
        entries.isNotEmpty && _selected.length == entries.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            "已选 ${_selected.length}",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              setState(() {
                if (allSelected) {
                  _selected.clear();
                } else {
                  _selected
                    ..clear()
                    ..addAll(entries.map(_keyOf));
                }
              });
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
            ),
            child: Text(
              allSelected ? "取消全选" : "全选",
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: _selected.isEmpty ? null : _deleteSelected,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
            ),
            child: const Text(
              "删除",
              style: TextStyle(fontSize: 11, color: Colors.redAccent),
            ),
          ),
          TextButton(
            onPressed: _exitSelect,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
            ),
            child: Text(
              "完成",
              style: TextStyle(fontSize: 11, color: primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 40, color: colors.outline),
          const SizedBox(height: 12),
          Text("还没有播放记录", style: TextStyle(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return "刚刚";
    if (diff.inHours < 1) return "${diff.inMinutes} 分钟前";
    if (diff.inDays < 1) return "${diff.inHours} 小时前";
    if (diff.inDays < 30) return "${diff.inDays} 天前";
    return "${t.month}-${t.day}";
  }
}
