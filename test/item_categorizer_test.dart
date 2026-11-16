import 'package:flutter_test/flutter_test.dart';
import 'package:remember_remind/core/item_categorizer.dart';
import 'package:remember_remind/models/shopping_item.dart';
import 'package:remember_remind/models/store_category.dart';

void main() {
  const categorizer = ItemCategorizer();

  test('사전에 있는 물건은 해당 매장 종류를 추천한다', () {
    expect(categorizer.suggest('우유'), {
      StoreCategory.convenience,
      StoreCategory.mart,
    });
    expect(categorizer.suggest('감기약'), {StoreCategory.pharmacy});
  });

  test('부분 일치는 가장 긴 키워드를 쓴다', () {
    expect(categorizer.suggest('어린이 감기약'), {StoreCategory.pharmacy});
    expect(categorizer.suggest('AA 건전지'), contains(StoreCategory.daiso));
  });

  test('모르는 물건은 편의점·마트를 추천하고, 빈 이름은 추천하지 않는다', () {
    expect(categorizer.suggest('무언가'), ItemCategorizer.fallback);
    expect(categorizer.suggest('  '), isEmpty);
  });

  test('ShoppingItem은 JSON으로 저장하고 복원할 수 있다', () {
    final item = ShoppingItem(
      id: '1',
      name: '우유',
      categories: {StoreCategory.mart},
      createdAt: DateTime(2026, 11, 16),
      important: true,
    );
    final restored = ShoppingItem.fromJson(item.toJson());
    expect(restored.name, '우유');
    expect(restored.categories, {StoreCategory.mart});
    expect(restored.important, isTrue);
    expect(restored.isPending, isTrue);
  });
}
