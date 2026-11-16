import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 물건 사진을 앱 전용 폴더에 보관한다.
///
/// iOS는 앱을 업데이트하면 앱 폴더의 절대 경로가 바뀌므로,
/// 물건에는 파일 이름만 저장하고 경로는 쓸 때마다 다시 계산한다.
class PhotoStore {
  PhotoStore(this._dir);

  final Directory _dir;
  static const _uuid = Uuid();

  static Future<PhotoStore> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/photos');
    await dir.create(recursive: true);
    return PhotoStore(dir);
  }

  /// 카메라나 앨범에서 고른 임시 파일을 복사해 두고 파일 이름을 돌려준다.
  Future<String> save(String sourcePath) async {
    final ext = sourcePath.contains('.')
        ? sourcePath.substring(sourcePath.lastIndexOf('.'))
        : '.jpg';
    final name = '${_uuid.v4()}$ext';
    await File(sourcePath).copy(fileOf(name).path);
    return name;
  }

  File fileOf(String name) => File('${_dir.path}/$name');

  /// 알림에 붙일 사본을 만든다. iOS는 알림에 붙인 파일을 가져가 버리기 때문이다.
  Future<String?> notificationCopy(String name) async {
    final file = fileOf(name);
    if (!await file.exists()) return null;
    final tmp = await getTemporaryDirectory();
    final copy = await file.copy('${tmp.path}/notif_$name');
    return copy.path;
  }

  Future<void> delete(String name) async {
    final file = fileOf(name);
    if (await file.exists()) await file.delete();
  }
}
