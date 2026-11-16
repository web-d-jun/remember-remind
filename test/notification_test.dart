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
