import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/geo.dart';

/// 앱이 종료된 뒤에도 iOS가 앱을 다시 깨우게 한다. (iOS 전용, 다른 플랫폼에서는 아무것도 안 함)
///
/// iOS는 위치 스트림을 쓰던 앱이 메모리 부족 등으로 종료되면 다시 실행해 주지 않는다.
/// 대신 아래 두 가지는 앱이 종료돼 있어도 백그라운드로 앱을 실행해 준다.
/// - 주요 위치 변경(Significant Location Change): 약 500m 이상 움직였을 때
/// - 지역 모니터링: 등록한 원(최대 20개)에 들어가거나 나갈 때
///
/// 깨어나면 AppDelegate가 화면 없는 Flutter 엔진으로 `backgroundMain`을 실행하고,
/// 거기서 위치 스트림을 다시 시작한다. 네이티브 쪽은 ios/Runner/AppDelegate.swift.
class LocationWakeup {
  const LocationWakeup();

  static const _channel = MethodChannel('kkamagwi/location_wakeup');

  /// iOS 지역 모니터링 개수 제한은 앱당 20개.
  static const maxRegions = 20;

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> start() => _call('start');

  /// 깨우기를 끄고 등록한 지역도 모두 지운다. (살 물건이 없을 때)
  Future<void> stop() => _call('stop');

  /// 지켜볼 지역을 통째로 바꾼다. [maxRegions]개를 넘으면 앞에서부터 자른다.
  Future<void> setRegions(List<WakeupRegion> regions) => _call('setRegions', [
    for (final r in regions.take(maxRegions))
      {
        'id': r.id,
        'lat': r.center.latitude,
        'lng': r.center.longitude,
        'radius': r.radius,
      },
  ]);

  Future<void> _call(String method, [Object? args]) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      debugPrint('LocationWakeup.$method 실패: $e');
    } on MissingPluginException {
      // 테스트 등 네이티브 쪽이 없는 환경.
    }
  }
}

class WakeupRegion {
  const WakeupRegion(this.id, this.center, this.radius);

  final String id;
  final LatLng center;

  /// m. iOS는 너무 작은 원(약 100m 미만)은 잘 못 잡는다.
  final double radius;

  String get key =>
      '$id@${center.latitude.toStringAsFixed(5)},'
      '${center.longitude.toStringAsFixed(5)}/${radius.round()}';
}
