import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:isolate';
import 'dart:typed_data';

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
    final loading = _index ??= _loadFromAsset(assetPath);
    // 실패한 Future를 들고 있으면 다시는 못 읽으므로, 실패하면 다음 검색 때 다시 시도한다.
    loading.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_index, loading)) _index = null;
      },
    );
    return loading;
  }

  static Future<StoreIndex> _loadFromAsset(String assetPath) async {
    final bytes = await rootBundle.load(assetPath);
    final data = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    return _parseInBackground(data);
  }

  /// 백그라운드 isolate로 넘기는 클로저는 [data]만 잡아야 한다.
  /// async 함수 안에서 만들면 그 함수의 Future까지 잡혀서 "object is unsendable"로
  /// 실패한다. 그래서 async가 아닌 별도 함수에서 만든다.
  static Future<StoreIndex> _parseInBackground(Uint8List data) =>
      Isolate.run(() => StoreIndex.parse(utf8.decode(gzip.decode(data))));

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
