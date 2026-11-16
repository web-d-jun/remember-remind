import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/notification_action.dart';
import '../data/item_repository.dart';
import '../state/shopping_list.dart';

/// 알림 버튼은 앱 화면과 다른 isolate에서 처리될 수 있다.
/// 앱이 살아 있으면 이 이름의 포트로 넘겨서 화면의 목록이 바로 바뀌게 하고,
/// 앱이 꺼져 있으면 저장소에 직접 쓴다.
const _portName = 'kkamagwi.notification_actions';

/// 앱이 백그라운드이거나 꺼져 있을 때 알림 버튼을 누르면 별도 isolate에서 호출된다.
@pragma('vm:entry-point')
Future<void> onBackgroundNotificationResponse(
  NotificationResponse response,
) async {
  final action = NotificationAction.fromId(response.actionId);
  if (action == null) return;

  final mainIsolate = IsolateNameServer.lookupPortByName(_portName);
  if (mainIsolate != null) {
    mainIsolate.send([action.id, response.payload]);
    return;
  }

  DartPluginRegistrant.ensureInitialized();
  final repo = ItemRepository(await SharedPreferences.getInstance());
  await repo.save(
    applyNotificationAction(
      repo.load(),
      action,
      decodeItemIds(response.payload),
      DateTime.now(),
    ),
  );
}

/// 앱 화면 쪽 isolate에서 백그라운드 isolate가 넘긴 버튼 동작을 받는다.
class NotificationActionReceiver {
  NotificationActionReceiver(this._list);

  final ShoppingList _list;
  final _port = ReceivePort();

  void start() {
    IsolateNameServer.removePortNameMapping(_portName);
    IsolateNameServer.registerPortWithName(_port.sendPort, _portName);
    _port.listen((message) {
      if (message is! List || message.length != 2) return;
      final action = NotificationAction.fromId(message[0] as String?);
      if (action == null) return;
      _list.applyAction(action, decodeItemIds(message[1] as String?));
    });
  }
}
