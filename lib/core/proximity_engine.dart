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
    this.largeInsideRadius = 150,
    this.largeExitRadius = 250,
    this.largeDwellDuration = const Duration(minutes: 5),
  }) : assert(largeInsideRadius <= approachRadius);

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

  // --- 대형 매장 ([Store.large]) ---
  // 마트 안에서는 GPS가 매장 좌표에서 100m 넘게 어긋나기도 해서 [insideRadius]로는
  // 안에 들어온 걸 못 잡는다. 대신 "근처에 몇 분 머물면 안에 있다"고 보고,
  // 크게 벗어나야 떠났다고 본다.

  /// 대형 매장에서 이 거리 안에 [largeDwellDuration] 동안 머물면 안에 있다고 본다.
  final double largeInsideRadius;

  /// 대형 매장에서 이 거리 밖으로 나가야 떠났다고 본다.
  final double largeExitRadius;

  /// 대형 매장 근처에 이만큼 머물러야 "들어갔다"고 본다.
  /// 주차장이나 앞길을 잠깐 지나는 경우를 거르려고 [dwellDuration]보다 길게 잡는다.
  final Duration largeDwellDuration;
}

class _VisitState {
  _VisitState(
    this.since, {
    required this.dwell,
    required this.exitRadius,
    this.loose = false,
  });

  final DateTime since;

  /// 이만큼 머물러야 안에 있다고 확정한다.
  Duration dwell;

  /// 이 거리 밖으로 나가면 방문이 끝난다.
  final double exitRadius;

  /// 대형 매장 근처에 머무르기만 한 상태(아직 매장 좌표 가까이 오지 않음).
  /// 확정 전에는 지나가는 다른 매장 알림을 막지 않는다.
  bool loose;

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
      if (d > visit.exitRadius) {
        if (visit.dwelled) {
          events.add(
            LeftStoreEvent(visitStore, itemsFor(visitStore, pendingItems)),
          );
        }
        _visitStore = null;
        _visit = null;
      } else {
        _checkDwell(visitStore, visit, now, pendingItems, events);
        // 매장 안에 있는 동안은 다른 매장 알림을 보내지 않는다.
        // 대형 매장 근처에 머무르기만 하는 중이면 아래 판단을 계속한다.
        if (!visit.loose) return events;
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
      final current = _visit;
      if (current != null && _visitStore == nearest.store) {
        // 근처에서 머무르던 대형 매장의 좌표 가까이 왔다. 기다린 시간은 그대로 두고
        // 일반 매장처럼 짧게 확정한다.
        current
          ..loose = false
          ..dwell = config.dwellDuration;
        _checkDwell(nearest.store, current, now, pendingItems, events);
        return events;
      }
      final visit = _VisitState(
        now,
        dwell: config.dwellDuration,
        exitRadius: _exitRadiusOf(nearest.store),
      );
      _visitStore = nearest.store;
      _visit = visit;
      _markApproached(nearest.store, now);
      _checkDwell(nearest.store, visit, now, pendingItems, events);
      return events;
    }

    // 4) 근처를 지나가는 중이면 접근 알림을 보낸다.
    //    [오늘은 그만]으로 미뤄둔 물건은 빼고, 남는 게 없으면 알리지 않는다.
    final tooFast = position.speed > config.maxApproachSpeed;
    final awake = nearest.items.where((i) => !i.isSnoozed(now)).toList();
    if (!tooFast &&
        awake.isNotEmpty &&
        _canNotifyApproach(nearest.store, now)) {
      _markApproached(nearest.store, now);
      events.add(ApproachEvent(nearest.store, awake));
    }

    // 5) 대형 매장 근처면, 몇 분 머무르는지 지켜보기 시작한다.
    if (_visit == null) {
      for (final c in candidates) {
        if (!c.store.large || c.distance > config.largeInsideRadius) continue;
        _visitStore = c.store;
        _visit = _VisitState(
          now,
          dwell: config.largeDwellDuration,
          exitRadius: config.largeExitRadius,
          loose: true,
        );
        break;
      }
    }
    return events;
  }

  /// 체류 시간이 찼으면 방문을 확정하고 남은 목록을 알린다.
  void _checkDwell(
    Store store,
    _VisitState visit,
    DateTime now,
    List<ShoppingItem> pendingItems,
    List<ProximityEvent> events,
  ) {
    if (visit.dwelled || now.difference(visit.since) < visit.dwell) return;
    visit
      ..dwelled = true
      ..loose = false;
    final items = itemsFor(store, pendingItems);
    if (items.isNotEmpty) events.add(InStoreEvent(store, items));
  }

  double _exitRadiusOf(Store store) =>
      store.large ? config.largeExitRadius : config.exitRadius;

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
