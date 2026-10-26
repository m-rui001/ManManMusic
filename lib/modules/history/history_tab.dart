import "dart:async";

import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/history/play_history.dart";
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
  const HistoryTab({super.key});

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

    return Column(
      children: [
        if (_selecting) _buildSelectBar(entries, primaryColor),
        Expanded(
          child: entries.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                  itemCount: entries.length + 1,
                  itemBuilder: (c, i) {
                    if (i == entries.length) {
                      return _selecting
                          ? const SizedBox(height: 10)
                          : Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Center(
                                child: TextButton(
                                  onPressed: _clearAll,
                                  child: const Text(
                                    "清空播放记录",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            );
                    }

                    final e = entries[i];
                    final key = _keyOf(e);
                    final selected = _selected.contains(key);
                    final isCurrent = player.current?.id == e.music.id;

                    return GestureDetector(
                      onTap: () {
                        if (_selecting) {
                          setState(() {
                            if (selected) {
                              _selected.remove(key);
                            } else {
                              _selected.add(key);
                            }
                          });
                          return;
                        }
                        player.play(music: e.music);
                      },
                      onLongPress: () => _selecting
                          ? setState(() {
                              if (selected) {
                                _selected.remove(key);
                              } else {
                                _selected.add(key);
                              }
                            })
                          : _enterSelect(e),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: selected
                              ? primaryColor.withValues(alpha: 0.06)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: selected
                              ? Border.all(
                                  color: primaryColor.withValues(alpha: 0.4),
                                )
                              : null,
                        ),
                        child: Row(
                          children: [
                            if (_selecting) ...[
                              Icon(
                                selected
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 18,
                                color: selected
                                    ? primaryColor
                                    : Colors.grey[350],
                              ),
                              const SizedBox(width: 8),
                            ],
                            _cover(e.music.cover, primaryColor),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    clearHtmlTags(e.music.name),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isCurrent
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isCurrent
                                          ? primaryColor
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    e.music.author.isEmpty
                                        ? "未知 UP 主"
                                        : clearHtmlTags(e.music.author),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!_selecting)
                              isCurrent
                                  ? Icon(
                                      Icons.graphic_eq,
                                      size: 15,
                                      color: primaryColor,
                                    )
                                  : Text(
                                      _relativeTime(e.playedAt),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                          ],
                        ),
                      ),
                    );
                  },
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 30),
      children: [
        Icon(Icons.history, size: 40, color: Colors.grey[350]),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            "还没有播放记录",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            "去搜索框找首歌听听吧",
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ),
      ],
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

Widget _cover(String url, Color primaryColor) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: 44,
      height: 44,
      child: url.isEmpty
          ? Container(
              color: const Color.fromARGB(255, 240, 240, 240),
              child: Icon(Icons.music_note, size: 17, color: primaryColor),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: const Color.fromARGB(255, 240, 240, 240),
                child: Icon(Icons.music_note, size: 17, color: primaryColor),
              ),
            ),
    ),
  );
}
