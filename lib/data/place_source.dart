import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:isolate';

import 'package:flutter/services.dart' show rootBundle;

import '../core/geo.dart';
import '../models/store.dart';
import '../models/store_category.dart';
import 'store_index.dart';

/// 주변 매장을 찾아주는 출처.
abstract interface class PlaceSource {
  Future<List<Store>> nearby({
    required LatLng center,
    required StoreCategory category,
    required int radiusMeters,
  });
}

/// 앱에 내장된 전국 매장 데이터(소상공인시장진흥공단 상가정보)에서 찾는다.
///
/// 네트워크, API 키, 호출 한도가 필요 없다. 데이터는 처음 검색할 때 한 번만
/// 백그라운드 isolate에서 읽는다. 데이터 갱신은 tool/build_store_data.py 참고.
class OfflinePlaceSource implements PlaceSource {
  OfflinePlaceSource({this.assetPath = 'assets/stores.tsv.gz'});

  final String assetPath;
  Future<StoreIndex>? _index;

  Future<StoreIndex> _load() {
    return _index ??= () async {
      final bytes = await rootBundle.load(assetPath);
      final data = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      return Isolate.run(
        () => StoreIndex.parse(utf8.decode(gzip.decode(data))),
      );
    }();
  }

  @override
  Future<List<Store>> nearby({
    required LatLng center,
    required StoreCategory category,
    required int radiusMeters,
  }) async {
    final index = await _load();
    return index.nearby(
      center: center,
      category: category,
      radiusMeters: radiusMeters.toDouble(),
    );
  }
}
