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

    test('가까운 매장이 이미 알렸으면, 살 물건이 다른 그다음 매장을 알린다', () {
      // GS25 50m, 약국 110m 앞에 서 있다. 우유는 GS25, 감기약은 약국.
      final pharmacy = Store(
        id: 'ph',
        name: '약국',
        category: StoreCategory.pharmacy,
        location: north(origin, -60),
      );
      final medicine = item('감기약', {StoreCategory.pharmacy});
      pending = [milk, medicine];
      final first = at(50, Duration.zero, stores: [gs25, pharmacy]);
      expect(first.single.store, gs25);
      expect(first.single.items, [milk]);
      final second = at(
        50,
        const Duration(seconds: 15),
        stores: [gs25, pharmacy],
      );
      expect(second.single.store, pharmacy);
      expect(second.single.items, [medicine]);
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

    /// [metersPerSecond]로 남쪽 [from]m에서 북쪽 [to]m까지 걸으며 5초마다 위치를 넣는다.
    List<ProximityEvent> walk(
      double from,
      double to, {
      double metersPerSecond = 1.2,
      List<Store>? stores,
    }) {
      final events = <ProximityEvent>[];
      final seconds = ((to - from) / metersPerSecond).round();
      for (var s = 0; s <= seconds; s += 5) {
        events.addAll(
          at(
            from + s * metersPerSecond,
            Duration(seconds: s),
            speed: metersPerSecond,
            stores: stores,
          ),
        );
      }
      return events;
    }

    test('보통 걸음으로 매장 앞을 지나가기만 하면 들어갔다고 보지 않는다', () {
      final events = walk(-150, 300);
      expect(events.whereType<ApproachEvent>(), hasLength(1));
      expect(events.whereType<InStoreEvent>(), isEmpty);
      expect(events.whereType<LeftStoreEvent>(), isEmpty);
    });

    test('천천히 걸어 지나가도(0.7m/s) 들어갔다고 보지 않는다', () {
      final events = walk(-150, 300, metersPerSecond: 0.7);
      expect(events.whereType<InStoreEvent>(), isEmpty);
      expect(events.whereType<LeftStoreEvent>(), isEmpty);
    });

    test('매장 안에서 돌아다니며 위치가 흔들려도 들어간 걸로 본다', () {
      // 매장 좌표 주변 ±15m 를 오간다.
      final events = <ProximityEvent>[];
      for (var s = 0; s <= 120; s += 10) {
        events.addAll(at((s ~/ 10).isEven ? -15 : 15, Duration(seconds: s)));
      }
      expect(events.whereType<InStoreEvent>(), hasLength(1));
      expect(engine.currentStore, gs25);
    });

    test('지나가다가 매장에 들어가 멈추면, 멈춘 때부터 세어 들어간 걸로 본다', () {
      walk(-150, 0);
      expect(engine.currentStore, isNull);
      final base = (150 / 1.2).round();
      at(5, Duration(seconds: base + 30));
      final events = at(5, Duration(seconds: base + 100));
      expect(events.whereType<InStoreEvent>(), hasLength(1));
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

  group('대형 매장: 안에서는 GPS가 매장 좌표와 많이 어긋난다', () {
    // 매장 좌표(건물 가운데)에서 북쪽으로 1km 떨어진 곳을 기준으로 한다.
    final hypermarket = Store(
      id: 'homeplus',
      name: '홈플러스 시청점',
      category: StoreCategory.mart,
      location: north(origin, 1000),
      large: true,
    );
    final smallMart = Store(
      id: 'small',
      name: '동네마트',
      category: StoreCategory.mart,
      location: north(origin, 1000),
    );

    /// 매장 좌표에서 [m]미터 떨어진 곳.
    List<ProximityEvent> near(
      Store store,
      double m,
      Duration elapsed, {
      List<Store>? stores,
    }) => at(1000 + m, elapsed, stores: stores ?? [store]);

    setUp(() => pending = [rice]);

    test('매장 좌표에서 100m 떨어져 있어도 5분 머물면 안에 있다고 본다', () {
      near(hypermarket, 100, Duration.zero);
      near(hypermarket, 120, const Duration(minutes: 2));
      expect(engine.currentStore, isNull, reason: '아직 5분이 안 됐다');
      final events = near(hypermarket, 90, const Duration(minutes: 5));
      expect(events.single, isA<InStoreEvent>());
      expect(engine.currentStore, hypermarket);
    });

    test('근처에 들어올 때 접근 알림은 그대로 보낸다', () {
      final events = near(hypermarket, 140, Duration.zero);
      expect(events.single, isA<ApproachEvent>());
    });

    test('GPS가 150m 넘게 튀어도 크게 벗어나지 않으면 떠난 걸로 보지 않는다', () {
      near(hypermarket, 100, Duration.zero);
      near(hypermarket, 100, const Duration(minutes: 5));
      expect(near(hypermarket, 200, const Duration(minutes: 8)), isEmpty);
      expect(engine.currentStore, hypermarket);
    });

    test('250m 넘게 벗어나면 떠났다고 보고, 안 산 물건을 알린다', () {
      near(hypermarket, 100, Duration.zero);
      near(hypermarket, 100, const Duration(minutes: 5));
      final left =
          near(hypermarket, 300, const Duration(minutes: 20)).single
              as LeftStoreEvent;
      expect(left.items, [rice]);
      expect(engine.currentStore, isNull);
    });

    test('근처를 잠깐 지나가기만 하면 안에 있다고 보지 않는다', () {
      near(hypermarket, 100, Duration.zero);
      near(hypermarket, 120, const Duration(minutes: 2));
      expect(near(hypermarket, 400, const Duration(minutes: 3)), isEmpty);
      expect(near(hypermarket, 100, const Duration(minutes: 6)), isEmpty);
      expect(engine.currentStore, isNull, reason: '다시 온 때부터 새로 센다');
    });

    test('매장 좌표 가까이 있어도 대형 매장은 5분 기준으로 본다', () {
      near(hypermarket, 20, Duration.zero);
      near(hypermarket, 10, const Duration(seconds: 70));
      expect(engine.currentStore, isNull, reason: '일반 매장 기준(1분)을 쓰지 않는다');
      final events = near(hypermarket, 30, const Duration(minutes: 5));
      expect(events.single, isA<InStoreEvent>());
    });

    test('넓은 매장 안을 돌아다녀도(좌표 40m 안팎을 들락거림) 5분이면 확정한다', () {
      final spots = <double>[10, 60, 90, 30, -40, -80, 20, 70];
      for (var s = 0; s <= 300; s += 15) {
        near(
          hypermarket,
          spots[(s ~/ 15) % spots.length],
          Duration(seconds: s),
        );
      }
      expect(engine.currentStore, hypermarket);
    });

    test('대형 매장 앞을 천천히 걸어 지나가기만 하면(0.8m/s) 들어갔다고 보지 않는다', () {
      final events = <ProximityEvent>[];
      // 매장 좌표 남쪽 200m에서 북쪽 300m까지 (150m 안을 약 6분 동안 지난다)
      for (var s = 0; s <= 625; s += 5) {
        events.addAll(
          at(
            800 + s * 0.8,
            Duration(seconds: s),
            speed: 0.8,
            stores: [hypermarket],
          ),
        );
      }
      expect(events.whereType<InStoreEvent>(), isEmpty);
      expect(events.whereType<LeftStoreEvent>(), isEmpty);
    });

    test('일반 매장은 근처에 오래 있어도 안에 있다고 보지 않는다', () {
      near(smallMart, 100, Duration.zero);
      near(smallMart, 100, const Duration(minutes: 10));
      expect(engine.currentStore, isNull);
    });

    test('대형 매장 근처에 머무는 동안에도 바로 옆 다른 매장에 들어가면 그쪽으로 본다', () {
      final pharmacy = Store(
        id: 'ph',
        name: '약국',
        category: StoreCategory.pharmacy,
        location: north(origin, 1100),
      );
      pending = [
        rice,
        item('감기약', {StoreCategory.pharmacy}),
      ];
      final stores = [hypermarket, pharmacy];
      near(hypermarket, 120, Duration.zero, stores: stores);
      near(hypermarket, 100, const Duration(minutes: 1), stores: stores);
      near(hypermarket, 100, const Duration(minutes: 3), stores: stores);
      expect(engine.currentStore, pharmacy);
    });
  });

  group('가게가 많은 건물 안의 대형 매장 (서울역 롯데마트 같은 곳)', () {
    final hypermarket = Store(
      id: 'lotte',
      name: '롯데마트 서울역점',
      category: StoreCategory.mart,
      location: north(origin, 1000),
      large: true,
    );
    // 마트 좌표에서 40~90m 떨어진 작은 가게들 (입점 매장으로 묶이지 않는 거리)
    final shops = [
      for (final (i, m) in <double>[45, -60, 90, -85].indexed)
        Store(
          id: 'shop$i',
          name: '편의점$i',
          category: StoreCategory.convenience,
          location: north(origin, 1000 + m),
        ),
    ];

    test('마트 안을 돌다 다른 가게 좌표 근처를 지나도 마트 타이머가 이어진다', () {
      pending = [milk, rice];
      final stores = [hypermarket, ...shops];
      // 가게 좌표 근처를 계속 지나가며 돌아다닌다.
      final spots = <double>[40, 60, -55, -20, 85, 50, -80, 10, 95, -60];
      final events = <ProximityEvent>[];
      for (var s = 0; s <= 330; s += 15) {
        events.addAll(
          at(
            1000 + spots[(s ~/ 15) % spots.length],
            Duration(seconds: s),
            stores: stores,
          ),
        );
      }
      expect(engine.currentStore, hypermarket);
      expect(events.whereType<InStoreEvent>().single.store, hypermarket);
      expect(events.whereType<LeftStoreEvent>(), isEmpty);
    });
  });

  group('대형 매장 안에 입점한 매장 (이마트 안 약국)', () {
    // 이마트 좌표는 GS25 북쪽 1km. 입점 약국은 주소로 좌표를 찍어 거의 같은 점에 있다.
    final emart = Store(
      id: 'emart',
      name: '이마트 성수점',
      category: StoreCategory.mart,
      location: north(origin, 1000),
      large: true,
    );
    final inPharmacy = Store(
      id: 'emart-ph',
      name: '이마트약국',
      category: StoreCategory.pharmacy,
      location: north(origin, 1005),
    );
    final medicine = item('감기약', {StoreCategory.pharmacy});
    final stores = [emart, inPharmacy];

    /// 이마트 좌표에서 [m]미터 떨어진 곳.
    List<ProximityEvent> atEmart(double m, Duration elapsed) =>
        at(1000 + m, elapsed, stores: stores);

    setUp(() => pending = [rice, medicine]);

    test('근처 알림은 이마트 한 곳으로 한 번만, 두 물건을 함께 알린다', () {
      final first = atEmart(140, Duration.zero);
      final approach = first.single as ApproachEvent;
      expect(approach.store, emart);
      expect(approach.items, [rice, medicine]);
      expect(approach.tenants, [inPharmacy]);
      expect(
        atEmart(120, const Duration(seconds: 15)),
        isEmpty,
        reason: '약국 알림이 따로 오지 않는다',
      );
    });

    test('약국 물건만 있어도 이마트로 알린다', () {
      pending = [medicine];
      final approach = atEmart(140, Duration.zero).single as ApproachEvent;
      expect(approach.store, emart);
      expect(approach.items, [medicine]);
    });

    test('마트 안을 돌다 약국 좌표를 지나도 이마트 방문이 유지되고, 5분이면 두 물건을 함께 보여준다', () {
      final spots = <double>[100, 5, 60, 0, -50, 10, 80, 3];
      final events = <ProximityEvent>[];
      for (var s = 0; s <= 300; s += 15) {
        events.addAll(
          atEmart(spots[(s ~/ 15) % spots.length], Duration(seconds: s)),
        );
      }
      expect(engine.currentStore, emart);
      final inStore = events.whereType<InStoreEvent>().single;
      expect(inStore.store, emart);
      expect(inStore.items, [rice, medicine]);
      expect(engine.currentTenants, [inPharmacy]);
    });

    test('쌀만 사고 나가면 이마트에서 감기약을 안 샀다고 알린다', () {
      atEmart(100, Duration.zero);
      atEmart(80, const Duration(minutes: 5));
      expect(engine.currentStoreItems([medicine]), [medicine]);
      pending = [medicine];
      final left =
          atEmart(300, const Duration(minutes: 30)).single as LeftStoreEvent;
      expect(left.store, emart);
      expect(left.items, [medicine]);
    });

    test('길 건너(60m) 약국은 입점 매장이 아니라 따로 알린다', () {
      final across = Store(
        id: 'across',
        name: '길건너약국',
        category: StoreCategory.pharmacy,
        location: north(origin, 1060),
      );
      final events = [
        ...at(1140, Duration.zero, stores: [emart, across]),
        ...at(1140, const Duration(seconds: 15), stores: [emart, across]),
      ];
      expect(events.map((e) => e.store), containsAll([emart, across]));
      expect((events.first as ApproachEvent).tenants, isEmpty);
    });
  });

  group('불확실한 매장 (이름은 달콤한솜사탕인데 업종은 슈퍼마켓 같은 곳)', () {
    final unsure = Store(
      id: 'unsure',
      name: '행복상회',
      category: StoreCategory.mart,
      location: origin,
      certain: false,
    );
    final unsure2 = Store(
      id: 'unsure2',
      name: '이가네',
      category: StoreCategory.mart,
      location: north(origin, 60),
      certain: false,
    );
    final bottleBrush = item('젖병솔', {StoreCategory.mart, StoreCategory.daiso});

    setUp(() => pending = [milk, bottleBrush]);

    test('"여기서 살 수 있어요"가 아니라 "혹시?"로 묻고, 근처 몇 곳을 함께 알려준다', () {
      final events = at(100, Duration.zero, stores: [unsure, unsure2]);
      final maybe = events.single as MaybeNearbyEvent;
      expect(maybe.items, [milk, bottleBrush]);
      expect(maybe.stores, [unsure2, unsure]);
      expect(events.whereType<ApproachEvent>(), isEmpty);
    });

    test('근처 확실한 매장에서 살 수 있는 물건은 "혹시?"에서 뺀다', () {
      // GS25(확실)는 우유를 팔고, 젖병솔은 동네 가게(불확실)만 팔지도 모른다.
      final events = [
        ...at(100, Duration.zero, stores: [gs25, unsure2]),
        ...at(100, const Duration(seconds: 15), stores: [gs25, unsure2]),
      ];
      expect(events.first, isA<ApproachEvent>());
      expect(events.first.items, [milk]);
      final maybe = events.whereType<MaybeNearbyEvent>().single;
      expect(maybe.items, [bottleBrush]);
    });

    test('확실한 매장에서 모두 살 수 있으면 "혹시?"를 묻지 않는다', () {
      pending = [milk];
      final events = [
        ...at(100, Duration.zero, stores: [gs25, unsure2]),
        ...at(100, const Duration(seconds: 15), stores: [gs25, unsure2]),
      ];
      expect(events.whereType<MaybeNearbyEvent>(), isEmpty);
    });

    test('"혹시?"는 2시간에 한 번만 묻는다', () {
      expect(at(100, Duration.zero, stores: [unsure]), hasLength(1));
      expect(at(100, const Duration(minutes: 30), stores: [unsure]), isEmpty);
      expect(
        at(100, const Duration(hours: 2, minutes: 1), stores: [unsure]),
        hasLength(1),
      );
    });

    test('불확실한 매장에 오래 있다가 나가도 "안 샀어요"라고 하지 않는다', () {
      final events = <ProximityEvent>[];
      for (var s = 0; s <= 300; s += 15) {
        events.addAll(at(5, Duration(seconds: s), stores: [unsure]));
      }
      events.addAll(at(300, const Duration(minutes: 10), stores: [unsure]));
      expect(events.whereType<InStoreEvent>(), isEmpty);
      expect(events.whereType<LeftStoreEvent>(), isEmpty);
      expect(engine.currentStore, isNull);
    });
  });
}
