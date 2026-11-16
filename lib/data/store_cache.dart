import '../core/geo.dart';
import '../models/store.dart';
import '../models/store_category.dart';
import 'place_source.dart';

/// 주변 매장 목록을 들고 있다가, 많이 이동했을 때만 다시 조회한다.
///
/// OS 지오펜스 개수 제한(iOS 20개, Android 100개)에 묶이지 않도록
/// "근처 매장만 메모리에 두고 위치가 바뀌면 갱신"하는 방식을 쓴다.
class StoreCache {
  StoreCache(
    this._source, {
    this.searchRadius = 1000,
    this.refreshDistance = 500,
    this.maxAge = const Duration(hours: 6),
  });

  final PlaceSource _source;

  /// 한 번에 조회하는 반경(m).
  final int searchRadius;

  /// 마지막 조회 위치에서 이만큼 벗어나면 다시 조회한다.
  final double refreshDistance;
  final Duration maxAge;

  final Map<StoreCategory, _Entry> _entries = {};

  List<Store> get stores => [for (final e in _entries.values) ...e.stores];

  /// [categories]에 해당하는 주변 매장을 필요한 만큼만 갱신한다.
  /// 실패한 종류는 이전 결과를 유지하고, 다음 호출에서 다시 시도한다.
  Future<void> refresh({
    required LatLng center,
    required Set<StoreCategory> categories,
    required DateTime now,
  }) async {
    _entries.removeWhere((c, _) => !categories.contains(c));

    final stale = categories.where((c) {
      final e = _entries[c];
      return e == null ||
          now.difference(e.fetchedAt) > maxAge ||
          distanceMeters(center, e.center) > refreshDistance;
    }).toList();

    await Future.wait(
      stale.map((c) async {
        try {
          final result = await _source.nearby(
            center: center,
            category: c,
            radiusMeters: searchRadius,
          );
          _entries[c] = _Entry(center, now, result);
        } on Exception {
          // 네트워크 오류 등은 다음 위치 갱신 때 재시도한다.
        }
      }),
    );
  }
}

class _Entry {
  _Entry(this.center, this.fetchedAt, this.stores);

  final LatLng center;
  final DateTime fetchedAt;
  final List<Store> stores;
}
