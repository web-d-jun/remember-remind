import 'item_categorizer.dart';

/// "우유랑 계란 사야 돼" 같은 말이나 입력을 물건 이름 목록으로 나눈다.
///
/// 음성 인식 결과에는 쉼표가 없고 말끝("사야 돼", "사 와")이 붙어 오므로,
/// 자연스럽게 말한 문장에서 물건만 골라낸다.
class ItemTextParser {
  const ItemTextParser([this._categorizer = const ItemCategorizer()]);

  final ItemCategorizer _categorizer;

  /// 명확한 구분자: 쉼표, 줄바꿈, "그리고", "및"
  static final _separators = RegExp(r'\s*(?:[,，、/\n]|\s그리고\s|\s및\s)\s*');

  /// 말 앞뒤에 붙는 군더더기
  static final _callName = RegExp(r'^\s*까마귀(?:야|아)?[\s,!]*');
  static final _trailingVerb = RegExp(
    r'\s*(?:좀\s*)?(?:'
    r'사\s*(?:야|와|오)\S*'
    r'|사오기|사기|사자|사러\S*|살\s*것|살거'
    r'|구매\S*|구입\S*|기억\S*|잊지\s*마\S*'
    r')(?:\s*(?:돼|해|함|하기|해야\s*돼|해야\s*해|해줘|줘))?\s*[.!?~]*\s*$',
  );

  List<String> parse(String text) {
    var t = text.replaceFirst(_callName, '').trim();
    t = t.replaceFirst(_trailingVerb, '').trim();
    if (t.isEmpty) return const [];

    final result = <String>[];
    for (final chunk in t.split(_separators)) {
      for (final part in _splitConjunctions(chunk)) {
        for (final name in _splitSpaces(part)) {
          final clean = _stripParticles(name.trim());
          if (clean.isNotEmpty && !result.contains(clean)) result.add(clean);
        }
      }
    }
    return result;
  }

  /// "우유랑 계란이랑 휴지", "우유하고 계란"
  Iterable<String> _splitConjunctions(String chunk) sync* {
    final words = chunk.trim().split(RegExp(r'\s+'));
    final buffer = <String>[];
    for (final word in words) {
      final stripped = _stripConjunction(word);
      if (stripped != null) {
        buffer.add(stripped);
        yield buffer.join(' ');
        buffer.clear();
      } else {
        buffer.add(word);
      }
    }
    if (buffer.isNotEmpty) yield buffer.join(' ');
  }

  /// 단어 끝의 "랑/이랑/하고"를 떼어낸다. 접속 조사가 아니면 null.
  String? _stripConjunction(String word) {
    if (word.endsWith('하고') && word.length > 2) {
      return word.substring(0, word.length - 2);
    }
    if (!word.endsWith('랑') || word.length < 2) return null;
    // "계란이랑" → "계란", "오이랑" → "오이". 사전에 있는 쪽을 고르고,
    // 모르면 "이랑"은 받침 뒤에만 오므로 받침이 있을 때만 "이"까지 뗀다.
    final withoutRang = word.substring(0, word.length - 1);
    if (withoutRang.endsWith('이') && withoutRang.length > 1) {
      final withoutIrang = withoutRang.substring(0, withoutRang.length - 1);
      if (_categorizer.isKnown(withoutIrang)) return withoutIrang;
      if (_categorizer.isKnown(withoutRang)) return withoutRang;
      if (_hasFinalConsonant(withoutIrang)) return withoutIrang;
    }
    return withoutRang;
  }

  /// 음성 인식은 "우유 계란 휴지"처럼 띄어쓰기로만 나열하는 경우가 많다.
  /// 모든 단어가 아는 물건일 때만 나눈다. ("종량제 봉투"는 그대로 둔다)
  Iterable<String> _splitSpaces(String part) {
    final words = part.trim().split(RegExp(r'\s+'));
    if (words.length > 1 && words.every(_categorizer.isKnown)) return words;
    return [part];
  }

  /// 끝의 목적격 조사 "을/를"을 뗀다. 받침과 맞을 때만. ("우유를", "감기약을")
  String _stripParticles(String name) {
    if (name.length < 2) return name;
    final body = name.substring(0, name.length - 1);
    final last = name[name.length - 1];
    if (last == '를' && !_hasFinalConsonant(body)) return body;
    if (last == '을' && _hasFinalConsonant(body)) return body;
    return name;
  }

  static bool _hasFinalConsonant(String word) {
    if (word.isEmpty) return false;
    final code = word.codeUnitAt(word.length - 1);
    if (code < 0xAC00 || code > 0xD7A3) return false;
    return (code - 0xAC00) % 28 != 0;
  }
}
