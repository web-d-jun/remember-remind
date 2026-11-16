import '../models/shopping_item.dart';
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
        return NotificationCopy(
          '까악! $store 앞이에요',
          '여기서 $names${josa(names, '을', '를')} 살 수 있어요',
        );
      case InStoreEvent():
        return inStore(store, items);
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

  /// 매장 안에 있는 동안 고정해 두는 목록.
  static NotificationCopy inStore(String store, List<ShoppingItem> items) {
    return NotificationCopy(
      '$store에서 살 것 ${items.length}개',
      items.map((i) => '• ${i.important ? '⭐ ' : ''}${i.name}').join('\n'),
    );
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
