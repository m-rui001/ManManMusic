import "dart:async";

import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/bili_account/bili_account_page.dart";
import "package:bobomusic/modules/bili_account/bili_login_gate.dart";
import "package:bobomusic/modules/history/play_history.dart";
import "package:bobomusic/modules/music_order/music_order.dart";
import "package:bobomusic/modules/music_plaza/search/search.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";

/// 首页
///
/// 布局：
/// - 顶部搜索栏（点开进搜索页）
/// - 可收起的登录/账号卡
/// - 两个分栏：历史播放（默认） / 我的歌单
///   左右滑动或点击标题切换
class MusicPlazaView extends StatefulWidget {
  const MusicPlazaView({super.key});

  @override
  State<MusicPlazaView> createState() => MusicPlazaViewState();
}

class MusicPlazaViewState extends State<MusicPlazaView>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  static const String _kQuick = "manman_home_quick_open";

  late final TabController _tab;
  final PageController _page = PageController();

  bool _quickOpen = true;
  bool _askedLogin = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (_tab.indexIsChanging) return;
      _page.animateToPage(
        _tab.index,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });

    _restoreQuickState();

    // 首次进入首页，弹一次登录引导（不登录也能用，只是音质差）
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_askedLogin || !mounted) return;
      _askedLogin = true;
      await BiliLoginGate.maybePromptOnStartup(context);
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _page.dispose();
    super.dispose();
  }

  Future<void> _restoreQuickState() async {
    final storage = await SharedPreferences.getInstance();
    final value = storage.getBool(_kQuick);
    if (value != null && mounted) setState(() => _quickOpen = value);
  }

  Future<void> _toggleQuick() async {
    setState(() => _quickOpen = !_quickOpen);
    final storage = await SharedPreferences.getInstance();
    await storage.setBool(_kQuick, _quickOpen);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SearchView()),
          ),
          child: Container(
            padding: const EdgeInsets.only(right: 4),
            child: const TextField(
              enabled: false,
              decoration: InputDecoration(
                filled: true,
                fillColor: Color.fromARGB(255, 239, 240, 241),
                constraints: BoxConstraints(maxHeight: 35),
                border: UnderlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
                hintText: "搜索歌曲、UP主",
                hintStyle: TextStyle(fontSize: 12),
                contentPadding:
                    EdgeInsets.symmetric(vertical: 13.5, horizontal: 16),
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: _quickOpen ? "收起顶部" : "展开顶部",
            icon: Icon(
              _quickOpen
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: primaryColor,
            ),
            onPressed: _toggleQuick,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            // 可收起的账号卡
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: _quickOpen
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: _AccountCard(onChanged: () => setState(() {})),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 8),
            _TabHeader(controller: _tab),
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (i) => _tab.animateTo(i),
                children: const [
                  _HistoryTab(),
                  _OrdersTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「历史播放 / 我的歌单」切换头
class _TabHeader extends StatelessWidget {
  final TabController controller;
  const _TabHeader({required this.controller});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 238, 238, 238),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              _segment(context, 0, "历史播放", Icons.history, primaryColor),
              _segment(context, 1, "我的歌单", Icons.queue_music, primaryColor),
            ],
          ),
        );
      },
    );
  }

  Widget _segment(
    BuildContext context,
    int index,
    String label,
    IconData icon,
    Color primaryColor,
  ) {
    final selected = controller.index == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => controller.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? primaryColor : Colors.grey,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? primaryColor : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 账号 / 登录卡
class _AccountCard extends StatefulWidget {
  final VoidCallback onChanged;
  const _AccountCard({required this.onChanged});

  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  final BiliAuth auth = BiliAuth.instance;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return GestureDetector(
      onTap: () async {
        if (auth.isLogin) {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BiliAccountPage()),
          );
          if (mounted) setState(() {});
          widget.onChanged();
          return;
        }

        final go = await BiliLoginGate.showPrompSheet(context);
        if (!go) return;
        if (!context.mounted) return;
        final ok = await BiliLoginGate.openLoginPage(context);
        if (!context.mounted) return;
        if (ok) {
          BotToast.showText(text: "登录成功，音质已提升");
          setState(() {});
          widget.onChanged();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            if (auth.isLogin && auth.face.isNotEmpty)
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color.fromARGB(255, 240, 240, 240),
                backgroundImage: NetworkImage(auth.face),
              )
            else
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  auth.isLogin
                      ? Icons.person_outline
                      : Icons.high_quality_outlined,
                  size: 19,
                  color: primaryColor,
                ),
              ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auth.isLogin
                        ? (auth.uname.isEmpty ? "已登录哔哩哔哩" : auth.uname)
                        : "登录解锁高音质",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    auth.isLogin
                        ? (auth.vipStatus > 0
                            ? "大会员 · 音质已拉满"
                            : "已登录 · 高音质已开启")
                        : "不登录只能听最低音质",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                auth.isLogin ? "管理" : "去登录",
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 历史播放
class _HistoryTab extends StatefulWidget {
  const _HistoryTab();

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  StreamSubscription? _sub;
  StreamSubscription? _playerSub;

  @override
  void initState() {
    super.initState();
    PlayHistory.instance.init().then((_) {
      if (mounted) setState(() {});
    });
    _sub = PlayHistory.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
    // 播放器换歌时高亮跟着变
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

  @override
  Widget build(BuildContext context) {
    final entries = PlayHistory.instance.entries;
    final primaryColor = Theme.of(context).primaryColor;
    final player = Provider.of<PlayerModel>(context);

    if (entries.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 30),
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

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      itemCount: entries.length + 1,
      itemBuilder: (c, i) {
        if (i == entries.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Center(
              child: TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      content: const Text(
                        "清空所有播放记录？",
                        style: TextStyle(fontSize: 13),
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
                },
                child: const Text(
                  "清空播放记录",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            ),
          );
        }

        final e = entries[i];
        final isCurrent = player.current?.id == e.music.id;

        return GestureDetector(
          onTap: () => player.play(music: e.music),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
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
                          fontWeight:
                              isCurrent ? FontWeight.bold : FontWeight.normal,
                          color: isCurrent ? primaryColor : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        e.music.author.isEmpty
                            ? "未知 UP 主"
                            : clearHtmlTags(e.music.author),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (isCurrent)
                  Icon(Icons.graphic_eq, size: 15, color: primaryColor)
                else
                  Text(
                    _relativeTime(e.playedAt),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),
          ),
        );
      },
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

/// 我的歌单
class _OrdersTab extends StatefulWidget {
  const _OrdersTab();

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  @override
  Widget build(BuildContext context) {
    // MusicOrderView 已改成纵向列表（见 music_order.dart）
    return const MusicOrderView(embedded: true);
  }
}
