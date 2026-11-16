import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/geo.dart';
import '../core/proximity_engine.dart';
import '../data/store_cache.dart';
import '../models/store.dart';
import '../state/shopping_list.dart';
import 'notification_service.dart';

enum TrackingStatus {
  /// 살 물건이 없어서 위치를 안 본다. (배터리 절약)
  idle,

  /// 위치 권한이 없다.
  noPermission,

  /// 앱을 쓰는 중에만 위치 권한이 있다. 백그라운드 알림이 안 된다.
  foregroundOnly,

  /// 위치 서비스(GPS)가 꺼져 있다.
  serviceDisabled,

  tracking,
}

/// 위치를 받아 근접 엔진에 넣고, 나온 이벤트를 알림으로 보낸다.
///
/// 살 물건이 있을 때만 위치를 추적한다.
class LocationTracker extends ChangeNotifier {
  LocationTracker({
    required this.list,
    required this.cache,
    required this.notifications,
    ProximityEngine? engine,
  }) : engine = engine ?? ProximityEngine() {
    list.addListener(_onListChanged);
  }

  final ShoppingList list;
  final StoreCache cache;
  final NotificationService notifications;
  final ProximityEngine engine;

  /// 서 있을 때는 위치 갱신이 안 오므로, 체류 시간 판단을 위해 주기적으로 엔진을 돌린다.
  static const _tickInterval = Duration(seconds: 15);

  StreamSubscription<Position>? _sub;
  Timer? _ticker;
  PositionSample? _last;
  bool _refreshing = false;

  TrackingStatus _status = TrackingStatus.idle;
  TrackingStatus get status => _status;

  Store? get currentStore => engine.currentStore;
  List<Store> get nearbyStores => cache.stores;
  PositionSample? get lastPosition => _last;

  Future<void> start() => _sync();

  /// 사용자가 버튼을 눌렀을 때 권한을 요청한다.
  Future<void> requestPermissions() async {
    await notifications.requestPermission();
    var whenInUse = await Permission.locationWhenInUse.request();
    if (whenInUse.isGranted) {
      // Android 11+ / iOS 모두 "항상 허용"은 앱 사용 중 허용 다음에 따로 요청해야 한다.
      final always = await Permission.locationAlways.request();
      if (always.isPermanentlyDenied) await openAppSettings();
    } else if (whenInUse.isPermanentlyDenied) {
      await openAppSettings();
    }
    await _sync();
  }

  Future<void> _sync() async {
    final needsTracking = list.pending.isNotEmpty;
    if (!needsTracking) {
      await _stop(TrackingStatus.idle);
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      await _stop(TrackingStatus.serviceDisabled);
      return;
    }
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      await _stop(TrackingStatus.noPermission);
      return;
    }
    _setStatus(
      permission == LocationPermission.always
          ? TrackingStatus.tracking
          : TrackingStatus.foregroundOnly,
    );
    _startStream();
  }

  void _startStream() {
    if (_sub != null) return;
    _sub = Geolocator.getPositionStream(
      locationSettings: _settings(),
    ).listen(_onPosition, onError: (_) {});
    _ticker = Timer.periodic(_tickInterval, (_) => _evaluate());
  }

  LocationSettings _settings() {
    const distanceFilter = 10;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilter,
          intervalDuration: const Duration(seconds: 10),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: '까마귀가 기억하고 있어요',
            notificationText: '근처에 살 곳이 있으면 귀띔해 줄게요',
            notificationChannelName: '위치 추적',
            enableWakeLock: true,
          ),
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: distanceFilter,
          activityType: ActivityType.fitness,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: false,
        );
      default:
        return const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilter,
        );
    }
  }

  Future<void> _stop(TrackingStatus status) async {
    await _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
    _setStatus(status);
  }

  void _onPosition(Position p) {
    _last = PositionSample(
      location: LatLng(p.latitude, p.longitude),
      accuracy: p.accuracy,
      speed: p.speed,
    );
    _refreshStores();
    _evaluate();
  }

  Future<void> _refreshStores() async {
    final last = _last;
    if (last == null || _refreshing) return;
    _refreshing = true;
    try {
      await cache.refresh(
        center: last.location,
        categories: list.neededCategories,
        now: DateTime.now(),
      );
      notifyListeners();
      _evaluate();
    } finally {
      _refreshing = false;
    }
  }

  void _evaluate() {
    final last = _last;
    if (last == null) return;
    final before = engine.currentStore;
    final events = engine.update(
      position: last,
      now: DateTime.now(),
      stores: cache.stores,
      pendingItems: list.pending,
    );
    for (final e in events) {
      notifications.handle(e);
    }
    if (events.isNotEmpty || before != engine.currentStore) notifyListeners();
  }

  void _onListChanged() {
    // 매장 안에서 물건을 체크하면 고정 알림의 목록도 바로 줄어든다.
    final store = engine.currentStore;
    if (store != null) {
      notifications.showInStore(
        store.name,
        engine.currentStoreItems(list.pending),
      );
    }
    _sync();
    _refreshStores();
  }

  @override
  void dispose() {
    list.removeListener(_onListChanged);
    _stop(TrackingStatus.idle);
    super.dispose();
  }

  void _setStatus(TrackingStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }
}
