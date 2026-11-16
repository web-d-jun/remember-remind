import 'package:flutter/material.dart';

import '../core/item_categorizer.dart';
import '../models/shopping_item.dart';
import '../models/store_category.dart';

typedef ItemDraft = ({
  String name,
  Set<StoreCategory> categories,
  bool important,
});

/// 물건 추가/수정 시트. 이름을 입력하면 살 수 있는 매장 종류를 자동으로 고른다.
class AddItemSheet extends StatefulWidget {
  const AddItemSheet({super.key, this.initial});

  final ShoppingItem? initial;

  static Future<ItemDraft?> show(
    BuildContext context, {
    ShoppingItem? initial,
  }) {
    return showModalBottomSheet<ItemDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AddItemSheet(initial: initial),
    );
  }

  @override
  State<AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<AddItemSheet> {
  static const _categorizer = ItemCategorizer();

  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name,
  );
  late Set<StoreCategory> _categories = {...?widget.initial?.categories};
  late bool _important = widget.initial?.important ?? false;

  /// 사용자가 매장 종류를 직접 고쳤으면 자동 추천으로 덮어쓰지 않는다.
  late bool _touched = widget.initial != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    if (_touched) {
      setState(() {});
      return;
    }
    setState(() => _categories = _categorizer.suggest(value));
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || _categories.isEmpty) return;
    Navigator.pop<ItemDraft>(context, (
      name: name,
      categories: _categories,
      important: _important,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSubmit = _name.text.trim().isNotEmpty && _categories.isNotEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.initial == null ? '무엇을 사야 하나요?' : '물건 수정',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: '예: 우유, 건전지, 감기약',
              border: OutlineInputBorder(),
            ),
            onChanged: _onNameChanged,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          Text('어디서 살 수 있나요?', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in StoreCategory.values)
                FilterChip(
                  label: Text(c.label),
                  selected: _categories.contains(c),
                  onSelected: (on) => setState(() {
                    _touched = true;
                    _categories = on
                        ? {..._categories, c}
                        : ({..._categories}..remove(c));
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _important,
            onChanged: (v) => setState(() => _important = v),
            title: const Text('꼭 사야 해요'),
            subtitle: const Text('안 사고 매장을 나서면 더 강하게 알려드려요'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: canSubmit ? _submit : null,
            child: Text(widget.initial == null ? '기억하기' : '저장'),
          ),
        ],
      ),
    );
  }
}
