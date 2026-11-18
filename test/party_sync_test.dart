import "dart:async";
import "dart:convert";
import "dart:io";

import "package:bobomusic/modules/party/party_service.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  late HttpServer relay;
  late PartyService host;
  late PartyService guest;
  final listeners = <StreamController<List<int>>>[];

  const room = "bili_100";
  final music = MusicItem(
    id: "2_BV1_3",
    origin: OriginType.bili,
    name: "第二首",
    author: "房主",
    cover: "",
    duration: 120,
  );

  setUp(() async {
    relay = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    relay.listen((request) async {
      final response = request.response;
      response.headers.contentType = ContentType.json;
      if (request.method == "GET") {
        response.bufferOutput = false;
        final stream = StreamController<List<int>>();
        listeners.add(stream);
        stream.add(utf8.encode('{"event":"open"}\n'));
        try {
          await response.addStream(stream.stream);
          await response.close();
        } on HttpException {
          // The subscription closed during a reconnect.
        } finally {
          listeners.remove(stream);
        }
        return;
      }
      final message = await utf8.decoder.bind(request).join();
      final line = jsonEncode({"event": "message", "message": message});
      for (final listener in listeners) {
        listener.add(utf8.encode("$line\n"));
      }
      response.write("{}");
      await response.close();
    });
    final base = "http://127.0.0.1:${relay.port}";
    host = PartyService.withRelay(base, 100);
    guest = PartyService.withRelay(base, 200);
  });

  tearDown(() async {
    await guest.leaveRoom(silent: true);
    await host.leaveRoom(silent: true);
    guest.dispose();
    host.dispose();
    for (final listener in listeners.toList()) {
      unawaited(listener.close());
    }
    listeners.clear();
    await relay.close(force: true);
  });

  test("加入时收到暂停状态和进度，重连后重新同步", () async {
    var position = const Duration(seconds: 34);
    host.onSyncRequested = ({String toClient = "", int toUid = 0}) {
      host.broadcast(
        music: music,
        position: position,
        toClient: toClient,
        toUid: toUid,
      );
    };
    expect(await host.createRoom(name: "房主", id: room, allowed: [200]), isTrue);
    final first = guest.states.first;
    expect(await guest.joinRoom(id: room, name: "听众"), isTrue);
    final snapshot = await first;
    expect(snapshot.name, "第二首");
    expect(snapshot.toClient, guest.myId);
    expect(snapshot.playing, isFalse);
    expect(snapshot.positionAt(snapshot.receivedAt + 4000), position);
    expect(guest.allowLocalControl, isFalse);

    position = const Duration(seconds: 57);
    final refreshed = guest.states.first;
    expect(await guest.retryNow(), isTrue);
    expect((await refreshed).position, position.inMilliseconds);
    expect(guest.admitted, isTrue);
  });

  test("房主在线时名单外的听众仍不能加入", () async {
    expect(await host.createRoom(name: "房主", id: room), isTrue);
    host.broadcast(music: music, playing: true);
    expect(await guest.joinRoom(id: room, name: "听众"), isFalse);
    expect(guest.admitted, isFalse);
    expect(guest.inRoom, isFalse);
    expect(guest.joinHint, contains("名单"));
  });

  test("播放中补偿本机取流耗时并限制在歌曲时长内", () {
    const state = PartyState(
      type: PartyMessageType.state,
      roomId: room,
      from: "host",
      at: 8000000,
      receivedAt: 1000,
      position: 30000,
      playing: true,
    );
    expect(state.positionAt(4000), const Duration(seconds: 33));
    expect(
      state.positionAt(4000, duration: const Duration(seconds: 32)),
      const Duration(seconds: 32),
    );
  });
}
