import '../models/shopping_item.dart';
import '../models/store.dart';
import '../models/store_category.dart';
import 'geo.dart';

/// 근접 감지 엔진의 판단 결과.
sealed class ProximityEvent {
  const ProximityEvent(this.store, this.items, {this.tenants = const []});

  final Store store;

  /// 이 매장에서 살 수 있는, 아직 안 산 물건들. ([tenants]에서 사는 것 포함)
  final List<ShoppingItem> items;

  /// [store]가 대형 매장일 때, 그 안에 입점한 매장들 (이마트 안 약국 등).
  /// 대형 매장과 한 곳으로 묶어서 알린다.
  final List<Store> tenants;
}

/// 문제 1 해결: 살 수 있는 매장 근처를 지나가고 있다.
class ApproachEvent extends ProximityEvent {
  const ApproachEvent(super.store, super.items, {super.tenants});
}

/// 근처에 그 물건을 팔지도 모르는 불확실한 매장([Store.certain]이 false)들이 있다.
///
/// 확실하지 않으니 "여기서 살 수 있어요"라고 단정하지 않고 "혹시 이 근처에…?"라고 묻는다.
/// [store]는 가장 가까운 곳, [stores]는 가까운 순서로 최대 3곳.
class MaybeNearbyEvent extends ProximityEvent {
  const MaybeNearbyEvent(super.store, super.items, {required this.stores});

  final List<Store> stores;
}

/// 문제 2 해결 (1단계): 매장 안에 들어와 머무르고 있다. 남은 목록을 계속 보여준다.
class InStoreEvent extends ProximityEvent {
  const InStoreEvent(super.store, super.items, {super.tenants});
}

/// 문제 2 해결 (2단계): 매장을 떠났다.
/// [items]가 비어 있지 않으면 빠뜨린 물건이 있다는 뜻이다.
class LeftStoreEvent extends ProximityEvent {
  const LeftStoreEvent(super.store, super.items, {super.tenants});

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
    this.maxDrift = 40,
    this.largeMaxDrift = 150,
    this.tenantRadius = 30,
    this.maybeCooldown = const Duration(hours: 2),
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

  /// 체류 시간을 채우는 동안 처음 위치에서 이만큼 넘게 움직이면 머무른 게 아니라
  /// 지나가는 중으로 보고 다시 센다.
  ///
  /// 매장 안에서는 돌아다녀도 제자리 근처지만, 걸어서 지나가면 1분에 70m 넘게 움직인다.
  /// 이게 없으면 보통 걸음으로 매장 앞을 지나가기만 해도 [exitRadius] 안에서
  /// 1분이 차서 "매장에 들어갔다가 안 사고 나갔다"고 잘못 알린다.
  final double maxDrift;

  /// 대형 매장의 [maxDrift]. 넓은 매장 안을 돌아다니는 것과 GPS 흔들림을 감안한다.
  final double largeMaxDrift;

  /// 대형 매장 좌표에서 이 거리 안에 있는 다른 매장은 그 안에 입점한 것으로 본다.
  ///
  /// 매장 좌표는 주소로 찍기 때문에, 이마트 안 약국·올리브영은 마트와 거의 같은 점에
  /// 찍힌다(전국 대형마트 445곳 중 약국 132곳이 10m, 52곳이 30m 안). 따로 다루면
  /// 근처 알림이 두 번 오고, 마트 안을 돌다 약국 좌표를 지날 때 방문이 바뀌어 버린다.
  final double tenantRadius;

  /// "혹시 이 근처에…?" 알림 재발송 간격. 동네 마트의 대부분이 불확실한 매장이라,
  /// 확실한 매장 알림보다 훨씬 드물게 보낸다.
  final Duration maybeCooldown;
}

typedef _Candidate = ({
  Store store,
  double distance,
  List<ShoppingItem> items,
  List<Store> tenants,
});

/// 매장 하나에 대한 방문. 머무르는지 지켜보는 중이거나, 안에 있다고 확정된 상태.
class _Visit {
  _Visit({
    required this.store,
    required this.tenants,
    required this.since,
    required this.anchor,
    required this.dwell,
    required this.exitRadius,
    required this.maxDrift,
  });

  final Store store;

  /// [store] 안에 입점한 매장들 (대형 매장일 때만).
  final List<Store> tenants;

  final DateTime since;

  /// 체류 시간을 세기 시작한 위치. 확정 전에 여기서 [maxDrift] 넘게 움직이면 지나가는 중이다.
  final LatLng anchor;
  final double maxDrift;

  /// 이만큼 머물러야 안에 있다고 확정한다.
  final Duration dwell;

  /// 이 거리 밖으로 나가면 방문이 끝난다.
  final double exitRadius;

  bool dwelled = false;

  bool isInside(LatLng here) =>
      distanceMeters(here, store.location) <= exitRadius;

  /// 확정 전 방문을 이어갈 수 있는지. 밖으로 나갔거나 많이 움직였으면(지나가는 중) false.
  bool holds(LatLng here) =>
      isInside(here) && distanceMeters(anchor, here) <= maxDrift;
}

