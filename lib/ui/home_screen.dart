import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';

import '../core/proximity_engine.dart';
import '../models/shopping_item.dart';
import '../data/photo_store.dart';
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
    _setUpShortcuts();
  }

  /// 앱 아이콘을 길게 누르면 바로 말하거나 찍을 수 있게 한다.
  /// 잠금 해제 → 앱 열기 → 버튼 찾기 단계를 건너뛴다.
  void _setUpShortcuts() {
    const quickActions = QuickActions();
    quickActions.initialize((type) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // 이미 열린 시트가 있으면 닫고 새로 연다.
        Navigator.of(context).popUntil((route) => route.isFirst);
        _add(type == _photoShortcut ? AddStart.photo : AddStart.voice);
      });
    });
    quickActions.setShortcutItems(const [
      ShortcutItem(type: _voiceShortcut, localizedTitle: '말로 기억하기'),
      ShortcutItem(type: _photoShortcut, localizedTitle: '사진으로 기억하기'),
    ]);
  }

  static const _voiceShortcut = 'add_voice';
  static const _photoShortcut = 'add_photo';

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 앱이 꺼져 있을 때 알림 버튼으로 바뀐 목록을 다시 읽는다.
      context.read<ShoppingList>().reload();
      // 설정 앱에서 권한을 바꾸고 돌아왔을 수 있다.
      context.read<LocationTracker>().start();
    }
  }

  Future<void> _add([AddStart start = AddStart.text]) async {
    final list = context.read<ShoppingList>();
    final messenger = ScaffoldMessenger.of(context);
    final added = await AddItemSheet.show(context, start: start);
    if (added.isEmpty || !mounted) return;
    // 확인 없이 저장했으니, 잘못 들었으면 바로 되돌릴 수 있게 한다.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${added.map((i) => i.name).join(', ')} 기억했어요'),
          action: SnackBarAction(
            label: '되돌리기',
            onPressed: () => list.removeAll(added),
          ),
        ),
      );
  }

  Future<void> _edit(ShoppingItem item) =>
      AddItemSheet.show(context, initial: item);

  @override
  Widget build(BuildContext context) {
    final list = context.watch<ShoppingList>();
    final tracker = context.watch<LocationTracker>();
    final pending = list.pending;
    final purchased = list.purchased;

    return Scaffold(
      appBar: AppBar(title: const Text('까마귀')),
      // 생각난 순간 바로 저장할 수 있게, 말하기와 사진 찍기를 한 번에 연다.
      // 생각난 순간 바로 저장: 말하기가 가장 크고, 사진·글자는 작게 둔다.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'text',
            tooltip: '글자로 기억하기',
            onPressed: () => _add(AddStart.text),
            child: const Icon(Icons.keyboard_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.small(
            heroTag: 'photo',
            tooltip: '사진으로 기억하기',
            onPressed: () => _add(AddStart.photo),
            child: const Icon(Icons.photo_camera_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'voice',
            onPressed: () => _add(AddStart.voice),
            icon: const Icon(Icons.mic),
            label: const Text('말로 기억하기'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 200),
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
        title: Text.rich(
          TextSpan(
            children: [
              if (item.important && item.isPending)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.star,
                      size: 18,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
              TextSpan(text: item.name),
            ],
          ),
          style: item.isPending
              ? null
              : const TextStyle(decoration: TextDecoration.lineThrough),
        ),
        subtitle: Text(item.categories.map((c) => c.label).join(' · ')),
        trailing: item.photo == null
            ? null
            : _PhotoThumb(photo: item.photo!, title: item.name),
        onTap: onEdit,
      ),
    );
  }
}

/// 목록의 작은 사진. 누르면 크게 보여준다. (매장에서 "어떤 제품이었지?" 할 때)
class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.photo, required this.title});

  final String photo;
  final String title;

  @override
  Widget build(BuildContext context) {
    final file = context.read<PhotoStore>().fileOf(photo);
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.file(file, fit: BoxFit.contain),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          file,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          cacheWidth: 132,
          errorBuilder: (_, _, _) => const SizedBox(width: 44, height: 44),
        ),
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
          Text('까먹어도 마음 놓아, 귀띔해 줄게', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '살 물건을 적어두면, 살 수 있는 곳을 지날 때 알려주고\n'
            '안 사고 나서면 집에 가기 전에 붙잡아 줄게요.',
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
