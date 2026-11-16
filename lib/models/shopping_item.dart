import 'store_category.dart';

/// 사야 할 물건 하나.
class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.name,
    required this.categories,
    required this.createdAt,
    this.important = false,
    this.purchasedAt,
  });

  final String id;
  final String name;

  /// 이 물건을 살 수 있는 매장 종류들.
  final Set<StoreCategory> categories;
  final DateTime createdAt;

  /// "꼭 사야 함": 매장을 그냥 나갈 때 더 강하게 알린다.
  final bool important;
  final DateTime? purchasedAt;

  bool get isPending => purchasedAt == null;

  ShoppingItem copyWith({
    String? name,
    Set<StoreCategory>? categories,
    bool? important,
    DateTime? purchasedAt,
    bool clearPurchasedAt = false,
  }) {
    return ShoppingItem(
      id: id,
      name: name ?? this.name,
      categories: categories ?? this.categories,
      createdAt: createdAt,
      important: important ?? this.important,
      purchasedAt: clearPurchasedAt ? null : (purchasedAt ?? this.purchasedAt),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'categories': categories.map((c) => c.name).toList(),
    'createdAt': createdAt.toIso8601String(),
    'important': important,
    'purchasedAt': purchasedAt?.toIso8601String(),
  };

  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    return ShoppingItem(
      id: json['id'] as String,
      name: json['name'] as String,
      categories: ((json['categories'] as List?) ?? const [])
          .map((e) => StoreCategory.fromName(e as String))
          .whereType<StoreCategory>()
          .toSet(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      important: json['important'] as bool? ?? false,
      purchasedAt: json['purchasedAt'] == null
          ? null
          : DateTime.parse(json['purchasedAt'] as String),
    );
  }
}
