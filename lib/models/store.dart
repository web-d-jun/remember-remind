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
    this.certain = true,
  });

  final String id;
  final String name;
  final StoreCategory category;
  final LatLng location;

  /// 대형마트처럼 넓은 매장. 매장 안에서는 GPS가 매장 좌표(보통 건물 한가운데)와
  /// 많이 어긋나므로, "근처에 몇 분 머물면 안에 있다"고 느슨하게 판단한다.
  final bool large;

  /// 그 종류의 물건을 거의 확실히 파는 매장인지.
  ///
  /// 브랜드 마트·"슈퍼"·체인 편의점·약국·다이소·직접 등록한 매장은 확실하다.
  /// 이름이 "달콤한솜사탕"인데 업종이 슈퍼마켓으로 등록된 곳처럼, 정말 파는지 모르는 개인
  /// 가게는 false다. 이런 곳은 "여기서 살 수 있어요"라고 단정하지 않고 "혹시 이 근처에…?"라고
  /// 조용히 알리며, 매장 안·안 사고 나감 알림은 보내지 않는다. (tool/build_store_data.py의 is_certain)
  final bool certain;

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
