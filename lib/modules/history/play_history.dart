import "dart:async";
import "dart:convert";

import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:shared_preferences/shared_preferences.dart";

/// 历史播放记录（纯本地，不需要服务器）
///
/// 只记录真正开始播放的歌，同 [playId] 或同 [id] 视为同一首，
/// 重复播放会把记录提到最前，而不是堆一堆重复项。
class PlayHistory {
  PlayHistory._();

  static final PlayHistory instance = PlayHistory._();

  static const String _key = "manman_play_history";
  static const int _maxCount = 100;

  List<HistoryEntry> _entries = [];
  bool _inited = false;

  /// 当前内存中的历史（越靠前越新）
  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// 历史变化时触发，页面可以监听刷新
  Stream<void> get changes => _changes.stream;

  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    final storage = await SharedPreferences.getInstance();
    final raw = storage.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        _entries = list
            .whereType<Map>()
            .map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.music.id.isNotEmpty)
            .toList();
      }
    } catch (_) {
      _entries = [];
    }
  }

  /// 记一首歌。播放器每次真正开始播放时调用。
  Future<void> record(MusicItem music) async {
    if (music.id.isEmpty) return;

    final same = _entries.indexWhere(
      (e) => e.music.id == music.id && e.music.playId == music.playId,
    );

    final entry = HistoryEntry(
      music: music,
      playedAt: DateTime.now(),
      count: same >= 0 ? _entries[same].count + 1 : 1,
    );

    if (same >= 0) {
      _entries.removeAt(same);
    }
    _entries.insert(0, entry);

    if (_entries.length > _maxCount) {
      _entries = _entries.sublist(0, _maxCount);
    }

    _changes.add(null);
    await _persist();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _entries.length) return;
    _entries.removeAt(index);
    _changes.add(null);
    await _persist();
  }

  Future<void> clear() async {
    _entries = [];
    _changes.add(null);
    await _persist();
  }

  Future<void> _persist() async {
    final storage = await SharedPreferences.getInstance();
    await storage.setString(
      _key,
      jsonEncode(_entries.map((e) => e.toJson()).toList()),
    );
  }
}

/// 一条历史记录
class HistoryEntry {
  final MusicItem music;
  final DateTime playedAt;

  /// 播放次数
  final int count;

  const HistoryEntry({
    required this.music,
    required this.playedAt,
    this.count = 1,
  });

  Map<String, dynamic> toJson() {
    return {
      "music": {
        "id": music.id,
        "name": music.name,
        "cover": music.cover,
        "duration": music.duration,
        "author": music.author,
        "origin": music.origin.value,
        "playId": music.playId,
        "orderName": music.orderName,
      },
      "at": playedAt.millisecondsSinceEpoch,
      "count": count,
    };
  }

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    final m = json["music"];
    final map = m is Map ? Map<String, dynamic>.from(m) : <String, dynamic>{};
    return HistoryEntry(
      music: MusicItem(
        id: "${map["id"] ?? ""}",
        name: "${map["name"] ?? ""}",
        cover: "${map["cover"] ?? ""}",
        duration: (map["duration"] is int) ? map["duration"] : 0,
        author: "${map["author"] ?? ""}",
        origin: OriginType.values.firstWhere(
          (e) => e.value == "${map["origin"] ?? ""}",
          orElse: () => OriginType.bili,
        ),
        playId: "${map["playId"] ?? ""}",
        orderName: "${map["orderName"] ?? ""}",
      ),
      playedAt: DateTime.fromMillisecondsSinceEpoch(
        (json["at"] is int) ? json["at"] : 0,
      ),
      count: (json["count"] is int) ? json["count"] : 1,
    );
  }
}
