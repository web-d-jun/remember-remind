import 'item_categorizer.dart';

/// 사진에서 읽은 글자 한 줄. [height]는 글자 크기(픽셀)로, 클수록 제품 이름일 가능성이 높다.
class OcrLine {
  const OcrLine(this.text, this.height);

  final String text;
  final double height;
}

/// 제품 사진에서 읽은 글자로 물건 이름 후보를 고른다. 사용자는 고르기만 하면 된다.
///
/// 1. 사전에 있는 물건 이름("샴푸", "우유")이 보이면 가장 먼저 추천한다.
///    살 수 있는 매장 종류를 정확히 알 수 있기 때문이다.
/// 2. 그다음은 글자가 큰 줄(보통 제품명·브랜드)을 추천한다.
///    용량("500ml"), 홍보 문구("1+1", "증정"), 숫자만 있는 줄은 뺀다.
List<String> pickNamesFromOcr(
  List<OcrLine> lines, {
  ItemCategorizer categorizer = const ItemCategorizer(),
  int max = 4,
}) {
  final cleaned = [
    for (final l in lines)
      if (_clean(l.text) case final t when t.isNotEmpty) OcrLine(t, l.height),
  ];
  final joined = cleaned.map((l) => l.text.replaceAll(' ', '')).toList();

  // 1) 사전 단어. 긴 단어부터, 이미 고른 단어에 들어 있는 짧은 단어는 뺀다. ("감기약" 안의 "약")
  final known = ItemCategorizer.knownNames.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final picked = <String>[];
  for (final word in known) {
    final found = word.length == 1
        ? joined.contains(word) // 한 글자 단어는 그 글자만 있는 줄일 때만
        : joined.any((t) => t.contains(word));
    if (found && !picked.any((p) => p.contains(word))) picked.add(word);
  }

  // 2) 글자가 큰 줄
  final big = cleaned.where((l) => _looksLikeName(l.text)).toList()
    ..sort((a, b) => b.height.compareTo(a.height));
  for (final l in big) {
    if (picked.length >= max) break;
    if (!picked.contains(l.text)) picked.add(l.text);
  }
  return picked.take(max).toList();
}

final _keep = RegExp(r'[^0-9A-Za-z가-힣\s]');
final _quantity = RegExp(
  r'\s*\d+([.,]\d+)?\s*(ml|mL|ML|l|L|g|kg|KG|매|개|입|롤|정|캡슐|팩|m|cm|%)(\s*[xX×]\s*\d+)?\s*',
);
const _promo = ['증정', '할인', '행사', '무료', '신제품', '한정', '기획', '특가', '덤'];

String _clean(String text) => text
    .replaceAll(_keep, ' ')
    .replaceAll(_quantity, ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool _looksLikeName(String text) {
  final compact = text.replaceAll(' ', '');
  if (compact.length < 2 || compact.length > 14) return false;
  if (!RegExp(r'[가-힣]').hasMatch(compact)) return false;
  if (RegExp(r'^\d+$').hasMatch(compact)) return false;
  if (_promo.any(compact.contains)) return false;
  return true;
}
