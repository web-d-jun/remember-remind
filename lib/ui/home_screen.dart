import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../core/proximity_engine.dart';
import '../models/shopping_item.dart';
import '../services/location_tracker.dart';
import '../state/shopping_list.dart';
import 'add_item_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _showPurchased = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 설정 앱에서 권한을 바꾸고 돌아왔을 수 있다.
    if (state == AppLifecycleState.resumed) {
      context.read<LocationTracker>().start();
    }
  }

  Future<void> _add() async {
    final draft = await AddItemSheet.show(context);
    if (draft == null || !mounted) return;
    await context.read<ShoppingList>().add(
      draft.name,
      draft.categories,
      important: draft.important,
    );
  }

  Future<void> _edit(ShoppingItem item) async {
    final draft = await AddItemSheet.show(context, initial: item);
    if (draft == null || !mounted) return;
    await context.read<ShoppingList>().update(
      item.copyWith(
        name: draft.name,
        categories: draft.categories,
        important: draft.important,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = context.watch<ShoppingList>();
    final tracker = context.watch<LocationTracker>();
    final pending = list.pending;
    final purchased = list.purchased;

    return Scaffold(
      appBar: AppBar(title: const Text('빠짐없이')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('살 물건'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _InStoreBanner(tracker: tracker, pending: pending),
          _StatusCard(tracker: tracker),
          if (pending.isEmpty)
            const _EmptyState()
          else
            for (final item in pending)
              _ItemTile(item: item, onEdit: () => _edit(item)),
          if (purchased.isNotEmpty) ...[
            const Divider(height: 32),
            ListTile(
              title: Text('산 물건 ${purchased.length}개'),
              trailing: Icon(
                _showPurchased ? Icons.expand_less : Icons.expand_more,
              ),
              onTap: () => setState(() => _showPurchased = !_showPurchased),
            ),
            if (_showPurchased) ...[
              for (final item in purchased)
                _ItemTile(item: item, onEdit: () => _edit(item)),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton(
                    onPressed: list.clearPurchased,
                    child: const Text('산 물건 지우기'),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// 매장 안에 있을 때 맨 위에 크게 보여준다. 체크하면 바로 빠진다.
class _InStoreBanner extends StatelessWidget {
  const _InStoreBanner({required this.tracker, required this.pending});

  final LocationTracker tracker;
  final List<ShoppingItem> pending;

  @override
  Widget build(BuildContext context) {
    final store = tracker.currentStore;
    if (store == null) return const SizedBox.shrink();
    final items = ProximityEngine.itemsFor(store, pending);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: items.isEmpty
          ? scheme.secondaryContainer
          : scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '지금 ${store.name}에 있어요',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              items.isEmpty
                  ? '여기서 살 건 다 샀어요 👍'
                  : '나가기 전에 꼭: ${items.map((i) => i.name).join(', ')}',
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.tracker});

  final LocationTracker tracker;

  @override
  Widget build(BuildContext context) {
    final (
      IconData icon,
      String text,
      String? action,
      VoidCallback? onTap,
    ) = switch (tracker.status) {
      TrackingStatus.idle => (
        Icons.check_circle_outline,
        '살 물건이 없어서 위치를 쓰지 않고 있어요',
        null,
        null,
      ),
      TrackingStatus.noPermission => (
        Icons.location_off_outlined,
        '근처 매장을 알려드리려면 위치 권한이 필요해요',
        '허용하기',
        tracker.requestPermissions,
      ),
      TrackingStatus.foregroundOnly => (
        Icons.warning_amber_outlined,
        '앱을 닫으면 알림이 안 와요. 위치 권한을 "항상 허용"으로 바꿔주세요',
        '설정',
        tracker.requestPermissions,
      ),
      TrackingStatus.serviceDisabled => (
        Icons.gps_off,
        '휴대폰의 위치 서비스가 꺼져 있어요',
        '켜기',
        Geolocator.openLocationSettings,
      ),
      TrackingStatus.tracking => (
        Icons.near_me_outlined,
        tracker.nearbyStores.isEmpty
            ? '살 물건을 기억하는 중이에요'
            : '근처 매장 ${tracker.nearbyStores.length}곳을 지켜보는 중이에요',
        null,
        null,
      ),
    };

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        trailing: action == null
            ? null
            : TextButton(onPressed: onTap, child: Text(action)),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onEdit});

  final ShoppingItem item;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final list = context.read<ShoppingList>();
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: theme.colorScheme.errorContainer,
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => list.remove(item),
      child: ListTile(
        leading: Checkbox(
          value: !item.isPending,
          onChanged: (_) => list.togglePurchased(item),
        ),
        title: Text(
          item.name,
          style: item.isPending
              ? null
              : const TextStyle(decoration: TextDecoration.lineThrough),
        ),
        subtitle: Text(item.categories.map((c) => c.label).join(' · ')),
        trailing: item.important && item.isPending
            ? Icon(Icons.star, color: theme.colorScheme.tertiary)
            : null,
        onTap: onEdit,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text('살 물건을 적어두세요', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '살 수 있는 매장 근처를 지나면 알려드리고,\n'
            '안 사고 매장을 나서면 다시 알려드릴게요.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
