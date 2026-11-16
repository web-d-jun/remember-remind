import 'package:flutter_test/flutter_test.dart';
import 'package:remember_remind/core/geo.dart';
import 'package:remember_remind/core/proximity_engine.dart';
import 'package:remember_remind/models/shopping_item.dart';
import 'package:remember_remind/models/store.dart';
import 'package:remember_remind/models/store_category.dart';

/// 위도 1도 ≈ 111km 이므로, 북쪽으로 [m]미터 떨어진 지점.
LatLng north(LatLng from, double m) =>
    LatLng(from.latitude + m / 111195, from.longitude);

void main() {
  const origin = LatLng(37.5665, 126.9780);
  final gs25 = Store(
    id: 'gs25',
    name: 'GS25 시청점',
    category: StoreCategory.convenience,
    location: origin,
  );
  final emart = Store(
    id: 'emart',
    name: '이마트',
    category: StoreCategory.mart,
    location: north(origin, 120),
  );
  final t0 = DateTime(2026, 11, 16, 18);

  ShoppingItem item(
    String name,
    Set<StoreCategory> cats, {
    bool important = false,
  }) => ShoppingItem(
    id: name,
    name: name,
    categories: cats,
    createdAt: t0,
    important: important,
  );

  final milk = item('우유', {StoreCategory.convenience, StoreCategory.mart});
  final battery = item('건전지', {StoreCategory.convenience});
  final rice = item('쌀', {StoreCategory.mart});

  late ProximityEngine engine;
  late List<ShoppingItem> pending;

  setUp(() {
    engine = ProximityEngine();
    pending = [milk, battery];
  });

  List<ProximityEvent> at(
    double metersNorthOfGs25,
    Duration elapsed, {
    double speed = 1.2,
    List<Store>? stores,
    double accuracy = 10,
  }) {
    return engine.update(
      position: PositionSample(
        location: north(origin, metersNorthOfGs25),
        accuracy: accuracy,
        speed: speed,
      ),
      now: t0.add(elapsed),
      stores: stores ?? [gs25],
      pendingItems: pending,
    );
  }

  group('문제 1: 매장 근처를 지나갈 때', () {
    test('반경 안에 들어오면 살 수 있는 물건과 함께 알린다', () {
      expect(at(500, Duration.zero), isEmpty);
      final events = at(100, const Duration(minutes: 1));
      expect(events.single, isA<ApproachEvent>());
      expect(events.single.items, [milk, battery]);
    });

    test('그 매장에서 살 물건이 없으면 알리지 않는다', () {
      pending = [rice];
      expect(at(100, Duration.zero), isEmpty);
    });

    test('차를 타고 빠르게 지나가면 알리지 않는다', () {
      expect(at(100, Duration.zero, speed: 15), isEmpty);
    });

    test('같은 매장은 쿨다운 동안 다시 알리지 않는다', () {
      expect(at(100, Duration.zero), hasLength(1));
      expect(at(500, const Duration(minutes: 5)), isEmpty);
      expect(at(100, const Duration(minutes: 10)), isEmpty);
      expect(at(500, const Duration(hours: 4)), isEmpty);
      expect(at(100, const Duration(hours: 4, minutes: 1)), hasLength(1));
    });

    test('같은 종류 매장을 연달아 지나가도 한 번만 알린다', () {
      final cu = Store(
        id: 'cu',
        name: 'CU',
        category: StoreCategory.convenience,
        location: north(origin, 400),
      );
      expect(at(100, Duration.zero, stores: [gs25, cu]), hasLength(1));
      expect(at(300, const Duration(minutes: 3), stores: [gs25, cu]), isEmpty);
    });

    test('오차가 큰 위치는 무시한다', () {
      expect(at(100, Duration.zero, accuracy: 500), isEmpty);
    });

    test('[오늘은 그만]으로 미룬 물건은 근처 알림에서 빠진다', () {
      final snoozed = milk.copyWith(
        snoozedUntil: t0.add(const Duration(hours: 6)),
      );
      pending = [snoozed, battery];
      expect(at(100, Duration.zero).single.items, [battery]);
    });

    test('미룬 물건뿐이면 근처 알림을 보내지 않지만, 매장에 들어가면 목록은 보여준다', () {
      pending = [milk.copyWith(snoozedUntil: t0.add(const Duration(hours: 6)))];
      expect(at(100, Duration.zero), isEmpty);
      at(10, const Duration(minutes: 1));
      final events = at(10, const Duration(minutes: 3));
      expect(events.single, isA<InStoreEvent>());
    });

    test('여러 매장이 있으면 가장 가까운 곳 하나만 알린다', () {
      final events = at(
        75,
        Duration.zero,
        stores: [gs25, emart],
      ); // GS25 75m, 이마트 45m
      expect(events.single.store, emart);
    });
  });

  group('문제 2: 매장에 들어갔다가 빠뜨리고 나올 때', () {
    test('매장 안에서 일정 시간 머무르면 남은 목록을 보여준다', () {
      expect(at(10, Duration.zero), isEmpty);
      expect(engine.currentStore, isNull, reason: '아직 체류 시간이 안 찼다');
      final events = at(10, const Duration(seconds: 61));
      expect(events.single, isA<InStoreEvent>());
      expect(engine.currentStore, gs25);
    });

    test('물건을 남긴 채로 나가면 빠뜨렸다고 알린다', () {
      at(10, Duration.zero);
      at(10, const Duration(minutes: 3));
      pending = [battery]; // 우유만 사고 건전지는 깜빡함
      final events = at(150, const Duration(minutes: 5));
      final left = events.single as LeftStoreEvent;
      expect(left.forgotSomething, isTrue);
      expect(left.items, [battery]);
      expect(engine.currentStore, isNull);
    });

    test('다 사고 나가면 빠뜨린 물건이 없다', () {
      at(10, Duration.zero);
      at(10, const Duration(minutes: 3));
      pending = [];
      final left = at(150, const Duration(minutes: 5)).single as LeftStoreEvent;
      expect(left.forgotSomething, isFalse);
    });

    test('앞을 스쳐 지나가기만 했으면 나갈 때 알리지 않는다', () {
      at(10, Duration.zero);
      expect(at(150, const Duration(seconds: 20)), isEmpty);
    });

    test('GPS가 조금 흔들려도 매장을 떠난 걸로 보지 않는다', () {
      at(10, Duration.zero);
      at(10, const Duration(minutes: 2));
      expect(at(60, const Duration(minutes: 3)), isEmpty);
      expect(engine.currentStore, gs25);
    });

    test('매장 안에 있는 동안은 근처 다른 매장 알림을 보내지 않는다', () {
      pending = [milk, battery, rice];
      at(10, Duration.zero, stores: [gs25, emart]);
      final events = at(10, const Duration(minutes: 2), stores: [gs25, emart]);
      expect(events.whereType<ApproachEvent>(), isEmpty);
    });

    test('매장 안에서 체크하면 남은 목록이 줄어든다', () {
      at(10, Duration.zero);
      at(10, const Duration(minutes: 2));
      expect(engine.currentStoreItems([battery]), [battery]);
      expect(engine.currentStoreItems([rice]), isEmpty);
    });
  });
}
