import '../core/geo.dart';
import 'store_category.dart';

/// 주변의 실제 매장 하나.
class Store {
  const Store({
    required this.id,
    required this.name,
    required this.category,
    required this.location,
  });

  final String id;
  final String name;
  final StoreCategory category;
  final LatLng location;

  @override
  bool operator ==(Object other) => other is Store && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Store($name, ${category.label})';
}
