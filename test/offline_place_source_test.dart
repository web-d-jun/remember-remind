import 'package:flutter_test/flutter_test.dart';
import 'package:remember_remind/core/geo.dart';
import 'package:remember_remind/data/place_source.dart';
import 'package:remember_remind/models/store_category.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 내장 데이터를 실제로 읽어(asset → gzip → 백그라운드 isolate) 검색까지 되는지 본다.
  // 주의: 앱에서만 나던 "object is unsendable" 실패(place_source.dart 참고)는
  // flutter test 환경에서는 재현되지 않아 이 테스트로는 잡히지 않는다. 기기에서 확인할 것.
  test('내장 매장 데이터에서 서울시청 근처 편의점을 찾는다', () async {
    final source = OfflinePlaceSource();
    final stores = await source.nearby(
      center: const LatLng(37.5665, 126.9780),
      category: StoreCategory.convenience,
      radiusMeters: 500,
    );
    expect(stores, isNotEmpty);
    expect(
      stores.every((s) => s.category == StoreCategory.convenience),
      isTrue,
    );
  });

  test('아이스크림 할인점은 마트가 아니라 아이스크림·과자 할인점으로 찾는다', () async {
    final source = OfflinePlaceSource();
    // 부산 연산동 더샵아이스크림할인점 좌표
    const here = LatLng(35.19202, 129.09554);
    final snack = await source.nearby(
      center: here,
      category: StoreCategory.snack,
      radiusMeters: 30,
    );
    final mart = await source.nearby(
      center: here,
      category: StoreCategory.mart,
      radiusMeters: 30,
    );
    expect(snack.map((s) => s.name), contains('더샵아이스크림할인점'));
    expect(mart.map((s) => s.name), isNot(contains('더샵아이스크림할인점')));
  });
}
