import "dart:async";
import "dart:math";

import "package:bobomusic/modules/bili_account/bili_login_gate.dart";
import "package:bobomusic/modules/party/party_page.dart";
import "package:bobomusic/modules/party/party_service.dart";
import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

/// 「一起听」底部栏页面
///
/// 设计取向：
/// - 不需要手动建房、不需要输房间号：进页面就自动用自己的房间号上线
/// - 房间号由 B 站 UID 派生（bili_<mid>），好友知道你的 UID 就能找到你
/// - 列出「我关注的人」，谁在听什么一眼可见，点一下就加入
class PartyTabView extends StatefulWidget {
  const PartyTabView({super.key});

  @override
  State<PartyTabView> createState() => PartyTabViewState();
}

class PartyTabViewState extends State<PartyTabView> {
  final PartySession session = PartySession.instance;
  final BiliAuth auth = BiliAuth.instance;

  static const String _kSelfId = "manman_party_self_id";

  StreamSubscription<Map<String, String>>? _memberSub;

  List<BiliFriend> friends = [];
  bool loadingFriends = false;
  String? friendError;

  Map<int, PartyProbe?> probes = {};

  bool _autoStarted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _memberSub = session.memberStream.listen((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _memberSub?.cancel();
    super.dispose();
  }

  /// 自己的房间号：登录后用 UID 派生，未登录用本地随机 id
  Future<String> _selfRoomId() async {
    if (auth.isLogin && auth.mid > 0) return "bili_${auth.mid}";

    final storage = await SharedPreferences.getInstance();
    var id = storage.getString(_kSelfId);
    if (id == null || id.isEmpty) {
      final rnd = Random.secure();
      id = "u${rnd.nextInt(89999999) + 10000000}";
      await storage.setString(_kSelfId, id);
    }
    return id;
  }

  String get _myName {
    if (auth.isLogin && auth.uname.isNotEmpty) return auth.uname;
    return "我";
  }

  Future<void> _bootstrap() async {
    if (_autoStarted) return;
    _autoStarted = true;

    final id = await _selfRoomId();
    if (!mounted) return;

    if (!session.inRoom || session.roomId != id) {
      final ok = await PartyService.instance.createRoom(name: _myName, id: id);
      if (ok) session.startBroadcasting();
    }

    if (!mounted) return;
    setState(() {});

    if (auth.isLogin) await _loadFriends();
  }

  Future<void> _loadFriends() async {
    if (!auth.isLogin) return;
    setState(() {
      loadingFriends = true;
      friendError = null;
    });

    try {
      final list = await auth.fetchFriends(pageSize: 20);
      if (!mounted) return;
      setState(() {
        friends = list;
        loadingFriends = false;
      });
      await _probeAll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingFriends = false;
        friendError = "获取关注列表失败，稍后再试";
      });
    }
  }

  /// 并发探测好友房间（一次，不做定时轮询）
  Future<void> _probeAll() async {
    if (friends.isEmpty) return;

    final result = <int, PartyProbe?>{};
    await Future.wait(
      friends.map((f) async {
        final probe = await PartyService.instance.probeRoom(f.roomId);
        result[f.mid] = (probe != null && probe.isFresh) ? probe : null;
      }),
    );

    if (!mounted) return;
    setState(() => probes = result);
  }

  Future<void> _joinFriend(BiliFriend friend) async {
    final probe = probes[friend.mid];
    if (probe == null) {
      BotToast.showText(text: "${friend.uname} 现在没在听歌");
      return;
    }

    setState(() => _busy = true);
    final ok = await PartyService.instance.joinRoom(
      id: friend.roomId,
      name: _myName,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      BotToast.showText(text: "已加入 ${friend.uname} 的一起听");
      setState(() {});
    } else {
      BotToast.showText(text: "加入失败，请检查网络");
    }
  }

  Future<void> _leave() async {
    await session.leave();
    if (!mounted) return;
    _autoStarted = false;
    setState(() {});
  }

  Future<void> _relogin() async {
    final ok = await BiliLoginGate.ensureLoggedIn(context);
    if (!ok || !mounted) return;
    setState(() {});
    await _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text("一起听", style: TextStyle(fontSize: 17)),
        actions: [
          IconButton(
            tooltip: "刷新",
            icon: Icon(Icons.refresh, size: 20, color: primaryColor),
            onPressed: () async {
              if (auth.isLogin && friends.isEmpty) {
                await _loadFriends();
              } else {
                await _probeAll();
              }
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
            onRefresh: () async {
              if (auth.isLogin) {
                await _loadFriends();
              } else {
                await _probeAll();
              }
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                _buildSelfCard(primaryColor),
                const SizedBox(height: 18),
                if (!auth.isLogin)
                  _buildLoginHint(primaryColor)
                else
                  _buildFriendSection(primaryColor),
                const SizedBox(height: 18),
                _buildMembersCard(primaryColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelfCard(Color primaryColor) {
    final inRoom = session.inRoom;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (auth.isLogin && auth.face.isNotEmpty)
                CircleAvatar(
                  radius: 21,
                  backgroundColor: const Color.fromARGB(255, 240, 240, 240),
                  backgroundImage: NetworkImage(auth.face),
                )
              else
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child:
                      Icon(Icons.person_outline, size: 21, color: primaryColor),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _myName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: inRoom && session.connected
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          inRoom
                              ? (session.connected ? "正在分享你的收听" : "连接中…")
                              : "未上线",
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (inRoom)
                TextButton(
                  onPressed: _leave,
                  child: const Text(
                    "下线",
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 248, 248, 248),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.tag, size: 14, color: primaryColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    inRoom ? session.roomId : "准备中…",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Text(
                  auth.isLogin ? "好友按 UID 就能找到你" : "登录后好友才能找到你",
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginHint(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 34, color: Colors.grey[350]),
          const SizedBox(height: 10),
          const Text(
            "登录后能看到好友在听什么",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          const Text(
            "用哔哩哔哩账号登录，就能在这里看到你关注的人正在听哪首歌，点一下就能一起听。",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.6),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: _relogin,
              child: const Text("去登录", style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendSection(Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Row(
            children: [
              Text(
                "我关注的人",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 6),
              if (friends.isNotEmpty)
                Text(
                  "${probes.values.where((e) => e != null).length} 人在听",
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
            ],
          ),
        ),
        if (loadingFriends)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 26),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (friendError != null)
          _buildEmptyHint(friendError!)
        else if (friends.isEmpty)
          _buildEmptyHint("还没有关注任何人，去 B 站关注几个 UP 主吧")
        else
          ...friends.map((f) => _buildFriendTile(f, primaryColor)),
      ],
    );
  }

  Widget _buildEmptyHint(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: Colors.grey, height: 1.6),
      ),
    );
  }

  Widget _buildFriendTile(BiliFriend friend, Color primaryColor) {
    final probe = probes[friend.mid];
    final listening = probe != null;

    return GestureDetector(
      onTap: _busy ? null : () => _joinFriend(friend),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: listening
              ? Border.all(
                  color: primaryColor.withValues(alpha: 0.25),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Opacity(
                  opacity: listening ? 1 : 0.45,
                  child: CircleAvatar(
                    radius: 21,
                    backgroundColor: const Color.fromARGB(255, 240, 240, 240),
                    backgroundImage:
                        friend.face.isNotEmpty ? NetworkImage(friend.face) : null,
                    child: friend.face.isEmpty
                        ? Icon(Icons.person, size: 20, color: Colors.grey[400])
                        : null,
                  ),
                ),
                if (listening)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend.uname.isEmpty ? "未知用户" : friend.uname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          listening ? FontWeight.bold : FontWeight.normal,
                      color: listening ? Colors.black87 : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    listening
                        ? "正在听《${clearHtmlTags(probe.musicName)}》"
                        : "没在听歌",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: listening ? primaryColor : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (listening)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  "一起听",
                  style: TextStyle(fontSize: 10, color: Colors.white),
                ),
              )
            else
              Icon(
                Icons.headphones_outlined,
                size: 16,
                color: Colors.grey[350],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersCard(Color primaryColor) {
    final members = session.members;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Text(
            "房间里的人（${members.length + (session.inRoom ? 1 : 0)}）",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: members.isEmpty && !session.inRoom
              ? const Text(
                  "还没上线，稍等一下",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                )
              : Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (session.inRoom)
                      _memberChip(
                        name: "$_myName（我）",
                        face: auth.face,
                        primaryColor: primaryColor,
                        highlight: true,
                      ),
                    ...members.values.map(
                      (name) => _memberChip(
                        name: name,
                        face: "",
                        primaryColor: primaryColor,
                        highlight: false,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _memberChip({
    required String name,
    required String face,
    required Color primaryColor,
    required bool highlight,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight
            ? primaryColor.withValues(alpha: 0.08)
            : const Color.fromARGB(255, 245, 245, 245),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 9,
            backgroundColor: const Color.fromARGB(255, 235, 235, 235),
            backgroundImage: face.isNotEmpty ? NetworkImage(face) : null,
            child: face.isEmpty
                ? Icon(Icons.person, size: 10, color: Colors.grey[400])
                : null,
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(
              fontSize: 11,
              color: highlight ? primaryColor : Colors.black87,
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
