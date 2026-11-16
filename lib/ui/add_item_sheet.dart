import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/item_categorizer.dart';
import '../core/item_text_parser.dart';
import '../data/photo_store.dart';
import '../models/item_draft.dart';
import '../models/shopping_item.dart';
import '../models/store_category.dart';
import '../services/photo_text_reader.dart';
import '../services/voice_input.dart';
import '../state/shopping_list.dart';

/// 시트를 열자마자 무엇부터 할지.
enum AddStart { text, voice, photo }

/// 물건 추가/수정 시트. 타이핑을 최대한 줄이는 게 목표다.
///
/// - 말하면 끝: 말이 끝나면 확인 없이 바로 저장한다. 잘못 들었으면 [되돌리기].
/// - 사진을 찍으면 바로 이름을 물어본다. 말하지 않아도 사진만으로 저장된다.
/// - 자주 사는 물건은 한 번 눌러 추가한다.
/// - "우유랑 계란"처럼 여러 개를 한 번에 말하거나 입력할 수 있다.
class AddItemSheet extends StatefulWidget {
  const AddItemSheet({
    super.key,
    this.initial,
    this.start = AddStart.text,
    required this.onAdded,
  });

  final ShoppingItem? initial;
  final AddStart start;
  final void Function(List<ShoppingItem> added) onAdded;

