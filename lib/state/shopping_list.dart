import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/notification_action.dart';
import '../core/quick_picks.dart';
import '../data/item_repository.dart';
import '../data/photo_store.dart';
import '../models/item_draft.dart';
import '../models/shopping_item.dart';
import '../models/store_category.dart';

/// 사야 할 물건 목록 상태.
class ShoppingList extends ChangeNotifier {
  ShoppingList(this._repo, {PhotoStore? photos})
    : _photos = photos,
      _items = _repo.load(),
      _history = _repo.loadHistory();

  final ItemRepository _repo;
  final PhotoStore? _photos;
  final Map<String, HistoryEntry> _history;
  final List<ShoppingItem> _items;
  static const _uuid = Uuid();

  /// 사진만 찍고 이름을 말하지 않은 물건의 이름. 자주 사는 물건 기록에는 남기지 않는다.
  static const photoOnlyName = '사진 속 물건';

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

  Future<List<ShoppingItem>> add(
    String name,
    Set<StoreCategory> categories, {
    bool important = false,
    String? photo,
  }) {
    return addAll([
      (name: name, categories: categories, important: important, photo: photo),
    ]);
  }

  /// 음성으로 "우유랑 계란"처럼 여러 개를 한 번에 말했을 때.
  /// 추가한 물건을 돌려준다. (되돌리기에 쓴다)
  Future<List<ShoppingItem>> addAll(List<ItemDraft> drafts) async {
    final now = DateTime.now();
    final added = [
      for (final d in drafts)
        ShoppingItem(
          id: _uuid.v4(),
          name: d.name.trim(),
          categories: d.categories,
          createdAt: now,
          important: d.important,
          photo: d.photo,
        ),
    ];
    _items.addAll(added);
    for (final item in added) {
      if (item.name == photoOnlyName) continue;
      _history[item.name] =
          _history[item.name]?.bump(item.categories, now) ??
          HistoryEntry(
            name: item.name,
            categories: item.categories,
            count: 1,
            lastAt: now,
          );
    }
    await _repo.saveHistory(_history);
    await _commit();
    return added;
  }

  /// 한 번 눌러 다시 추가할 물건들. (자주, 최근에 기억한 순서)
  List<String> get quickPicks => rankQuickPicks(
    history: _history.values,
    pendingNames: {for (final i in _items.where((i) => i.isPending)) i.name},
    now: DateTime.now(),
  );

  /// 예전에 이 이름으로 골랐던 매장 종류. 없으면 null.
  Set<StoreCategory>? rememberedCategories(String name) =>
      _history[name]?.categories;

  /// [되돌리기]: 방금 추가한 물건들을 지운다.
  Future<void> removeAll(Iterable<ShoppingItem> items) async {
    final ids = {for (final i in items) i.id};
    final removed = _items.where((e) => ids.contains(e.id)).toList();
    _items.removeWhere((e) => ids.contains(e.id));
    await _deletePhotos(removed);
    await _commit();
  }

  Future<void> update(ShoppingItem item) async {
    final i = _items.indexWhere((e) => e.id == item.id);
    if (i < 0) return;
    final oldPhoto = _items[i].photo;
    _items[i] = item;
    if (oldPhoto != null && oldPhoto != item.photo) {
      await _photos?.delete(oldPhoto);
    }
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
    await _deletePhotos([item]);
    await _commit();
  }

  Future<void> clearPurchased() async {
    final removed = _items.where((e) => !e.isPending).toList();
    _items.removeWhere((e) => !e.isPending);
    await _deletePhotos(removed);
    await _commit();
  }

  Future<void> _deletePhotos(List<ShoppingItem> items) async {
    for (final i in items) {
      if (i.photo != null) await _photos?.delete(i.photo!);
    }
  }

  /// 알림 버튼([샀어요], [오늘은 그만])을 적용한다.
  Future<void> applyAction(NotificationAction action, Set<String> ids) async {
    final updated = applyNotificationAction(
      _items,
      action,
      ids,
      DateTime.now(),
    );
    _items
      ..clear()
      ..addAll(updated);
    await _commit();
  }

  /// 앱이 꺼져 있을 때 알림 버튼으로 바뀐 내용을 저장소에서 다시 읽는다.
  Future<void> reload() async {
    final fresh = await _repo.reload();
    _items
      ..clear()
      ..addAll(fresh);
    notifyListeners();
  }

  Future<void> _commit() async {
    notifyListeners();
    await _repo.save(_items);
  }
}
