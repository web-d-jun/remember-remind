import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/notification_action.dart';
import '../core/notification_copy.dart';
import '../core/proximity_engine.dart';
import '../data/photo_store.dart';
import '../models/shopping_item.dart';
import 'notification_action_bridge.dart';

typedef NotificationActionCallback =
    void Function(NotificationAction action, Set<String> itemIds);

/// 근접 이벤트를 사용자에게 보여줄 알림으로 바꾼다.
class NotificationService {
  NotificationService({
    required PhotoStore photos,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _photos = photos,
       _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final PhotoStore _photos;

  static const _inStoreId = 2000;
  static const _forgotId = 3000;

  // iOS는 버튼 묶음(category)을 미리 등록해 두고 알림마다 이름으로 고른다.
  static const _approachCategory = 'approach';
  static const _inStoreCategory = 'in_store';
  static const _forgotCategory = 'forgot';

  static final _purchasedAndroid = AndroidNotificationAction(
    NotificationAction.purchased.id,
    '샀어요',
  );
  static final _snoozeAndroid = AndroidNotificationAction(
    NotificationAction.snoozeToday.id,
    '오늘은 그만',
  );

  /// [onAction]은 앱이 떠 있을 때 버튼을 누르면 호출된다.
  /// 앱이 꺼져 있으면 [onBackgroundNotificationResponse]가 대신 처리한다.
  Future<void> init({required NotificationActionCallback onAction}) async {
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              _approachCategory,
              actions: [
                DarwinNotificationAction.plain(
                  NotificationAction.purchased.id,
                  '샀어요',
                ),
                DarwinNotificationAction.plain(
                  NotificationAction.snoozeToday.id,
                  '오늘은 그만',
                ),
              ],
            ),
            DarwinNotificationCategory(
              _inStoreCategory,
              actions: [
                DarwinNotificationAction.plain(
                  NotificationAction.purchased.id,
                  '다 샀어요',
                ),
              ],
            ),
            DarwinNotificationCategory(
              _forgotCategory,
              actions: [
                DarwinNotificationAction.plain(
                  NotificationAction.purchased.id,
                  '샀어요',
                ),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final action = NotificationAction.fromId(response.actionId);
        if (action == null) return; // 알림 본문을 누른 경우: 앱만 연다.
        onAction(action, decodeItemIds(response.payload));
      },
      onDidReceiveBackgroundNotificationResponse:
          onBackgroundNotificationResponse,
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
        final copy = NotificationCopy.of(event);
        final photo = await _photoFor(items);
        await _plugin.show(
          id: store.id.hashCode & 0x7fffffff,
          title: copy.title,
          body: copy.body,
          payload: encodeItemIds(items),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'nearby',
              '근처 매장 알림',
              channelDescription: '살 물건이 있는 매장 근처를 지날 때 알려요',
              importance: Importance.high,
              priority: Priority.high,
              largeIcon: photo?.android,
              styleInformation: photo?.bigPicture(copy),
              actions: [_purchasedAndroid, _snoozeAndroid],
            ),
            iOS: DarwinNotificationDetails(
              categoryIdentifier: _approachCategory,
              interruptionLevel: InterruptionLevel.active,
              attachments: photo?.ios,
            ),
          ),
        );
      case InStoreEvent(:final store, :final items):
        await showInStore(store.name, items);
      case LeftStoreEvent(:final items):
        await _plugin.cancel(id: _inStoreId);
        if (items.isEmpty) return;
        final copy = NotificationCopy.of(event);
        final photo = await _photoFor(items);
        await _plugin.show(
          id: _forgotId,
          title: copy.title,
          body: copy.body,
          payload: encodeItemIds(items),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'forgot',
              '빠뜨린 물건 알림',
              channelDescription: '물건을 안 사고 매장을 나설 때 알려요',
              importance: Importance.max,
              priority: Priority.max,
              category: AndroidNotificationCategory.reminder,
              largeIcon: photo?.android,
              styleInformation:
                  photo?.bigPicture(copy) ?? BigTextStyleInformation(copy.body),
              actions: [_purchasedAndroid],
            ),
            iOS: DarwinNotificationDetails(
              categoryIdentifier: _forgotCategory,
              interruptionLevel: InterruptionLevel.active,
              attachments: photo?.ios,
            ),
          ),
        );
    }
  }

  /// 매장 안에 있는 동안 고정해 두는 알림. 물건을 체크할 때마다 다시 그린다.
  /// 목록이 잘 보이도록 사진은 작은 아이콘으로만 붙인다.
  Future<void> showInStore(String storeName, List<ShoppingItem> items) async {
    if (items.isEmpty) {
      await _plugin.cancel(id: _inStoreId);
      return;
    }
    final copy = NotificationCopy.inStore(storeName, items);
    final photo = await _photoFor(items);
    await _plugin.show(
      id: _inStoreId,
      title: copy.title,
      body: copy.body,
      payload: encodeItemIds(items),
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
          largeIcon: photo?.android,
          styleInformation: BigTextStyleInformation(copy.body),
          actions: [
            AndroidNotificationAction(NotificationAction.purchased.id, '다 샀어요'),
          ],
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier: _inStoreCategory,
          presentSound: false,
          interruptionLevel: InterruptionLevel.passive,
          attachments: photo?.ios,
        ),
      ),
    );
  }

  Future<void> clearInStore() => _plugin.cancel(id: _inStoreId);

  /// 사진이 붙은 첫 물건의 사진. ("이 샴푸"를 매장에서 바로 알아보게)
  Future<_NotificationPhoto?> _photoFor(List<ShoppingItem> items) async {
    final name = items.map((i) => i.photo).whereType<String>().firstOrNull;
    if (name == null) return null;
    final file = _photos.fileOf(name);
    if (!await file.exists()) return null;
    // iOS는 알림에 붙인 파일을 옮겨 가므로 사본을 붙인다.
    final iosCopy = Platform.isIOS
        ? await _photos.notificationCopy(name)
        : null;
    return _NotificationPhoto(file.path, iosCopy);
  }
}

class _NotificationPhoto {
  _NotificationPhoto(this.path, this.iosCopyPath);

  final String path;
  final String? iosCopyPath;

  FilePathAndroidBitmap get android => FilePathAndroidBitmap(path);

  List<DarwinNotificationAttachment>? get ios =>
      iosCopyPath == null ? null : [DarwinNotificationAttachment(iosCopyPath!)];

  BigPictureStyleInformation bigPicture(NotificationCopy copy) {
    return BigPictureStyleInformation(
      android,
      contentTitle: copy.title,
      summaryText: copy.body,
      hideExpandedLargeIcon: true,
    );
  }
}
