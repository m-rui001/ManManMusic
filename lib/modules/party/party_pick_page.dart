import "package:bobomusic/modules/party/party_roster.dart";
import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";

/// 从「我关注的人」里挑选加入一起听名单
///
/// 默认一个都不选，用户自己挑。已经加入的显示为已勾选，
/// 取消勾选等于从名单移除。
class PartyPickPage extends StatefulWidget {
  const PartyPickPage({super.key});

  @override
  State<PartyPickPage> createState() => _PartyPickPageState();
}

class _PartyPickPageState extends State<PartyPickPage> {
  final BiliAuth _auth = BiliAuth.instance;
  final PartyRoster _roster = PartyRoster.instance;

  List<BiliFriend> _all = [];
  bool _loading = true;
  String? _error;

  /// 本次改动后的目标名单（mid 集合）
  final Set<int> _picked = {};

  @override
  void initState() {
    super.initState();
    _picked.addAll(_roster.members.map((e) => e.mid));
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _auth.fetchFriends(pageSize: 50);
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "获取关注列表失败，稍后再试";
      });
    }
  }

  Future<void> _save() async {
    final addList = <RosterMember>[];
    for (final f in _all) {
      if (!_picked.contains(f.mid)) continue;
      addList.add(
        RosterMember(mid: f.mid, uname: f.uname, face: f.face),
      );
    }

    // 若有人被取消勾选，从名单移除
    for (final m in _roster.members) {
      if (!_picked.contains(m.mid)) {
        await _roster.remove(m.mid);
      }
    }
    await _roster.addAll(addList);

    if (!mounted) return;
    BotToast.showText(text: "已更新一起听名单（${_picked.length} 人）");
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text("选择一起听的人", style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: Text(
              "完成",
              style: TextStyle(fontSize: 13, color: primaryColor),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(onPressed: _load, child: const Text("重试")),
                      ],
                    ),
                  )
                : _all.isEmpty
                    ? const Center(
                        child: Text(
                          "你在 B 站还没有关注任何人",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
                        itemCount: _all.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(
                                left: 4,
                                bottom: 10,
                              ),
                              child: Text(
                                "勾选的人会出现在一起听列表里。"
                                "没勾选的不会被探测，也不会打扰你。",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                  height: 1.6,
                                ),
                              ),
                            );
                          }

                          final f = _all[i - 1];
                          final checked = _picked.contains(f.mid);

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                if (checked) {
                                  _picked.remove(f.mid);
                                } else {
                                  _picked.add(f.mid);
                                }
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: checked
                                    ? primaryColor.withValues(alpha: 0.05)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: checked
                                    ? Border.all(
                                        color: primaryColor.withValues(
                                          alpha: 0.35,
                                        ),
                                      )
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 19,
                                    backgroundColor: const Color.fromARGB(
                                      255,
                                      240,
                                      240,
                                      240,
                                    ),
                                    backgroundImage: f.face.isNotEmpty
                                        ? NetworkImage(f.face)
                                        : null,
                                    child: f.face.isEmpty
                                        ? Icon(
                                            Icons.person,
                                            size: 18,
                                            color: Colors.grey[400],
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          f.uname.isEmpty ? "未知用户" : f.uname,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                          ),
                                        ),
                                        if (f.sign.isNotEmpty)
                                          Text(
                                            f.sign,
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
                                  Icon(
                                    checked
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    size: 20,
                                    color: checked
                                        ? primaryColor
                                        : Colors.grey[350],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
