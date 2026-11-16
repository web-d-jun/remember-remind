import 'dart:math' as math;

class LatLng {
  const LatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  String toString() => 'LatLng($latitude, $longitude)';
}

/// 두 좌표 사이 거리(m). Haversine 공식.
double distanceMeters(LatLng a, LatLng b) {
  const earthRadius = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLng = rad(b.longitude - a.longitude);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.latitude)) *
          math.cos(rad(b.latitude)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadius * math.asin(math.sqrt(h));
}

/// 위치 측정값 한 개.
class PositionSample {
  const PositionSample({
    required this.location,
    required this.accuracy,
    this.speed = -1,
  });

  final LatLng location;

  /// 오차 반경(m).
  final double accuracy;

  /// m/s. 모르면 음수.
  final double speed;
}
