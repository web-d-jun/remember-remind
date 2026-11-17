import 'package:flutter_test/flutter_test.dart';
import 'package:remember_remind/core/geo.dart';
import 'package:remember_remind/models/store_category.dart';
import 'package:remember_remind/state/my_stores.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const cityHall = LatLng(37.5665, 126.9780);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('등록한 매장은 앱을 다시 열어도 남아 있다', () async {
    final prefs = await SharedPreferences.getInstance();
    final stores = MyStores(prefs);
    final daiso = await stores.add(
      name: '다이소 시청점',
      category: StoreCategory.daiso,
      location: cityHall,
      large: true,
    );
    expect(daiso.isUserRegistered, isTrue);

    final reopened = MyStores(prefs);
    expect(reopened.stores.single.name, '다이소 시청점');
    expect(reopened.stores.single.large, isTrue);
    expect(reopened.stores.single.location.latitude, cityHall.latitude);
  });

  test('필요한 종류이고 반경 안에 있는 매장만 근처 매장이 된다', () async {
    final stores = MyStores(await SharedPreferences.getInstance());
    await stores.add(
      name: '다이소',
      category: StoreCategory.daiso,
      location: cityHall,
      large: false,
    );
    await stores.add(
      name: '먼 다이소',
      category: StoreCategory.daiso,
      location: const LatLng(37.6, 126.9780), // 약 3.7km
      large: false,
    );
    expect(stores.near(cityHall, {StoreCategory.daiso}).map((s) => s.name), [
      '다이소',
    ]);
    expect(stores.near(cityHall, {StoreCategory.pharmacy}), isEmpty);
  });

  test('지운 매장을 되돌릴 수 있다', () async {
    final stores = MyStores(await SharedPreferences.getInstance());
    final a = await stores.add(
      name: 'A',
      category: StoreCategory.mart,
      location: cityHall,
      large: false,
    );
    await stores.add(
      name: 'B',
      category: StoreCategory.mart,
      location: cityHall,
      large: false,
    );
    await stores.remove(a);
    expect(stores.stores.map((s) => s.name), ['B']);
    await stores.restore(a, 0);
    expect(stores.stores.map((s) => s.name), ['A', 'B']);
  });
}