/// 위치 측정값을 받아 접근, 체류, 이탈 이벤트를 만든다.
///
/// 플랫폼 의존성이 없어서 위치 스트림, 타이머, 테스트 어디서든 그대로 쓸 수 있다.
class ProximityEngine {
  ProximityEngine({this.config = const ProximityConfig()});

  final ProximityConfig config;

  final Map<String, DateTime> _lastStoreApproach = {};
  final Map<StoreCategory, DateTime> _lastCategoryApproach = {};

  /// 일반 매장 방문 (40m 안에 1분).
  _Visit? _small;

  /// 대형 매장 방문 (150m 안에 5분). 일반 매장 방문과 따로 센다.
  /// 마트 안을 돌다 다른 가게 좌표 40m 안을 지나가도 마트 타이머가 끊기지 않게 하려는 것이다.
  /// (서울역처럼 가게가 많은 건물 안의 대형 매장은 이게 없으면 5분이 영영 안 찬다)
  _Visit? _large;

  _Visit? get _confirmed => (_small?.dwelled ?? false)
      ? _small
      : (_large?.dwelled ?? false)
      ? _large
      : null;

  /// 지금 "들어와 있다"고 확정된 매장. 없으면 null.
  Store? get currentStore => _confirmed?.store;

  /// [currentStore] 안에 입점한 매장들.
  List<Store> get currentTenants => _confirmed?.tenants ?? const [];

  List<ProximityEvent> update({
    required PositionSample position,
    required DateTime now,
    required List<Store> stores,
    required List<ShoppingItem> pendingItems,
  }) {
    if (position.accuracy > config.maxAccuracy) return const [];

    final events = <ProximityEvent>[];
    final here = position.location;

    // 1) 안에 있다고 확정된 매장이 있으면 떠났는지만 본다.
    //    매장 안에 있는 동안은 다른 매장 알림을 보내지 않는다.
    final confirmed = _confirmed;
    if (confirmed != null) {
      if (confirmed.isInside(here)) return events;
      events.add(
        LeftStoreEvent(
          confirmed.store,
          itemsAt(confirmed.store, confirmed.tenants, pendingItems),
          tenants: confirmed.tenants,
        ),
      );
      _small = null;
      _large = null;
    }

    // 2) 머무르는지 지켜보던 방문들의 체류 시간을 센다. 지나가는 중이었으면 없던 걸로 한다.
    if (_large case final v? when !v.holds(here)) _large = null;
    if (_small case final v? when !v.holds(here)) _small = null;
    if (_confirm(_small, now, pendingItems, events) ||
        _confirm(_large, now, pendingItems, events)) {
      return events;
    }

    // 3) 관련 물건이 있는 매장만, 가까운 순서로 본다.
    //    대형 매장에 입점한 매장은 따로 보지 않고 대형 매장에 묶는다.
    final tenantsOf = _tenantsOf(stores);
    final tenantIds = {
      for (final ts in tenantsOf.values)
        for (final t in ts) t.id,
    };
    final candidates = <_Candidate>[];
    for (final store in stores) {
      if (tenantIds.contains(store.id)) continue;
      final d = distanceMeters(here, store.location);
      if (d > config.approachRadius) continue;
      final tenants = tenantsOf[store.id] ?? const <Store>[];
      final items = itemsAt(store, tenants, pendingItems);
      if (items.isEmpty) continue;
      candidates.add((
        store: store,
        distance: d,
        items: items,
        tenants: tenants,
      ));
    }
    candidates.sort((a, b) => a.distance.compareTo(b.distance));

    // 4) 대형 매장 근처면, 몇 분 머무르는지 지켜보기 시작한다.
    if (_large == null) {
      final c = candidates
          .where((c) => c.store.large && c.distance <= config.largeInsideRadius)
          .firstOrNull;
      if (c != null) {
        _large = _Visit(
          store: c.store,
          tenants: c.tenants,
          since: now,
          anchor: here,
          dwell: config.largeDwellDuration,
          exitRadius: config.largeExitRadius,
          maxDrift: config.largeMaxDrift,
        );
        if (_confirm(_large, now, pendingItems, events)) return events;
      }
    }

    // 5) 일반 매장 좌표 가까이 왔으면, 머무르는지 지켜보기 시작한다.
    //    대형 매장은 좌표 가까이 와도 이 규칙을 쓰지 않는다. 넓은 매장 안을 돌아다니면
    //    좌표 40m 안팎을 계속 들락거리기 때문이다.
    if (_small == null) {
      final c = candidates
          // 불확실한 매장은 매장 안·안 사고 나감 알림을 보내지 않는다. 그 물건이 원래 없는
          // 가게에서 "까먹지 마, 안 샀어요!"라고 하면 안 되기 때문이다.
          .where(
            (c) =>
                !c.store.large &&
                c.store.certain &&
                c.distance <= config.insideRadius,
          )
          .firstOrNull;
      if (c != null) {
        _small = _Visit(
          store: c.store,
          tenants: const [],
          since: now,
          anchor: here,
          dwell: config.dwellDuration,
          exitRadius: config.exitRadius,
          maxDrift: config.maxDrift,
        );
        _markApproached(c.store, now);
        if (_confirm(_small, now, pendingItems, events)) return events;
      }
    }
    // 일반 매장 앞에 서 있는 동안은 다른 매장 알림을 보내지 않는다.
    if (_small != null) return events;

    // 6) 근처를 지나가는 중이면 접근 알림을 보낸다. 한 번에 한 매장만 알린다.
    //    가장 가까운 매장이 이미 알렸으면(쿨다운) 그다음 가까운 매장을 본다.
    //    (편의점 옆 약국처럼 살 물건이 다른 매장을 놓치지 않게)
    //    [오늘은 그만]으로 미뤄둔 물건은 빼고, 남는 게 없으면 알리지 않는다.
    if (position.speed > config.maxApproachSpeed) return events;
    for (final c in candidates) {
      if (!c.store.certain) continue;
      final awake = c.items.where((i) => !i.isSnoozed(now)).toList();
      if (awake.isEmpty || !_canNotifyApproach(c.store, now)) continue;
      _markApproached(c.store, now);
      // 입점 매장도 이미 알린 걸로 친다. (같은 종류 매장 쿨다운에도 반영)
      for (final t in c.tenants) {
        _markApproached(t, now);
      }
      events.add(ApproachEvent(c.store, awake, tenants: c.tenants));
      return events;
    }

    // 7) 불확실한 매장만 있는 물건은 "혹시 이 근처에…?"라고 조용히, 드물게 묻는다.
    //    근처 확실한 매장에서 살 수 있는 물건은 빼고, 남는 게 없으면 묻지 않는다.
    final maybe = _maybeNearby(candidates, now);
    if (maybe != null) events.add(maybe);
    return events;
  }

