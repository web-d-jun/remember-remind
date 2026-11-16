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
    this.snoozedUntil,
    this.photo,
  });

  final String id;
  final String name;

  /// 이 물건을 살 수 있는 매장 종류들.
  final Set<StoreCategory> categories;
  final DateTime createdAt;

  /// "꼭 사야 함": 매장을 그냥 나갈 때 더 강하게 알린다.
  final bool important;
  final DateTime? purchasedAt;

  /// [오늘은 그만]을 누르면 이 시각까지 "근처예요" 알림을 보내지 않는다.
  /// 매장 안 목록과 "안 사고 나감" 알림은 계속 동작한다.
  final DateTime? snoozedUntil;

  /// 사진 파일 이름. ("이 샴푸"처럼 정확한 물건을 기억할 때) 경로는 PhotoStore가 계산한다.
  final String? photo;

  bool get isPending => purchasedAt == null;

  bool isSnoozed(DateTime now) =>
      snoozedUntil != null && now.isBefore(snoozedUntil!);

  ShoppingItem copyWith({
    String? name,
    Set<StoreCategory>? categories,
    bool? important,
    DateTime? purchasedAt,
    bool clearPurchasedAt = false,
    DateTime? snoozedUntil,
    String? photo,
    bool clearPhoto = false,
  }) {
    return ShoppingItem(
      id: id,
      name: name ?? this.name,
      categories: categories ?? this.categories,
      createdAt: createdAt,
      important: important ?? this.important,
      purchasedAt: clearPurchasedAt ? null : (purchasedAt ?? this.purchasedAt),
      snoozedUntil: snoozedUntil ?? this.snoozedUntil,
      photo: clearPhoto ? null : (photo ?? this.photo),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'categories': categories.map((c) => c.name).toList(),
    'createdAt': createdAt.toIso8601String(),
    'important': important,
    'purchasedAt': purchasedAt?.toIso8601String(),
    'snoozedUntil': snoozedUntil?.toIso8601String(),
    'photo': photo,
  };

  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) =>
        json[key] == null ? null : DateTime.parse(json[key] as String);
    return ShoppingItem(
      id: json['id'] as String,
      name: json['name'] as String,
      categories: ((json['categories'] as List?) ?? const [])
          .map((e) => StoreCategory.fromName(e as String))
          .whereType<StoreCategory>()
          .toSet(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      important: json['important'] as bool? ?? false,
      purchasedAt: date('purchasedAt'),
      snoozedUntil: date('snoozedUntil'),
      photo: json['photo'] as String?,
    );
  }
}
