import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../core/geo.dart';
import '../models/store_category.dart';
import '../state/my_stores.dart';

/// 직접 등록한 매장 목록. 내장 데이터에 없는 매장(다이소 등)을 채운다.
class MyStoresScreen extends StatelessWidget {
  const MyStoresScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const MyStoresScreen()),
  );

  @override
  Widget build(BuildContext context) {
    final myStores = context.watch<MyStores>();
    final stores = myStores.stores;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('내 매장')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _registerHere(context),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('지금 있는 곳 등록'),
      ),
      body: stores.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    size: 56,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '까마귀가 모르는 매장이 있나요?',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '다이소처럼 자주 가는데 알림이 안 오는 매장에 가서\n'
                    '"지금 있는 곳 등록"을 누르세요.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                for (final (i, store) in stores.indexed)
                  Dismissible(
                    key: ValueKey(store.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      color: theme.colorScheme.errorContainer,
                      child: const Icon(Icons.delete_outline),
                    ),
                    onDismissed: (_) {
                      myStores.remove(store);
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text('${store.name} 지웠어요'),
                            action: SnackBarAction(
                              label: '되돌리기',
                              onPressed: () => myStores.restore(store, i),
                            ),
                          ),
                        );
                    },
                    child: ListTile(
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(store.name),
                      subtitle: Text(
                        [
                          store.category.label,
                          if (store.large) '큰 매장',
                        ].join(' · '),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _registerHere(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final myStores = context.read<MyStores>();

    final position = await _currentPosition(messenger);
    if (position == null || !context.mounted) return;

    final draft = await showModalBottomSheet<_StoreDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RegisterSheet(accuracy: position.accuracy),
    );
    if (draft == null) return;

    final store = await myStores.add(
      name: draft.name,
      category: draft.category,
      location: LatLng(position.latitude, position.longitude),
      large: draft.large,
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${store.name} 등록했어요')));
  }

  Future<Position?> _currentPosition(ScaffoldMessengerState messenger) async {
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        say('위치 권한이 있어야 지금 있는 곳을 등록할 수 있어요');
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } on Exception {
      say('위치를 못 찾았어요. 잠시 후 다시 해 주세요');
      return null;
    }
  }
}

typedef _StoreDraft = ({String name, StoreCategory category, bool large});

/// 매장 종류를 고르고(이름은 종류로 자동으로 채움) 저장한다. 타이핑은 선택.
class _RegisterSheet extends StatefulWidget {
  const _RegisterSheet({required this.accuracy});

  /// 현재 위치의 오차(m).
  final double accuracy;

  @override
  State<_RegisterSheet> createState() => _RegisterSheetState();
}

class _RegisterSheetState extends State<_RegisterSheet> {
  StoreCategory? _category;
  bool _large = false;
  final _name = TextEditingController();

  /// 이름 칸을 사용자가 직접 고쳤는지. 안 고쳤으면 종류를 바꿀 때 이름도 따라 바꾼다.
  bool _nameEdited = false;

  static bool _usuallyLarge(StoreCategory c) =>
      c == StoreCategory.mart || c == StoreCategory.daiso;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _pick(StoreCategory c) {
    setState(() {
      _category = c;
      _large = _usuallyLarge(c);
      if (!_nameEdited) _name.text = c.label;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = _category;
    final inaccurate = widget.accuracy > 50;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('여기는 어떤 매장인가요?', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            inaccurate
                ? '지금 위치 오차가 ${widget.accuracy.round()}m예요. '
                      '매장 입구 가까이에서 등록하면 더 정확해요.'
                : '지금 서 있는 곳을 매장 위치로 저장해요.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: inaccurate
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in StoreCategory.values)
                ChoiceChip(
                  label: Text(c.label),
                  selected: c == category,
                  onSelected: (_) => _pick(c),
                ),
            ],
          ),
          if (category != null) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '이름 (예: 다이소 시청점)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _nameEdited = true,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _large,
              onChanged: (v) => setState(() => _large = v),
              title: const Text('큰 매장'),
              subtitle: const Text('마트처럼 넓으면 켜 두세요. 매장 안에서 위치가 튀어도 안에 있다고 알아봐요.'),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: category == null
                  ? null
                  : () {
                      final name = _name.text.trim();
                      Navigator.of(context).pop<_StoreDraft>((
                        name: name.isEmpty ? category.label : name,
                        category: category,
                        large: _large,
                      ));
                    },
              child: const Text('등록'),
            ),
          ),
        ],
      ),
    );
  }
}