  /// 시트에서 추가한 물건들을 돌려준다. (화면에서 [되돌리기]를 보여주려고)
  static Future<List<ShoppingItem>> show(
    BuildContext context, {
    ShoppingItem? initial,
    AddStart start = AddStart.text,
  }) async {
    final added = <ShoppingItem>[];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          AddItemSheet(initial: initial, start: start, onAdded: added.addAll),
    );
    return added;
  }

  @override
  State<AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<AddItemSheet> {
  static const _categorizer = ItemCategorizer();
  static const _parser = ItemTextParser();

  late final PhotoStore _photos;
  late final VoiceInput _voice;
  late final ShoppingList _list;
  late final PhotoTextReader _reader;

  late final TextEditingController _text = TextEditingController(
    text: widget.initial?.name,
  );
  late Set<StoreCategory> _categories = {...?widget.initial?.categories};
  late bool _important = widget.initial?.important ?? false;
  late String? _photo = widget.initial?.photo;

  /// 사용자가 매장 종류를 직접 고쳤으면 자동 추천으로 덮어쓰지 않는다.
  late bool _touched = widget.initial != null;

  bool _listening = false;
  String? _voiceHint;
  String? _voiceError;
  bool _saved = false;

  /// 고르기만 하면 되는 이름 후보. (잘못 들었을 때, 사진에서 글자를 읽었을 때)
  List<String> _suggestions = const [];
  String _suggestionTitle = '';

  /// 후보를 고른 뒤 음성 인식이 늦게 보내는 결과는 무시한다.
  bool _ignoreVoice = false;

  /// 이 시트에서 한 번 눌러 추가한 물건 이름들.
  final _addedHere = <String>[];

  /// 이 시트에서 새로 찍은 사진. 저장하지 않고 닫으면 지운다.
  final _newPhotos = <String>{};

  bool get _editing => widget.initial != null;

  /// 수정할 때는 이름을 나누지 않는다.
  List<String> get _names {
    if (_editing) {
      final name = _text.text.trim();
      return name.isEmpty ? const [] : [name];
    }
    return _parser.parse(_text.text);
  }

  Set<StoreCategory> _categoriesFor(String name) =>
      _list.rememberedCategories(name) ?? _categorizer.suggest(name);

  @override
  void initState() {
    super.initState();
    _photos = context.read<PhotoStore>();
    _voice = context.read<VoiceInput>();
    _list = context.read<ShoppingList>();
    _reader = context.read<PhotoTextReader>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (widget.start) {
        case AddStart.voice:
          _startVoice();
        case AddStart.photo:
          _pickPhoto();
        case AddStart.text:
          break;
      }
    });
  }

  @override
  void dispose() {
    if (_listening) _voice.stop();
    for (final p in _newPhotos) {
      if (!_saved || p != _photo) _photos.delete(p);
    }
    _text.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final names = _names;
    setState(() {
      if (!_touched && names.length == 1) {
        _categories = _categoriesFor(names.single);
      }
    });
  }

  // ── 말로 입력 ──────────────────────────────────────────────

  Future<void> _startVoice({String? hint}) async {
    final ready = await _voice.ensureReady(
      onError: (_) => mounted ? setState(() => _listening = false) : null,
    );
    if (!mounted) return;
    if (!ready) {
      setState(() => _voiceError = '마이크나 음성 인식 권한이 없어요. 설정에서 허용해 주세요.');
      return;
    }
    setState(() {
      _listening = true;
      _voiceHint = hint;
      _voiceError = null;
      if (_suggestionTitle == _unsureTitle) _suggestions = const [];
    });
    await _voice.listen(
      onResult: (result) {
        if (!mounted || _ignoreVoice) return;
        _setText(result.words);
        if (!result.isFinal) return;
        setState(() => _listening = false);
        if (_names.isEmpty) return;
        if (result.isUnsure) {
          // 확신이 낮으면 저장하지 않고, 후보 중에서 고르게 한다.
          setState(() {
            _suggestionTitle = _unsureTitle;
            _suggestions = [result.words, ...result.alternatives];
          });
          return;
        }
        // 말하면 끝: 확인 없이 바로 저장한다. (수정할 때도 다시 말하면 바로 바뀐다)
        if (_editing) _categories = _categoriesFor(_names.single);
        _save();
      },
    );
  }

  static const _unsureTitle = '혹시 이거예요?';

  void _setText(String words) {
    _text.text = words;
    _text.selection = TextSelection.collapsed(offset: words.length);
    _onTextChanged();
  }

  /// 후보를 누르면 그 이름으로 바로 저장한다.
  Future<void> _pickSuggestion(String name) async {
    _ignoreVoice = true;
    if (_listening) await _stopVoice();
    _setText(name);
    if (_editing || !_touched) _categories = _categoriesFor(name);
    await _save();
  }

  Future<void> _stopVoice() async {
    await _voice.stop();
    if (mounted) setState(() => _listening = false);
  }

  // ── 사진 ──────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('사진 찍기'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('앨범에서 고르기'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80,
    );
    if (picked == null) return;
    final name = await _photos.save(picked.path);
    if (!mounted) return;
    setState(() {
      _newPhotos.add(name);
      _photo = name;
    });
    // 이름을 타이핑하지 않게: 사진 속 글자로 후보를 만들고, 동시에 말로도 물어본다.
    if (!_editing && _text.text.trim().isEmpty) {
      _reader.suggestNames(_photos.fileOf(name).path).then((names) {
        if (!mounted || _saved || names.isEmpty) return;
        setState(() {
          _suggestionTitle = '사진에서 찾은 이름';
          _suggestions = names;
        });
      });
      _startVoice(hint: '이 물건 이름을 말하거나, 아래에서 골라 주세요');
    }
  }

  // ── 저장 ──────────────────────────────────────────────────

  bool get _canSave {
    if (_editing) return _names.isNotEmpty && _categories.isNotEmpty;
    final names = _names;
    if (names.length > 1) return true;
    if (names.length == 1) return _categories.isNotEmpty;
    return _photo != null; // 사진만 있어도 저장할 수 있다.
  }

  Future<void> _save() async {
    if (!_canSave || _saved) return;
    _saved = true;
    if (_listening) await _stopVoice();

    final names = _names;
    if (_editing) {
      await _list.update(
        widget.initial!.copyWith(
          name: names.single,
          categories: _categories,
          important: _important,
          photo: _photo,
          clearPhoto: _photo == null,
        ),
      );
    } else {
      final List<ItemDraft> drafts;
      if (names.length > 1) {
        drafts = [
          for (final n in names)
            (
              name: n,
              categories: _categoriesFor(n),
              important: _important,
              photo: null,
            ),
        ];
      } else {
        final name = names.isEmpty ? ShoppingList.photoOnlyName : names.single;
        drafts = [
          (
            name: name,
            categories: _categories.isEmpty
                ? ItemCategorizer.fallback
                : _categories,
            important: _important,
            photo: _photo,
          ),
        ];
      }
      widget.onAdded(await _list.addAll(drafts));
    }
    if (mounted) Navigator.pop(context);
  }

  /// 자주 사는 물건 칩: 누르면 바로 추가하고 시트는 열어 둔다.
  Future<void> _addQuick(String name) async {
    final added = await _list.add(name, _categoriesFor(name));
    widget.onAdded(added);
    if (mounted) setState(() => _addedHere.add(name));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = _names;
    final multiple = names.length > 1;
    final empty = _text.text.trim().isEmpty;
    // 칩을 눌러 목록이 바뀌면 칩도 다시 그린다.
    final quickPicks = _editing
        ? const <String>[]
        : context.watch<ShoppingList>().quickPicks;

    final String buttonLabel;
    if (_editing) {
      buttonLabel = '저장';
    } else if (multiple) {
      buttonLabel = '${names.length}개 기억하기';
    } else if (empty && _photo == null && _addedHere.isNotEmpty) {
      buttonLabel = '완료';
    } else {
      buttonLabel = '기억하기';
    }
    final onButton = buttonLabel == '완료'
        ? () => Navigator.pop(context)
        : (_canSave ? _save : null);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _editing ? '물건 수정' : '무엇을 사야 하나요?',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (_listening)
              _ListeningBanner(
                hint: _voiceHint ?? '"우유랑 계란 사야 돼"처럼 말해 보세요',
                heard: _text.text,
                onStop: _stopVoice,
              )
            else
              TextField(
                controller: _text,
                autofocus: widget.start == AddStart.text && _editing,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: _photo != null ? '이름 (안 적어도 돼요)' : '예: 우유, 계란, 감기약',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: '말로 입력',
                    onPressed: () => _startVoice(),
                    icon: const Icon(Icons.mic_none),
                  ),
                ),
                onChanged: (_) => _onTextChanged(),
                onSubmitted: (_) => _save(),
              ),
            if (_editing && !_listening) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => _startVoice(hint: '바꿀 이름을 말해 주세요'),
                icon: const Icon(Icons.mic),
                label: const Text('다시 말하기'),
              ),
            ],
            if (_suggestions.isNotEmpty)
              _Suggestions(
                title: _suggestionTitle,
                names: _suggestions,
                onPick: _pickSuggestion,
                onRetry: _suggestionTitle == _unsureTitle
                    ? () => _startVoice()
                    : null,
              ),
            if (_voiceError != null) ...[
              const SizedBox(height: 8),
              Text(
                _voiceError!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (!_editing && empty && !_listening && quickPicks.isNotEmpty)
              _QuickPicks(
                names: quickPicks,
                added: _addedHere,
                onTap: _addQuick,
              ),
            const SizedBox(height: 16),
            if (multiple)
              _MultiPreview(names: names, categoriesFor: _categoriesFor)
            else ...[
              _PhotoField(
                photo: _photo,
                onPick: _pickPhoto,
                onRemove: () => setState(() => _photo = null),
              ),
              if (!empty || _editing) ...[
                const SizedBox(height: 16),
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
              ],
            ],
            if (!empty || _editing || _photo != null) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _important,
                onChanged: (v) => setState(() => _important = v),
                title: Text(multiple ? '모두 꼭 사야 해요' : '꼭 사야 해요'),
                subtitle: const Text('안 사고 매장을 나서면 더 강하게 알려드려요'),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(onPressed: onButton, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }
}

/// 듣는 중일 때 입력칸 대신 보여준다.
class _ListeningBanner extends StatelessWidget {
  const _ListeningBanner({
    required this.hint,
    required this.heard,
    required this.onStop,
  });

  final String hint;
  final String heard;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(Icons.graphic_eq, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('듣고 있어요', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text(
                    heard.isEmpty ? hint : heard,
                    style: heard.isEmpty
                        ? theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          )
                        : theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '그만 듣기',
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

/// 고르기만 하면 되는 이름 후보. 누르면 그 이름으로 바로 저장된다.
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.title,
    required this.names,
    required this.onPick,
    this.onRetry,
  });

  final String title;
  final List<String> names;
  final void Function(String name) onPick;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in names)
                ActionChip(
                  avatar: const Icon(Icons.touch_app_outlined, size: 18),
                  label: Text(n),
                  onPressed: () => onPick(n),
                ),
              if (onRetry != null)
                ActionChip(
                  avatar: const Icon(Icons.mic, size: 18),
                  label: const Text('다시 말하기'),
                  onPressed: onRetry,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 자주 사는 물건. 누르면 바로 추가된다.
class _QuickPicks extends StatelessWidget {
  const _QuickPicks({
    required this.names,
    required this.added,
    required this.onTap,
  });

  final List<String> names;
  final List<String> added;
  final void Function(String name) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            added.isEmpty ? '눌러서 바로 추가' : '추가했어요: ${added.join(', ')}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in names)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: Text(n),
                  onPressed: () => onTap(n),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 여러 개를 한 번에 말했을 때, 어떻게 나뉘었는지 보여준다.
class _MultiPreview extends StatelessWidget {
  const _MultiPreview({required this.names, required this.categoriesFor});

  final List<String> names;
  final Set<StoreCategory> Function(String name) categoriesFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (final n in names)
            ListTile(
              dense: true,
              leading: const Icon(Icons.check, size: 20),
              title: Text(n),
              subtitle: Text(
                categoriesFor(n).map((c) => c.label).join(' · '),
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoField extends StatelessWidget {
  const _PhotoField({
    required this.photo,
    required this.onPick,
    required this.onRemove,
  });

  final String? photo;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    if (photo == null) {
      return OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('사진 붙이기 (이 제품 그대로 사고 싶을 때)'),
      );
    }
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            context.read<PhotoStore>().fileOf(photo),
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            cacheWidth: 216,
          ),
        ),
        const SizedBox(width: 12),
        TextButton(onPressed: onPick, child: const Text('다시 찍기')),
        TextButton(onPressed: onRemove, child: const Text('빼기')),
      ],
    );
  }
}
