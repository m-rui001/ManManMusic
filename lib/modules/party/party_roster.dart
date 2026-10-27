import "dart:convert";
import "dart:math";

import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:shared_preferences/shared_preferences.dart";

/// 一起听名单里的一个人
class RosterMember {
  final int mid;
  final String uname;
  final String face;

  /// 点过红心 = 共管
  ///
  /// 共管可以在我听歌的时候直接换歌、拖进度；
  /// 没点红心的只能听，想自己操作必须先退出房间。
  final bool canControl;

  const RosterMember({
    required this.mid,
    required this.uname,
    required this.face,
    this.canControl = false,
  });

  RosterMember copyWith({
    String? uname,
    String? face,
    bool? canControl,
  }) {
    return RosterMember(
      mid: mid,
      uname: uname ?? this.uname,
      face: face ?? this.face,
      canControl: canControl ?? this.canControl,
    );
  }

  /// 房间号规则与 PartyTabView 保持一致
  String get roomId => "bili_$mid";

  Map<String, dynamic> toJson() => {
        "mid": mid,
        "uname": uname,
        "face": face,
        "canControl": canControl,
      };

  factory RosterMember.fromJson(Map<String, dynamic> json) {
    return RosterMember(
      mid: (json["mid"] is int) ? json["mid"] : int.tryParse("${json["mid"]}") ?? 0,
      uname: "${json["uname"] ?? ""}",
      face: "${json["face"] ?? ""}",
      canControl: json["canControl"] == true,
    );
  }
}

/// 一起听名单
///
/// 设计取向：
/// - 默认是**空的**，不把你关注的所有人都塞进来
/// - 只有你手动加进来的人才会显示、才会被探测
/// - 随时可以从「我关注的人」里导入，也可以单独移除
///
/// 原因：关注列表里大多数是 UP 主，真正会一起听歌的只有少数几个人，
/// 每次都对几十个人发探测请求既慢又没意义。
class PartyRoster {
  PartyRoster._();

  static final PartyRoster instance = PartyRoster._();

  static const String _kRoster = "manman_party_roster";

  List<RosterMember> _members = [];
  bool _inited = false;

  List<RosterMember> get members => List.unmodifiable(_members);

  int get length => _members.length;

  bool contains(int mid) => _members.any((e) => e.mid == mid);

  /// 允许进我房间的人
  List<int> get uids => _members.map((e) => e.mid).toList();

  /// 其中可以和我一起控制播放的人（点过红心）
  List<int> get controllerUids =>
      _members.where((e) => e.canControl).map((e) => e.mid).toList();

  /// 切换某个人的共管权限
  Future<void> setControl(int mid, bool value) async {
    final index = _members.indexWhere((e) => e.mid == mid);
    if (index < 0) return;
    _members[index] = _members[index].copyWith(canControl: value);
    await _save();
  }

  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    final storage = await SharedPreferences.getInstance();
    final raw = storage.getString(_kRoster);
    if (raw == null || raw.isEmpty) return;

    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      _members = list
          .whereType<Map>()
          .map((e) => RosterMember.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.mid > 0)
          .toList();
    } catch (_) {
      _members = [];
    }
  }

  Future<void> _save() async {
    final storage = await SharedPreferences.getInstance();
    await storage.setString(
      _kRoster,
      jsonEncode(_members.map((e) => e.toJson()).toList()),
    );
  }

  /// 加一个人（已在名单里就更新头像/昵称）
  Future<void> add(RosterMember member) async {
    if (member.mid <= 0) return;
    final index = _members.indexWhere((e) => e.mid == member.mid);
    if (index >= 0) {
      // 已在名单里：只更新昵称头像，别把红心（共管）冲掉
      _members[index] = _members[index]
          .copyWith(uname: member.uname, face: member.face);
    } else {
      _members.add(member);
    }
    await _save();
  }

  /// 批量加
  Future<void> addAll(Iterable<RosterMember> list) async {
    for (final m in list) {
      if (m.mid <= 0) continue;
      final index = _members.indexWhere((e) => e.mid == m.mid);
      if (index >= 0) {
        _members[index] =
            _members[index].copyWith(uname: m.uname, face: m.face);
      } else {
        _members.add(m);
      }
    }
    await _save();
  }

  Future<void> remove(int mid) async {
    _members.removeWhere((e) => e.mid == mid);
    await _save();
  }

  Future<void> clear() async {
    _members = [];
    await _save();
  }

  // ===== 自动上线开关 =====

  static const String _kAutoOnline = "manman_party_auto_online";

  /// 打开 App 是否自动上线
  ///
  /// **默认开启**；关掉后需要在「一起听」页手动点上线。
  static Future<bool> isAutoOnline() async {
    final storage = await SharedPreferences.getInstance();
    return storage.getBool(_kAutoOnline) ?? true;
  }

  static Future<void> setAutoOnline(bool value) async {
    final storage = await SharedPreferences.getInstance();
    await storage.setBool(_kAutoOnline, value);
  }
}

/// 自己的房间号
///
/// 登录后用 B 站 UID 派生（好友按 UID 就能找到你），
/// 未登录用本地持久化的随机 id。
Future<String> selfPartyRoomId() async {
  final auth = BiliAuth.instance;
  if (auth.isLogin && auth.mid > 0) return "bili_${auth.mid}";

  const key = "manman_party_self_id";
  final storage = await SharedPreferences.getInstance();
  var id = storage.getString(key);
  if (id == null || id.isEmpty) {
    final rnd = Random.secure();
    id = "u${rnd.nextInt(89999999) + 10000000}";
    await storage.setString(key, id);
  }
  return id;
}

/// 自己的显示昵称
String selfPartyName() {
  final auth = BiliAuth.instance;
  if (auth.isLogin && auth.uname.isNotEmpty) return auth.uname;
  return "我";
}
