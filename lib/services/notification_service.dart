import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/proximity_engine.dart';
import '../models/shopping_item.dart';

/// 근접 이벤트를 사용자에게 보여줄 알림으로 바꾼다.
class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _inStoreId = 2000;
  static const _forgotId = 3000;

  static const _nearbyChannel = AndroidNotificationDetails(
    'nearby',
    '근처 매장 알림',
    channelDescription: '살 물건이 있는 매장 근처를 지날 때 알려요',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const _forgotChannel = AndroidNotificationDetails(
    'forgot',
    '빠뜨린 물건 알림',
    channelDescription: '물건을 안 사고 매장을 나설 때 알려요',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.reminder,
  );

  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
  }

  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  Future<void> handle(ProximityEvent event) async {
    switch (event) {
      case ApproachEvent(:final store, :final items):
        await _plugin.show(
          id: store.id.hashCode & 0x7fffffff,
          title: '${store.name} 근처예요',
          body: '여기서 ${_names(items)}${_object(items)} 살 수 있어요',
          notificationDetails: const NotificationDetails(
            android: _nearbyChannel,
            iOS: DarwinNotificationDetails(
              interruptionLevel: InterruptionLevel.active,
            ),
          ),
        );
      case InStoreEvent(:final store, :final items):
        await showInStore(store.name, items);
      case LeftStoreEvent(:final store, :final items):
        await _plugin.cancel(id: _inStoreId);
        if (items.isEmpty) return;
        final important = items.any((i) => i.important);
        await _plugin.show(
          id: _forgotId,
          title: important
              ? '잠깐! ${_names(items)} 꼭 사야 해요'
              : '${_names(items)} 안 사셨어요!',
          body:
              '${store.name}에서 아직 안 샀어요. 지금 돌아가면 금방이에요. '
              '이미 샀다면 앱에서 체크해 주세요.',
          notificationDetails: const NotificationDetails(
            android: _forgotChannel,
            iOS: DarwinNotificationDetails(
              interruptionLevel: InterruptionLevel.active,
            ),
          ),
        );
    }
  }

  /// 매장 안에 있는 동안 고정해 두는 알림. 물건을 체크할 때마다 다시 그린다.
  Future<void> showInStore(String storeName, List<ShoppingItem> items) async {
    if (items.isEmpty) {
      await _plugin.cancel(id: _inStoreId);
      return;
    }
    final body = items
        .map((i) => '• ${i.important ? '⭐ ' : ''}${i.name}')
        .join('\n');
    await _plugin.show(
      id: _inStoreId,
      title: '$storeName에서 살 것 ${items.length}개',
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'in_store',
          '매장 안 목록',
          channelDescription: '매장에 있는 동안 남은 물건을 계속 보여줘요',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(
          presentSound: false,
          interruptionLevel: InterruptionLevel.passive,
        ),
      ),
    );
  }

  Future<void> clearInStore() => _plugin.cancel(id: _inStoreId);

  static String _names(List<ShoppingItem> items) {
    if (items.length <= 2) return items.map((i) => i.name).join(', ');
    return '${items.take(2).map((i) => i.name).join(', ')} 외 ${items.length - 2}개';
  }

  /// 마지막 글자 받침에 따라 "을/를".
  static String _object(List<ShoppingItem> items) {
    final last = _names(items);
    if (last.isEmpty) return '을';
    final code = last.codeUnitAt(last.length - 1);
    if (code < 0xAC00 || code > 0xD7A3) return '을(를)';
    return (code - 0xAC00) % 28 == 0 ? '를' : '을';
  }
}
