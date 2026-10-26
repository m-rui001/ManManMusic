import "package:bobomusic/components/title_area/title_area.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/modules/music_plaza/components/detail.dart";
import "package:bobomusic/modules/music_plaza/components/singer_item.dart";
import "package:bobomusic/modules/music_plaza/pages/singer_list.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/read_data_from_json.dart";
import "package:flutter/material.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";
import "package:path/path.dart" as path;
import "package:uuid/uuid.dart";

const uuid = Uuid();
final DBOrder db = DBOrder();

class SingerRow extends StatefulWidget {
  const SingerRow({super.key});

  @override
  State<SingerRow> createState() => SingerRowViewState();
}

class SingerRowViewState extends State<SingerRow> {
  List<Widget> singerList = [];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSingerList();
    });
  }

  Future<void> _loadSingerList() async {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width - 40;
    final jsonData = await readDataFromJson(filePath: path.join("assets", "chinese.json"));
    List<MusicOrderItem> list = [];
    list = jsonData.map((item) {
      return MusicOrderItem.fromJson(item as Map<String, dynamic>);
    }).toList();
    EasyLoading.show(maskType: EasyLoadingMaskType.black);

    for (var order in list) {
      if (!await db.isTableExists(order.name)) {
        await db.createOrderTable(order.name);

        for (var music in order.musicList) {
          final newM = music.copyWith(playId: music.playId.isEmpty ? uuid.v4() : music.playId, orderName: order.name);
          await db.insert(order.name, musicItem2Row(music: newM));
        }
      }
    }

    EasyLoading.dismiss();

    final itemCounts = screenWidth ~/ 60;
    list = list.sublist(0, itemCounts > list.length ? list.length : itemCounts);
    List<Widget> singerViewList = [];

    for (var it in list) {
      singerViewList.add(
        SingerItem(
          imageUrl: it.cover!,
          name: it.name,
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (BuildContext context) {
                return MusicOrderDetail(
                  musicOrderItem: it,
                  shouldLoadData: true,
                );
              },
            ));
          },
        )
      );
    }

    setState(() {
      singerList = singerViewList;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TitleAreaView(title: "热门歌手", onTapNextPage: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (BuildContext context) {
                  return const SingerList();
                },
              ),
            );
          }),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: singerList
          ),
        ],
      )
    );
  }
}
