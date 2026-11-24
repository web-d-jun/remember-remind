import 'package:flutter_test/flutter_test.dart';
import 'package:remember_remind/core/geo.dart';
import 'package:remember_remind/core/notification_action.dart';
import 'package:remember_remind/core/notification_copy.dart';
import 'package:remember_remind/core/proximity_engine.dart';
import 'package:remember_remind/models/shopping_item.dart';
import 'package:remember_remind/models/store.dart';
import 'package:remember_remind/models/store_category.dart';

void main() {
  final now = DateTime(2026, 11, 16, 18, 30);
  ShoppingItem item(String name, {bool important = false}) => ShoppingItem(
    id: name,
    name: name,
    categories: {StoreCategory.convenience},
    createdAt: now,
    important: important,
  );
  const store = Store(
    id: 'gs25',
    name: 'GS25 시청점',
    category: StoreCategory.convenience,
    location: LatLng(37.5665, 126.9780),
  );

  group('알림 버튼', () {
    final milk = item('우유');
    final battery = item('건전지');
    final bought = item('휴지').copyWith(purchasedAt: now);

    test('물건이 하나일 때만 [샀어요] 버튼을 붙인다 (일부만 샀는데 전부 체크되지 않게)', () {
      expect(offersPurchasedButton([milk]), isTrue);
      expect(offersPurchasedButton([milk, battery]), isFalse);
    });

    test('payload에 물건 id를 담고 다시 꺼낼 수 있다', () {
      expect(decodeItemIds(encodeItemIds([milk, battery])), {'우유', '건전지'});
      expect(decodeItemIds(null), isEmpty);
      expect(decodeItemIds('깨진값'), isEmpty);
      expect(decodeItemIds('{"a":1}'), isEmpty);
    });

    test('[샀어요]는 알림에 나온 물건만 산 것으로 바꾼다', () {
      final result = applyNotificationAction(
        [milk, battery, bought],
        NotificationAction.purchased,
        {'우유'},
        now,
      );
      expect(result[0].purchasedAt, now);
      expect(result[1].isPending, isTrue);
      expect(result[2].purchasedAt, bought.purchasedAt, reason: '이미 산 건 그대로');
    });

    test('[오늘은 그만]은 오늘 자정까지 미룬다', () {
      final result = applyNotificationAction(
        [milk],
        NotificationAction.snoozeToday,
        {'우유'},
        now,
      );
      expect(result.single.snoozedUntil, DateTime(2026, 11, 17));
      expect(result.single.isSnoozed(now), isTrue);
      expect(result.single.isSnoozed(DateTime(2026, 11, 17, 0, 1)), isFalse);
      expect(result.single.isPending, isTrue);
    });

    test('모르는 버튼 id는 무시한다', () {
      expect(NotificationAction.fromId('???'), isNull);
      expect(NotificationAction.fromId(null), isNull);
    });

    test('미뤄둔 시각도 저장하고 복원한다', () {
      final snoozed = milk.copyWith(snoozedUntil: DateTime(2026, 11, 17));
      expect(
        ShoppingItem.fromJson(snoozed.toJson()).snoozedUntil,
        DateTime(2026, 11, 17),
      );
    });
  });

  group('알림 문구', () {
    test('근처를 지날 때', () {
      final copy = NotificationCopy.of(ApproachEvent(store, [item('우유')]));
      expect(copy.title, '까악! GS25 시청점 앞이에요');
      expect(copy.body, '여기서 우유를 살 수 있어요');
    });

    test('불확실한 매장은 단정하지 않고 "혹시?"로 묻는다', () {
      const a = Store(
        id: 'a',
        name: '행복상회',
        category: StoreCategory.convenience,
        location: LatLng(37.5665, 126.9780),
        certain: false,
      );
      const b = Store(
        id: 'b',
        name: '이가네',
        category: StoreCategory.convenience,
        location: LatLng(37.5665, 126.9780),
        certain: false,
      );
      final copy = NotificationCopy.of(
        MaybeNearbyEvent(a, [item('우유'), item('젖병솔')], stores: [a, b]),
      );
      expect(copy.title, '까악! 혹시 이 근처에…?');
      expect(copy.body, '우유, 젖병솔을 파는 가게가 있을지도 몰라요 · 행복상회 외 1곳 (확실하진 않아요)');
    });

    group('대형 매장 안에 입점한 매장', () {
      const emart = Store(
        id: 'emart',
        name: '이마트 성수점',
        category: StoreCategory.mart,
        location: LatLng(37.5665, 126.9780),
        large: true,
      );
      const pharmacy = Store(
        id: 'ph',
        name: '이마트약국',
        category: StoreCategory.pharmacy,
        location: LatLng(37.5665, 126.9780),
      );
      ShoppingItem at(String name, StoreCategory c) =>
          ShoppingItem(id: name, name: name, categories: {c}, createdAt: now);
      final rice = at('쌀', StoreCategory.mart);
      final medicine = at('감기약', StoreCategory.pharmacy);

      test('근처 알림에 안에 있는 매장을 알려준다', () {
        final copy = NotificationCopy.of(
          ApproachEvent(emart, [rice, medicine], tenants: [pharmacy]),
        );
        expect(copy.body, '여기서 쌀, 감기약을 살 수 있어요 (안에 약국이 있어요)');
      });

      test('마트에서 바로 살 수 있으면 덧붙이지 않는다', () {
        final copy = NotificationCopy.of(
          ApproachEvent(emart, [rice], tenants: [pharmacy]),
        );
        expect(copy.body, '여기서 쌀을 살 수 있어요');
      });

      test('매장 안 목록에 어디서 사는지 붙인다', () {
        final copy = NotificationCopy.inStore(
          emart,
          [rice, medicine],
          [pharmacy],
        );
        expect(copy.title, '이마트 성수점에서 살 것 2개');
        expect(copy.body, '• 쌀\n• 감기약 (약국)');
      });
    });

    test('안 사고 나갈 때', () {
      final copy = NotificationCopy.of(
        LeftStoreEvent(store, [item('감기약'), item('건전지')]),
      );
      expect(copy.title, '까먹지 마, 귀가 전에!');
      expect(copy.body, contains('감기약, 건전지를 안 샀어요'));
    });

    test('꼭 사야 하는 물건을 안 사고 나가면 제목에서 이름을 부른다', () {
      final copy = NotificationCopy.of(
        LeftStoreEvent(store, [item('기저귀', important: true), item('우유')]),
      );
      expect(copy.title, '까악! 기저귀는 꼭 사야 해요');
    });

    test('물건이 많으면 줄여서 보여준다', () {
      final names = NotificationCopy.itemNames([
        item('우유'),
        item('건전지'),
        item('휴지'),
        item('라면'),
      ]);
      expect(names, '우유, 건전지 외 2개');
    });

    test('받침에 따라 조사를 고른다', () {
      expect(NotificationCopy.josa('감기약', '을', '를'), '을');
      expect(NotificationCopy.josa('우유', '을', '를'), '를');
      expect(NotificationCopy.josa('외 2개', '을', '를'), '를');
      expect(NotificationCopy.josa('AA', '을', '를'), '을(를)');
    });
  });
}
