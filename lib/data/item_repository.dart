import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/quick_picks.dart';
import '../models/shopping_item.dart';

/// 물건 목록을 기기 안에 저장한다.
class ItemRepository {
  ItemRepository(this._prefs);

  static const _key = 'shopping_items_v1';
  static const _historyKey = 'item_history_v1';

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

  /// 다른 isolate(알림 버튼 처리)가 쓴 내용까지 디스크에서 다시 읽는다.
  Future<List<ShoppingItem>> reload() async {
    await _prefs.reload();
    return load();
  }

  Future<void> save(List<ShoppingItem> items) {
    return _prefs.setString(
      _key,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  /// 예전에 기억했던 물건 기록 (이름 → 기록).
  Map<String, HistoryEntry> loadHistory() {
    final raw = _prefs.getString(_historyKey);
    if (raw == null) return {};
    try {
      final list = jsonDecode(raw) as List;
      final entries = list.map(
        (e) => HistoryEntry.fromJson(e as Map<String, dynamic>),
      );
      return {for (final e in entries) e.name: e};
    } on FormatException {
      return {};
    }
  }

  Future<void> saveHistory(Map<String, HistoryEntry> history) {
    return _prefs.setString(
      _historyKey,
      jsonEncode(history.values.map((e) => e.toJson()).toList()),
    );
  }
}
