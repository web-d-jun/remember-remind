import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/item_repository.dart';
import '../models/shopping_item.dart';
import '../models/store_category.dart';

/// 사야 할 물건 목록 상태.
class ShoppingList extends ChangeNotifier {
  ShoppingList(this._repo) : _items = _repo.load();

  final ItemRepository _repo;
  final List<ShoppingItem> _items;
  static const _uuid = Uuid();

  List<ShoppingItem> get pending =>
      _items.where((i) => i.isPending).toList()..sort((a, b) {
        if (a.important != b.important) return a.important ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });

  List<ShoppingItem> get purchased =>
      _items.where((i) => !i.isPending).toList()
        ..sort((a, b) => b.purchasedAt!.compareTo(a.purchasedAt!));

  /// 아직 안 산 물건들이 필요로 하는 매장 종류. 추적 대상이 된다.
  Set<StoreCategory> get neededCategories => {
    for (final i in _items.where((i) => i.isPending)) ...i.categories,
  };

  Future<void> add(
    String name,
    Set<StoreCategory> categories, {
    bool important = false,
  }) async {
    _items.add(
      ShoppingItem(
        id: _uuid.v4(),
        name: name.trim(),
        categories: categories,
        createdAt: DateTime.now(),
        important: important,
      ),
    );
    await _commit();
  }

  Future<void> update(ShoppingItem item) async {
    final i = _items.indexWhere((e) => e.id == item.id);
    if (i < 0) return;
    _items[i] = item;
    await _commit();
  }

  Future<void> togglePurchased(ShoppingItem item) {
    return update(
      item.isPending
          ? item.copyWith(purchasedAt: DateTime.now())
          : item.copyWith(clearPurchasedAt: true),
    );
  }

  Future<void> remove(ShoppingItem item) async {
    _items.removeWhere((e) => e.id == item.id);
    await _commit();
  }

  Future<void> clearPurchased() async {
    _items.removeWhere((e) => !e.isPending);
    await _commit();
  }

  Future<void> _commit() async {
    notifyListeners();
    await _repo.save(_items);
  }
}
