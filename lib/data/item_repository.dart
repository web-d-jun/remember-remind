import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/shopping_item.dart';

/// 물건 목록을 기기 안에 저장한다.
class ItemRepository {
  ItemRepository(this._prefs);

  static const _key = 'shopping_items_v1';

  final SharedPreferences _prefs;

  List<ShoppingItem> load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ShoppingItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on FormatException {
      return [];
    }
  }

  Future<void> save(List<ShoppingItem> items) {
    return _prefs.setString(
      _key,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }
}
