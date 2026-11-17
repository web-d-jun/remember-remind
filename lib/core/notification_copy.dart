import '../models/shopping_item.dart';
import '../models/store.dart';
import 'proximity_engine.dart';

/// 알림 문구. 까마귀가 귀띔해 주는 말투로 쓴다.
///
/// 문구만 따로 두어 테스트하고 다듬기 쉽게 한다.
class NotificationCopy {
  const NotificationCopy(this.title, this.body);

  final String title;
  final String body;

  factory NotificationCopy.of(ProximityEvent event) {
    final store = event.store.name;
    final items = event.items;
    final names = itemNames(items);
    switch (event) {
      case ApproachEvent():
        // 이마트 앞에서 감기약을 알리면 어리둥절하니, 안에 있는 매장을 알려준다.
        final inside = {
          for (final i in items) ?insideLabel(i, event.store, event.tenants),
        }.join(', ');
        return NotificationCopy(
          '까악! $store 앞이에요',
          '여기서 $names${josa(names, '을', '를')} 살 수 있어요'
              '${inside.isEmpty ? '' : ' (안에 $inside${josa(inside, '이', '가')} 있어요)'}',
        );
      case InStoreEvent():
        return inStore(event.store, items, event.tenants);
      case LeftStoreEvent():
        final important = items.where((i) => i.important).toList();
        final title = important.isEmpty
            ? '까먹지 마, 귀가 전에!'
            : '까악! ${itemNames(important)}${josa(itemNames(important), '은', '는')} 꼭 사야 해요';
        return NotificationCopy(
          title,
          '$store에서 $names${josa(names, '을', '를')} 안 샀어요. '
          '지금 돌아가면 금방이에요',
        );
    }
  }

  /// 매장 안에 있는 동안 고정해 두는 목록. 입점 매장에서 살 물건은 어디서 사는지 붙인다.
  /// ("• 감기약 (약국)")
  static NotificationCopy inStore(
    Store store,
    List<ShoppingItem> items, [
    List<Store> tenants = const [],
  ]) {
    return NotificationCopy(
      '${store.name}에서 살 것 ${items.length}개',
      items
          .map((i) {
            final inside = insideLabel(i, store, tenants);
            return '• ${i.important ? '⭐ ' : ''}${i.name}'
                '${inside == null ? '' : ' ($inside)'}';
          })
          .join('\n'),
    );
  }

  /// [item]을 [store] 안에 입점한 매장에서 사야 하면 그 매장 종류 이름("약국").
  /// [store]에서 바로 살 수 있으면 null.
  static String? insideLabel(
    ShoppingItem item,
    Store store,
    List<Store> tenants,
  ) {
    if (item.categories.contains(store.category)) return null;
    for (final t in tenants) {
      if (item.categories.contains(t.category)) return t.category.label;
    }
    return null;
  }

  /// "우유", "우유, 건전지", "우유, 건전지 외 2개"
  static String itemNames(List<ShoppingItem> items) {
    if (items.length <= 2) return items.map((i) => i.name).join(', ');
    final first = items.take(2).map((i) => i.name).join(', ');
    return '$first 외 ${items.length - 2}개';
  }

  /// 마지막 글자 받침에 따라 조사를 고른다. ("우유를", "건전지를", "감기약을")
  /// 한글이 아니면 둘 다 보여준다. ("AA을(를)")
  static String josa(String word, String withFinal, String withoutFinal) {
    if (word.isEmpty) return withFinal;
    final code = word.codeUnitAt(word.length - 1);
    if (code < 0xAC00 || code > 0xD7A3) return '$withFinal($withoutFinal)';
    return (code - 0xAC00) % 28 == 0 ? withoutFinal : withFinal;
  }
}
