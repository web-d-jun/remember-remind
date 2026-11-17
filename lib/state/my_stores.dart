import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/geo.dart';
import '../models/store.dart';
import '../models/store_category.dart';

/// 사용자가 직접 등록한 매장.
///
/// 내장 데이터에 없는 매장(다이소 대부분, 새로 생긴 매장 등)을 채운다.
/// 기기 안에만 저장하며, 근처 매장 검색 결과와 함께 근접 판단에 쓰인다.
class MyStores extends ChangeNotifier {
  MyStores(this._prefs) : _stores = _load(_prefs);

  static const _key = 'my_stores_v1';
  static const _uuid = Uuid();

  final SharedPreferences _prefs;
  final List<Store> _stores;

  List<Store> get stores => List.unmodifiable(_stores);

  /// [center]에서 [radiusMeters] 안에 있고 [categories]에 해당하는 매장.
  List<Store> near(
    LatLng center,
    Set<StoreCategory> categories, {
    double radiusMeters = 1000,
  }) => [
    for (final s in _stores)
      if (categories.contains(s.category) &&
          distanceMeters(center, s.location) <= radiusMeters)
        s,
  ];

  Future<Store> add({
    required String name,
    required StoreCategory category,
    required LatLng location,
    required bool large,
  }) async {
    final store = Store(
      id: '${Store.userIdPrefix}${_uuid.v4()}',
      name: name,
      category: category,
      location: location,
      large: large,
    );
    _stores.add(store);
    await _save();
    notifyListeners();
    return store;
  }

  Future<void> remove(Store store) async {
    _stores.removeWhere((s) => s.id == store.id);
    await _save();
    notifyListeners();
  }

  /// 지운 매장을 되돌린다.
  Future<void> restore(Store store, int index) async {
    _stores.insert(index.clamp(0, _stores.length), store);
    await _save();
    notifyListeners();
  }

  static List<Store> _load(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          ?Store.fromJson(e as Map<String, dynamic>),
      ];
    } on FormatException {
      return [];
    }
  }

  Future<void> _save() => _prefs.setString(
    _key,
    jsonEncode([for (final s in _stores) s.toJson()]),
  );
}
