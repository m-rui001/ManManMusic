import "dart:async";

import "package:bobomusic/modules/bili_account/bili_login_gate.dart";
import "package:bobomusic/modules/party/party_page.dart";
import "package:bobomusic/modules/party/party_pick_page.dart";
import "package:bobomusic/modules/party/party_roster.dart";
import "package:bobomusic/modules/party/party_service.dart";
import "package:bobomusic/modules/party/party_widgets.dart";
import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";

/// 「一起听」底部栏页面
///
/// 上线策略：
/// - 默认打开 App 就自动上线（设置里可以关掉）
/// - 关掉之后这里会显示「上线」按钮，手动控制
///
/// 名单策略：
/// - 一开始是空的，不把你关注的所有人都塞进来
/// - 点「选择」从关注列表里挑人，也可以单独移除
class PartyTabView extends StatefulWidget {
  const PartyTabView({super.key});

  @override
  State<PartyTabView> createState() => PartyTabViewState();
}

class PartyTabViewState extends State<PartyTabView> {
  final PartySession session = PartySession.instance;
  final BiliAuth auth = BiliAuth.instance;
  final PartyRoster roster = PartyRoster.instance;

  StreamSubscription<Map<String, String>>? _memberSub;

  Map<int, PartyProbe?> probes = {};
  bool _busy = false;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _memberSub = session.memberStream.listen((_) {
      if (mounted) setState(() {});
    });

    roster.init().then((_) async {
      if (!mounted) return;
      setState(() {});
      // 上线与否完全由启动逻辑 + 用户手动操作决定，这里只负责探测
      await _probeAll();
    });
  }

  @override
  void dispose() {
    _memberSub?.cancel();
    super.dispose();
  }

  String get _myName {
    if (auth.isLogin && auth.uname.isNotEmpty) return auth.uname;
    return "我";
  }

  Future<void> _toggleOnline() async {
    setState(() => _busy = true);
    if (session.inRoom) {
      await session.goOffline();
    } else {
      await session.goOnline();
    }
    if (!mounted) return;
    setState(() => _busy = false);
  }

  /// 只探测名单里的人
  Future<void> _probeAll() async {
    if (roster.members.isEmpty) {
      if (mounted) setState(() => probes = {});
      return;
    }

    setState(() => _probing = true);

    final result = <int, PartyProbe?>{};
    await Future.wait(
      roster.members.map((m) async {
        final probe = await PartyService.instance.probeRoom(m.roomId);
        result[m.mid] = (probe != null && probe.isFresh) ? probe : null;
      }),
    );

    if (!mounted) return;
    setState(() {
      probes = result;
      _probing = false;
    });
  }

  Future<void> _join(RosterMember member) async {
    final probe = probes[member.mid];
    if (probe == null) {
      BotToast.showText(text: "${member.uname} 现在没在听歌");
      return;
    }

    setState(() => _busy = true);
    final ok = await PartyService.instance.joinRoom(
      id: member.roomId,
      name: _myName,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      BotToast.showText(text: "已加入 ${member.uname} 的一起听");
    } else {
      BotToast.showText(text: "加入失败，请检查网络");
    }
  }

  Future<void> _removeFromRoster(RosterMember member) async {
    await roster.remove(member.mid);
    if (!mounted) return;
    setState(() => probes.remove(member.mid));
    BotToast.showText(text: "已从名单移除 ${member.uname}");
  }

  Future<void> _pickPeople() async {
    if (!auth.isLogin) {
      final ok = await BiliLoginGate.ensureLoggedIn(context);
      if (!ok || !mounted) return;
      setState(() {});
    }

    if (!mounted) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PartyPickPage()),
    );

    if (changed == true && mounted) {
      setState(() {});
      await _probeAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final members = roster.members;
    final listeningCount = probes.values.where((e) => e != null).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("一起听", style: TextStyle(fontSize: 17)),
        actions: [
          IconButton(
            tooltip: "刷新",
            icon: Icon(Icons.refresh, size: 20, color: primaryColor),
            onPressed: _probing
                ? null
                : () async {
                    await _probeAll();
                  },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: Container(
          color: const Color.fromARGB(255, 245, 245, 245),
          child: RefreshIndicator(
            onRefresh: _probeAll,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                PartySelfCard(
                  nick: _myName,
                  face: auth.isLogin ? auth.face : "",
                  inRoom: session.inRoom,
                  connected: session.connected,
                  roomId: session.roomId,
                  isLogin: auth.isLogin,
                  onToggleOnline: _busy ? () {} : _toggleOnline,
                ),
                if (!auth.isLogin) ...[
                  const SizedBox(height: 12),
                  _loginHint(primaryColor),
                ],
                const SizedBox(height: 18),
                PartySectionTitle(
                  title: "一起听名单",
                  trailingText: members.isEmpty
                      ? null
                      : (listeningCount > 0
                          ? "$listeningCount 人在听"
                          : "${members.length} 人"),
                  action: TextButton(
                    onPressed: _pickPeople,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                    ),
                    child: Text(
                      members.isEmpty ? "添加" : "选择",
                      style: TextStyle(fontSize: 11, color: primaryColor),
                    ),
                  ),
                ),
                if (members.isEmpty)
                  _emptyRoster(primaryColor)
                else
                  ...members.map(
                    (m) => PartyRosterTile(
                      member: m,
                      probe: probes[m.mid],
                      onTap: _busy ? () {} : () => _join(m),
                      onRemove: () => _removeFromRoster(m),
                    ),
                  ),
                const SizedBox(height: 18),
                PartySectionTitle(
                  title: "房间里的人",
                  trailingText:
                      "${session.members.length + (session.inRoom ? 1 : 0)} 人",
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: PartyMemberChips(
                    myName: _myName,
                    myFace: auth.isLogin ? auth.face : "",
                    inRoom: session.inRoom,
                    members: session.members,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyRoster(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(Icons.group_add_outlined, size: 34, color: Colors.grey[350]),
          const SizedBox(height: 10),
          const Text(
            "名单还是空的",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          const Text(
            "从你关注的人里挑几个真正会一起听歌的。"
            "没加进来的人不会被探测，列表也不会乱。",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.6),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(19),
                ),
              ),
              onPressed: _pickPeople,
              child: const Text("从关注列表添加", style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginHint(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 255, 247, 230),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lightbulb_outline,
            size: 15,
            color: Color(0xFFB8860B),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "登录后好友才能按 UID 找到你，也才能从关注列表挑人。",
              style: TextStyle(
                fontSize: 10,
                color: Color(0xFFB8860B),
                height: 1.6,
              ),
            ),
          ),
          TextButton(
            onPressed: _pickPeople,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
            ),
            child: Text(
              "去登录",
              style: TextStyle(fontSize: 11, color: primaryColor),
            ),
          ),
        ],
      ),
    );
  }
}
