import 'dart:math' as math;
import 'dart:typed_data';

import '../core/geo.dart';
import '../models/store.dart';
import '../models/store_category.dart';

/// 전국 매장 데이터를 격자(약 1km 칸)로 나눠 두고 주변 매장을 빠르게 찾는다.
///
/// 16만 개 매장을 Store 객체로 다 만들면 메모리를 많이 쓰므로,
/// 좌표와 종류는 숫자 배열로 들고 있다가 검색된 것만 Store로 만든다.
class StoreIndex {
  StoreIndex._(this._lat, this._lng, this._category, this._names, this._grid);

  /// 격자 한 칸 크기(도). 위도 0.01도 ≈ 1.1km.
  static const _cell = 0.01;

  final Int32List _lat; // 위도 x 100000
  final Int32List _lng; // 경도 x 100000
  final Uint8List _category;
  final List<String> _names;
  final Map<int, Int32List> _grid;

  int get length => _names.length;

  /// `카테고리\t위도x1e5\t경도x1e5\t이름` 형식의 텍스트를 읽는다.
  /// 모르는 카테고리나 깨진 줄은 건너뛴다.
  factory StoreIndex.parse(String tsv) {
    final lat = <int>[];
    final lng = <int>[];
    final category = <int>[];
    final names = <String>[];
    final byName = {for (final c in StoreCategory.values) c.name: c.index};

    var start = 0;
    while (start < tsv.length) {
      var end = tsv.indexOf('\n', start);
      if (end < 0) end = tsv.length;
      final parts = tsv.substring(start, end).split('\t');
      start = end + 1;
      if (parts.length < 4) continue;
      final c = byName[parts[0]];
      final la = int.tryParse(parts[1]);
      final ln = int.tryParse(parts[2]);
      if (c == null || la == null || ln == null) continue;
      category.add(c);
      lat.add(la);
      lng.add(ln);
      names.add(parts[3]);
    }

    final cells = <int, List<int>>{};
    for (var i = 0; i < names.length; i++) {
      cells
          .putIfAbsent(_key(_cellOf(lat[i]), _cellOf(lng[i])), () => [])
          .add(i);
    }

    return StoreIndex._(
      Int32List.fromList(lat),
      Int32List.fromList(lng),
      Uint8List.fromList(category),
      names,
      {for (final e in cells.entries) e.key: Int32List.fromList(e.value)},
    );
  }

  List<Store> nearby({
    required LatLng center,
    required StoreCategory category,
    required double radiusMeters,
  }) {
    // 경도 1도의 거리는 위도에 따라 줄어든다.
    final latSpan = radiusMeters / 111195;
    final lngSpan =
        radiusMeters /
        (111195 * math.cos(center.latitude * math.pi / 180)).abs();
    final minLat = _cellOf(((center.latitude - latSpan) * 1e5).floor());
    final maxLat = _cellOf(((center.latitude + latSpan) * 1e5).ceil());
    final minLng = _cellOf(((center.longitude - lngSpan) * 1e5).floor());
    final maxLng = _cellOf(((center.longitude + lngSpan) * 1e5).ceil());

    final result = <({Store store, double distance})>[];
    for (var y = minLat; y <= maxLat; y++) {
      for (var x = minLng; x <= maxLng; x++) {
        final ids = _grid[_key(y, x)];
        if (ids == null) continue;
        for (final i in ids) {
          if (_category[i] != category.index) continue;
          final loc = LatLng(_lat[i] / 1e5, _lng[i] / 1e5);
          final d = distanceMeters(center, loc);
          if (d > radiusMeters) continue;
          result.add((
            store: Store(
              id: 'semas:$i',
              name: _names[i],
              category: category,
              location: loc,
            ),
            distance: d,
          ));
        }
      }
    }
    result.sort((a, b) => a.distance.compareTo(b.distance));
    return [for (final r in result) r.store];
  }

  static int _cellOf(int e5) => (e5 / (_cell * 1e5)).floor();

  static int _key(int latCell, int lngCell) => latCell * 100000 + lngCell;
}
