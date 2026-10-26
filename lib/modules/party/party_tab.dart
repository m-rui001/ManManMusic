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
/// 规则（也是这一页要讲清楚的事）：
/// - 我上线 = 开着我的房间，只有「一起听名单」里的人能进来
/// - 名单里点过红心的人 = 共管，可以和我一起换歌、拖进度
/// - 其他人进来只能听，想自己点歌得先退出房间
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
  StreamSubscription<void>? _changeSub;

  Map<int, PartyProbe?> probes = {};
  bool _busy = false;
  bool _probing = false;

  @override
  void initState() {
    super.initState();

    _memberSub = session.memberStream.listen((_) {
      if (mounted) setState(() {});
    });

    _changeSub = session.changes.listen((_) {
      if (mounted) setState(() {});
    });

    roster.init().then((_) async {
      if (!mounted) return;
      setState(() {});
      await _probeAll();
    });
  }

  @override
  void dispose() {
    _memberSub?.cancel();
    _changeSub?.cancel();
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
      if (!auth.isLogin) {
        final ok = await BiliLoginGate.ensureLoggedIn(context);
        if (!ok) {
          if (mounted) setState(() => _busy = false);
          return;
        }
      }
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

    if (!auth.isLogin) {
      final ok = await BiliLoginGate.ensureLoggedIn(context);
      if (!ok || !mounted) return;
    }

    setState(() => _busy = true);
    final ok = await session.join(member.roomId);
    if (!mounted) return;
    setState(() => _busy = false);

    BotToast.showText(
      text: ok ? "已加入 ${member.uname} 的一起听" : "加入失败，请检查网络",
    );
  }

  Future<void> _toggleControl(RosterMember member) async {
    await roster.setControl(member.mid, !member.canControl);
    session.refreshPermissions();

    if (!mounted) return;
    setState(() {});

    BotToast.showText(
      text: member.canControl
          ? "已取消 ${member.uname} 的共管权限"
          : "${member.uname} 现在可以和你一起换歌了",
    );
  }

  Future<void> _removeFromRoster(RosterMember member) async {
    await roster.remove(member.mid);
    session.refreshPermissions();

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
      session.refreshPermissions();
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
                  isGuest: session.isGuest,
                  onToggleOnline: _busy ? () {} : _toggleOnline,
                ),
                if (!auth.isLogin) ...[
                  const SizedBox(height: 12),
                  _loginHint(primaryColor),
                ],
                if (session.isGuest) ...[
                  const SizedBox(height: 12),
                  _guestCard(primaryColor),
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
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 10),
                  child: Text(
                    "名单里的人才能进你的房间；点红心的人可以和你一起换歌、拖进度。",
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1.6,
                      color: Colors.grey[500],
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
                      onToggleControl: () => _toggleControl(m),
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

  /// 作为听众在别人房间里的状态卡
  Widget _guestCard(Color primaryColor) {
    final locked = session.isLocked;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: locked
            ? const Color.fromARGB(255, 255, 247, 230)
            : primaryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            locked ? Icons.lock_outline : Icons.graphic_eq,
            size: 16,
            color: locked ? const Color(0xFFB8860B) : primaryColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              locked
                  ? "正在跟房主一起听：只能听，想自己点歌请先退出"
                  : "你在这个房间有共管权限，可以一起换歌、拖进度",
              style: TextStyle(
                fontSize: 10,
                height: 1.6,
                color: locked ? const Color(0xFFB8860B) : primaryColor,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              await session.leave();
              if (mounted) setState(() {});
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
            ),
            child: const Text("退出", style: TextStyle(fontSize: 11)),
          ),
        ],
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
            "没加进来的人进不了你的房间，列表也不会乱。",
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
              "登录后好友才能按 UID 找到你，也才能认出谁在名单里。",
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
