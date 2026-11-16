import 'package:flutter_test/flutter_test.dart';
import 'package:remember_remind/core/item_categorizer.dart';
import 'package:remember_remind/core/quick_picks.dart';
import 'package:remember_remind/data/item_repository.dart';
import 'package:remember_remind/models/store_category.dart';
import 'package:remember_remind/state/shopping_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime(2026, 11, 16);
  HistoryEntry entry(String name, int count, int daysAgo) => HistoryEntry(
    name: name,
    categories: {StoreCategory.mart},
    count: count,
    lastAt: now.subtract(Duration(days: daysAgo)),
  );

  group('자주 사는 물건 순서', () {
    test('자주, 최근에 기억한 물건이 앞에 온다', () {
      final picks = rankQuickPicks(
        history: [entry('라면', 2, 1), entry('우유', 10, 2), entry('쌀', 10, 300)],
        pendingNames: {},
        now: now,
        limit: 3,
      );
      expect(picks, ['우유', '라면', '쌀']);
    });

    test('이미 목록에 있는 물건은 빼고, 모자라면 흔한 물건으로 채운다', () {
      final picks = rankQuickPicks(
        history: [entry('우유', 5, 0), entry('샴푸', 1, 0)],
        pendingNames: {'우유', '계란'},
        now: now,
        limit: 4,
      );
      expect(picks.first, '샴푸');
      expect(picks, isNot(contains('우유')));
      expect(picks, isNot(contains('계란')));
      expect(picks, hasLength(4));
    });
  });

  group('ShoppingList 빠른 추가', () {
    late ShoppingList list;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      list = ShoppingList(
        ItemRepository(await SharedPreferences.getInstance()),
      );
    });

    test('추가한 물건은 기록되고, 예전에 고른 매장 종류를 기억한다', () async {
      await list.add('우유', {StoreCategory.convenience});
      expect(list.rememberedCategories('우유'), {StoreCategory.convenience});
      expect(
        list.quickPicks,
        isNot(contains('우유')),
        reason: '아직 안 샀으니 칩에서 빠진다',
      );

      await list.togglePurchased(list.pending.single);
      expect(list.quickPicks.first, '우유', reason: '사고 나면 다시 칩으로 나온다');
    });

    test('기록은 앱을 다시 켜도 남는다', () async {
      await list.add('샴푸', {StoreCategory.drugstore});
      final reopened = ShoppingList(
        ItemRepository(await SharedPreferences.getInstance()),
      );
      expect(reopened.rememberedCategories('샴푸'), {StoreCategory.drugstore});
    });

    test('[되돌리기]는 방금 추가한 것만 지운다', () async {
      await list.add('휴지', {StoreCategory.mart});
      final added = await list.addAll([
        (
          name: '우유',
          categories: {StoreCategory.mart},
          important: false,
          photo: null,
        ),
        (
          name: '계란',
          categories: {StoreCategory.mart},
          important: false,
          photo: null,
        ),
      ]);
      await list.removeAll(added);
      expect(list.pending.map((i) => i.name), ['휴지']);
    });

    test('이름 없이 사진만 저장한 물건은 자주 사는 물건에 남기지 않는다', () async {
      await list.add(ShoppingList.photoOnlyName, ItemCategorizer.fallback);
      expect(list.rememberedCategories(ShoppingList.photoOnlyName), isNull);
    });
  });
}
