import '../models/shopping_item.dart';
import '../models/store.dart';
import '../models/store_category.dart';
import 'geo.dart';

/// 근접 감지 엔진의 판단 결과.
sealed class ProximityEvent {
  const ProximityEvent(this.store, this.items);

  final Store store;

  /// 이 매장에서 살 수 있는, 아직 안 산 물건들.
  final List<ShoppingItem> items;
}

/// 문제 1 해결: 살 수 있는 매장 근처를 지나가고 있다.
class ApproachEvent extends ProximityEvent {
  const ApproachEvent(super.store, super.items);
}

/// 문제 2 해결 (1단계): 매장 안에 들어와 머무르고 있다. 남은 목록을 계속 보여준다.
class InStoreEvent extends ProximityEvent {
  const InStoreEvent(super.store, super.items);
}

/// 문제 2 해결 (2단계): 매장을 떠났다.
/// [items]가 비어 있지 않으면 빠뜨린 물건이 있다는 뜻이다.
class LeftStoreEvent extends ProximityEvent {
  const LeftStoreEvent(super.store, super.items);

  bool get forgotSomething => items.isNotEmpty;
}

class ProximityConfig {
  const ProximityConfig({
    this.approachRadius = 150,
    this.insideRadius = 40,
    this.exitRadius = 80,
    this.dwellDuration = const Duration(seconds: 60),
    this.maxApproachSpeed = 7,
    this.maxAccuracy = 100,
    this.storeCooldown = const Duration(hours: 3),
    this.categoryCooldown = const Duration(minutes: 30),
  });

  /// 이 거리 안에 들어오면 "근처에 있어요" 알림.
  final double approachRadius;

  /// 이 거리 안이면 매장 안에 있다고 본다.
  final double insideRadius;

  /// 이 거리 밖으로 나가야 매장을 떠났다고 본다.
  /// [insideRadius]보다 크게 잡아 GPS 흔들림으로 들락날락하는 걸 막는다.
  final double exitRadius;

  /// 이만큼 머물러야 "들어갔다"고 본다. 앞을 지나가기만 한 경우를 거른다.
  final Duration dwellDuration;

  /// 이보다 빠르면(m/s, 약 25km/h) 차량 이동으로 보고 접근 알림을 생략한다.
  final double maxApproachSpeed;

  /// 오차가 이보다 큰 측정값은 무시한다.
  final double maxAccuracy;

  /// 같은 매장에 대한 접근 알림 재발송 간격.
  final Duration storeCooldown;

  /// 같은 종류 매장(예: 편의점)에 대한 접근 알림 재발송 간격.
  /// 편의점 세 곳을 연달아 지나갈 때 세 번 울리지 않게 한다.
  final Duration categoryCooldown;
}

class _VisitState {
  _VisitState(this.since);

  final DateTime since;
  bool dwelled = false;
}

/// 위치 측정값을 받아 접근, 체류, 이탈 이벤트를 만든다.
///
/// 플랫폼 의존성이 없어서 위치 스트림, 타이머, 테스트 어디서든 그대로 쓸 수 있다.
class ProximityEngine {
  ProximityEngine({this.config = const ProximityConfig()});

  final ProximityConfig config;

  final Map<String, DateTime> _lastStoreApproach = {};
  final Map<StoreCategory, DateTime> _lastCategoryApproach = {};

  Store? _visitStore;
  _VisitState? _visit;

  /// 지금 "들어와 있다"고 확정된 매장. 없으면 null.
  Store? get currentStore => (_visit?.dwelled ?? false) ? _visitStore : null;

  List<ProximityEvent> update({
    required PositionSample position,
    required DateTime now,
    required List<Store> stores,
    required List<ShoppingItem> pendingItems,
  }) {
    if (position.accuracy > config.maxAccuracy) return const [];

    final events = <ProximityEvent>[];
    final here = position.location;

    // 1) 방문 중인 매장이 있으면 체류/이탈부터 판단한다.
    final visitStore = _visitStore;
    final visit = _visit;
    if (visitStore != null && visit != null) {
      final d = distanceMeters(here, visitStore.location);
      if (d > config.exitRadius) {
        if (visit.dwelled) {
          events.add(
            LeftStoreEvent(visitStore, itemsFor(visitStore, pendingItems)),
          );
        }
        _visitStore = null;
        _visit = null;
      } else {
        if (!visit.dwelled &&
            now.difference(visit.since) >= config.dwellDuration) {
          visit.dwelled = true;
          final items = itemsFor(visitStore, pendingItems);
          if (items.isNotEmpty) events.add(InStoreEvent(visitStore, items));
        }
        // 매장 안에 있는 동안은 다른 매장 알림을 보내지 않는다.
        return events;
      }
    }

    // 2) 관련 물건이 있는 매장만, 가까운 순서로 본다.
    final candidates =
        <({Store store, double distance, List<ShoppingItem> items})>[];
    for (final store in stores) {
      final items = itemsFor(store, pendingItems);
      if (items.isEmpty) continue;
      final d = distanceMeters(here, store.location);
      if (d <= config.approachRadius) {
        candidates.add((store: store, distance: d, items: items));
      }
    }
    if (candidates.isEmpty) return events;
    candidates.sort((a, b) => a.distance.compareTo(b.distance));
    final nearest = candidates.first;

    // 3) 매장 안으로 들어왔으면 방문을 시작한다. (체류 시간이 차야 확정)
    if (nearest.distance <= config.insideRadius) {
      _visitStore = nearest.store;
      _visit = _VisitState(now);
      _markApproached(nearest.store, now);
      if (config.dwellDuration == Duration.zero) {
        _visit!.dwelled = true;
        events.add(InStoreEvent(nearest.store, nearest.items));
      }
      return events;
    }

    // 4) 근처를 지나가는 중이면 접근 알림을 보낸다.
    final tooFast = position.speed > config.maxApproachSpeed;
    if (!tooFast && _canNotifyApproach(nearest.store, now)) {
      _markApproached(nearest.store, now);
      events.add(ApproachEvent(nearest.store, nearest.items));
    }
    return events;
  }

  /// 물건 체크 상태가 바뀌었을 때, 매장 안 목록을 다시 계산한다.
  List<ShoppingItem> currentStoreItems(List<ShoppingItem> pendingItems) {
    final store = currentStore;
    return store == null ? const [] : itemsFor(store, pendingItems);
  }

  static List<ShoppingItem> itemsFor(Store store, List<ShoppingItem> items) {
    return items
        .where((i) => i.isPending && i.categories.contains(store.category))
        .toList();
  }

  bool _canNotifyApproach(Store store, DateTime now) {
    final lastStore = _lastStoreApproach[store.id];
    if (lastStore != null && now.difference(lastStore) < config.storeCooldown) {
      return false;
    }
    final lastCategory = _lastCategoryApproach[store.category];
    if (lastCategory != null &&
        now.difference(lastCategory) < config.categoryCooldown) {
      return false;
    }
    return true;
  }

  void _markApproached(Store store, DateTime now) {
    _lastStoreApproach[store.id] = now;
    _lastCategoryApproach[store.category] = now;
  }
}
