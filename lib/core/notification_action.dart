import 'dart:convert';

import '../models/shopping_item.dart';

/// 알림에 붙는 버튼.
enum NotificationAction {
  /// [샀어요] 알림에 나온 물건을 산 것으로 표시한다.
  purchased('purchased'),

  /// [오늘은 그만] 알림에 나온 물건은 오늘 자정까지 "근처예요" 알림을 보내지 않는다.
  snoozeToday('snooze_today');

  const NotificationAction(this.id);

  final String id;

  static NotificationAction? fromId(String? id) {
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// 알림에 [샀어요] 버튼을 붙일지.
///
/// 버튼 한 번은 알림에 나온 물건 전부에 적용된다. 물건이 여러 개면 일부만 샀을 수
/// 있는데("우유만 사고 계란은 깜빡") 전부 산 걸로 처리되면 빠뜨린 걸 다시 알려 주지
/// 못한다. 그래서 물건이 하나일 때만 붙이고, 여러 개면 앱이나 매장 안 목록에서 체크한다.
bool offersPurchasedButton(List<ShoppingItem> items) => items.length == 1;

/// 알림 payload: 알림에 나온 물건 id 목록.
String encodeItemIds(Iterable<ShoppingItem> items) =>
    jsonEncode([for (final i in items) i.id]);

Set<String> decodeItemIds(String? payload) {
  if (payload == null || payload.isEmpty) return const {};
  try {
    return (jsonDecode(payload) as List).cast<String>().toSet();
  } on FormatException {
    return const {};
  } on TypeError {
    return const {};
  }
}

/// 버튼 동작을 목록에 적용한 결과를 돌려준다. 해당하지 않는 물건은 그대로 둔다.
List<ShoppingItem> applyNotificationAction(
  List<ShoppingItem> items,
  NotificationAction action,
  Set<String> ids,
  DateTime now,
) {
  final midnight = DateTime(now.year, now.month, now.day + 1);
  return [
    for (final item in items)
      if (!ids.contains(item.id) || !item.isPending)
        item
      else
        switch (action) {
          NotificationAction.purchased => item.copyWith(purchasedAt: now),
          NotificationAction.snoozeToday => item.copyWith(
            snoozedUntil: midnight,
          ),
        },
  ];
}
