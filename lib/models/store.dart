import '../core/geo.dart';
import 'store_category.dart';

/// 주변의 실제 매장 하나.
class Store {
  const Store({
    required this.id,
    required this.name,
    required this.category,
    required this.location,
    this.large = false,
  });

  final String id;
  final String name;
  final StoreCategory category;
  final LatLng location;

  /// 대형마트처럼 넓은 매장. 매장 안에서는 GPS가 매장 좌표(보통 건물 한가운데)와
  /// 많이 어긋나므로, "근처에 몇 분 머물면 안에 있다"고 느슨하게 판단한다.
  final bool large;

  /// 사용자가 직접 등록한 매장인지. ([MyStores])
  bool get isUserRegistered => id.startsWith(userIdPrefix);

  static const userIdPrefix = 'user:';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category.name,
    'lat': location.latitude,
    'lng': location.longitude,
    'large': large,
  };

  /// 모르는 종류 등 읽을 수 없으면 null.
  static Store? fromJson(Map<String, dynamic> json) {
    final category = StoreCategory.fromName(json['category'] as String? ?? '');
    final lat = json['lat'];
    final lng = json['lng'];
    if (category == null || lat is! num || lng is! num) return null;
    return Store(
      id: json['id'] as String,
      name: json['name'] as String,
      category: category,
      location: LatLng(lat.toDouble(), lng.toDouble()),
      large: json['large'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) => other is Store && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Store($name, ${category.label})';
}
