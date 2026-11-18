import "package:bobomusic/constants/app_info.dart";

class Covers {
  static String getLocalCover() {
    return Covers.local[0];
  }

  static const local = [appLogoAsset];
}
