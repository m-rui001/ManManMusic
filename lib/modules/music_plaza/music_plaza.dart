import "package:bobomusic/modules/bili_account/bili_login_gate.dart";
import "package:bobomusic/modules/history/history_tab.dart";
import "package:bobomusic/modules/music_order/music_order.dart";
import "package:bobomusic/modules/music_plaza/search/search.dart";
import "package:flutter/material.dart";


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

  late final TabController _tab;
  final PageController _page = PageController();

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
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 20, color: primaryColor),
                const SizedBox(width: 9),
                Text(
                  "搜索歌曲、UP主",
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            const SizedBox(height: 8),
            _TabHeader(controller: _tab),
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (i) => _tab.animateTo(i),
                children: const [
                  HistoryTab(),
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

/// 历史播放
/// 我的歌单
class _OrdersTab extends StatefulWidget {
  const _OrdersTab();

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // MusicOrderView 已改成纵向列表（见 music_order.dart）
    // 保留状态：切走再切回来不用重新加载，靠 RefreshMusicList 事件刷新
    return const MusicOrderView(embedded: true);
  }
}