  DateTime? _lastMaybe;

  MaybeNearbyEvent? _maybeNearby(List<_Candidate> candidates, DateTime now) {
    final last = _lastMaybe;
    if (last != null && now.difference(last) < config.maybeCooldown) {
      return null;
    }
    final covered = {
      for (final c in candidates)
        if (c.store.certain) ...c.items,
    };
    final stores = <Store>[];
    final items = <ShoppingItem>[];
    for (final c in candidates) {
      if (c.store.certain) continue;
      final rest = c.items
          .where((i) => !i.isSnoozed(now) && !covered.contains(i))
          .toList();
      if (rest.isEmpty) continue;
      stores.add(c.store);
      for (final i in rest) {
        if (!items.contains(i)) items.add(i);
      }
    }
    if (stores.isEmpty) return null;
    _lastMaybe = now;
    return MaybeNearbyEvent(
      stores.first,
      items,
      stores: stores.take(3).toList(),
    );
  }

  /// 체류 시간이 찼으면 방문을 확정하고 남은 목록을 알린다. 확정했으면 true.
  /// 한 곳이 확정되면 다른 방문은 버린다. (동시에 두 매장 안에 있을 수는 없다)
  bool _confirm(
    _Visit? visit,
    DateTime now,
    List<ShoppingItem> pendingItems,
    List<ProximityEvent> events,
  ) {
    if (visit == null || visit.dwelled) return false;
    if (now.difference(visit.since) < visit.dwell) return false;
    visit.dwelled = true;
    if (identical(visit, _small)) {
      _large = null;
    } else {
      _small = null;
    }
    final items = itemsAt(visit.store, visit.tenants, pendingItems);
    if (items.isNotEmpty) {
      events.add(InStoreEvent(visit.store, items, tenants: visit.tenants));
    }
    return true;
  }

  /// 대형 매장 id → 그 안에 입점한 것으로 보이는 매장들.
  /// 한 매장이 대형 매장 두 곳에 걸치면 더 가까운 쪽에 넣는다.
  Map<String, List<Store>> _tenantsOf(List<Store> stores) {
    final larges = stores.where((s) => s.large).toList();
    if (larges.isEmpty) return const {};
    final result = <String, List<Store>>{};
    for (final s in stores) {
      if (s.large) continue;
      Store? host;
      var best = config.tenantRadius;
      for (final l in larges) {
        final d = distanceMeters(s.location, l.location);
        if (d <= best) {
          best = d;
          host = l;
        }
      }
      if (host != null) (result[host.id] ??= []).add(s);
    }
    return result;
  }

  /// 물건 체크 상태가 바뀌었을 때, 매장 안 목록을 다시 계산한다.
  List<ShoppingItem> currentStoreItems(List<ShoppingItem> pendingItems) {
    final visit = _confirmed;
    return visit == null
        ? const []
        : itemsAt(visit.store, visit.tenants, pendingItems);
  }

  static List<ShoppingItem> itemsFor(Store store, List<ShoppingItem> items) =>
      itemsAt(store, const [], items);

  /// [store]와 그 안에 입점한 [tenants] 중 한 곳에서라도 살 수 있는 안 산 물건.
  static List<ShoppingItem> itemsAt(
    Store store,
    List<Store> tenants,
    List<ShoppingItem> items,
  ) {
    final categories = {store.category, for (final t in tenants) t.category};
    return items
        .where((i) => i.isPending && i.categories.any(categories.contains))
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
