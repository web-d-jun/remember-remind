import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/geo.dart';
import '../core/proximity_engine.dart';
import '../data/store_cache.dart';
import '../models/store.dart';
import '../state/my_stores.dart';
import '../state/shopping_list.dart';
import 'location_wakeup.dart';
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
    required this.myStores,
    this.wakeup = const LocationWakeup(),
    ProximityEngine? engine,
  }) : engine = engine ?? ProximityEngine() {
    list.addListener(_onListChanged);
    myStores.addListener(_onMyStoresChanged);
  }

  final ShoppingList list;
  final StoreCache cache;
  final NotificationService notifications;
  final MyStores myStores;
  final LocationWakeup wakeup;
  final ProximityEngine engine;

  /// iOS에 마지막으로 넘긴 지역 목록. 같으면 다시 넘기지 않는다.
  String? _regionsKey;
  LatLng? _hereCenter;

  /// 서 있을 때는 위치 갱신이 안 오므로, 체류 시간 판단을 위해 주기적으로 엔진을 돌린다.
  static const _tickInterval = Duration(seconds: 15);

  StreamSubscription<Position>? _sub;
  Timer? _ticker;
  PositionSample? _last;
  bool _refreshing = false;

  TrackingStatus _status = TrackingStatus.idle;
  TrackingStatus get status => _status;

  Store? get currentStore => engine.currentStore;

  /// 근처 매장: 내장 데이터 검색 결과 + 직접 등록한 매장.
  List<Store> get nearbyStores {
    final last = _last;
    if (last == null) return cache.stores;
    return [
      ...cache.stores,
      ...myStores.near(
        last.location,
        list.neededCategories,
        radiusMeters: cache.searchRadius.toDouble(),
      ),
    ];
  }

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
    final always = permission == LocationPermission.always;
    _setStatus(
      always ? TrackingStatus.tracking : TrackingStatus.foregroundOnly,
    );
    _startStream();
    // 앱이 종료돼도 다시 깨어날 수 있게 한다. ("항상 허용"일 때만 동작)
    if (always) {
      await wakeup.start();
      await _updateWakeupRegions();
    }
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
    if (_regionsKey != null || status == TrackingStatus.idle) {
      _regionsKey = null;
      _hereCenter = null;
      await wakeup.stop();
    }
    _setStatus(status);
  }

  /// 살 물건이 있는 가까운 매장들과 지금 있는 곳을 iOS 지역 모니터링에 넘긴다.
  ///
  /// - 매장 원(접근 반경): 앱이 종료된 채로 매장 근처에 오면 깨어난다.
  /// - 지금 있는 곳 원(300m): 앱이 종료된 채로 집 등에서 나서면 깨어난다.
  Future<void> _updateWakeupRegions() async {
    final last = _last;
    if (last == null || _status != TrackingStatus.tracking) return;
    final pending = list.pending;
    final stores =
        nearbyStores
            .where((s) => ProximityEngine.itemsFor(s, pending).isNotEmpty)
            .toList()
          ..sort(
            (a, b) => distanceMeters(
              last.location,
              a.location,
            ).compareTo(distanceMeters(last.location, b.location)),
          );
    // 위치가 바뀔 때마다 지역을 다시 등록하지 않도록, 150m 넘게 움직였을 때만 옮긴다.
    final here = _hereCenter;
    if (here == null || distanceMeters(here, last.location) > 150) {
      _hereCenter = last.location;
    }
    final regions = [
      WakeupRegion('here', _hereCenter!, 300),
      for (final s in stores.take(LocationWakeup.maxRegions - 1))
        WakeupRegion(s.id, s.location, engine.config.approachRadius),
    ];
    final key = regions.map((r) => r.key).join('|');
    if (key == _regionsKey) return;
    _regionsKey = key;
    await wakeup.setRegions(regions);
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
      await _updateWakeupRegions();
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
      stores: nearbyStores,
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
        store,
        engine.currentStoreItems(list.pending),
        engine.currentTenants,
      );
    }
    _sync();
    _refreshStores();
  }

  void _onMyStoresChanged() {
    notifyListeners();
    _evaluate();
    _updateWakeupRegions();
  }

  @override
  void dispose() {
    list.removeListener(_onListChanged);
    myStores.removeListener(_onMyStoresChanged);
    _stop(TrackingStatus.idle);
    super.dispose();
  }

  void _setStatus(TrackingStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }
}
