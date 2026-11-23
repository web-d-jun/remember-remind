import '../models/store_category.dart';

/// 상가정보에 적힌 매장 이름을 사람들이 아는 브랜드 이름으로 바꾼다.
///
/// 상가정보에는 같은 브랜드가 여러 모양으로 적혀 있다.
/// - 운영 회사 이름: "비지에프리테일알펜시아리조트점"(CU), "코리아세븐횡성 코아루점"(세븐일레븐)
/// - 한글로 읽은 이름: "지에스25뉴국제호텔점", "씨유제주공항점"
/// - 회사 이름이 뒤에 붙은 것: "세븐청계퍼시픽점 코리아"
/// 알림에는 "CU 알펜시아리조트점", "GS25 뉴국제호텔점"처럼 보여준다.
///
/// 편의점만 바꾼다. (BGF리테일은 마트도 운영해서, 마트 이름은 그대로 둔다)
String displayStoreName(String raw, StoreCategory category) {
  final name = raw.trim();
  if (category != StoreCategory.convenience) return name;
  for (final (pattern, brand) in _brands) {
    final m = pattern.firstMatch(name);
    if (m == null) continue;
    var rest = name.substring(m.end).trim();
    // 회사 이름 "(주)코리아세븐"이 뒤에 붙어 "…점주 코리아", "…점 코리아"가 된 것,
    // 그리고 "(주)"가 남아 "…점주"가 된 것을 정리한다.
    rest = rest.replaceFirst(_companySuffix, '').trim();
    return rest.isEmpty ? brand : '$brand $rest';
  }
  return name;
}

// 앞에서부터 처음 맞는 것을 쓴다. 긴 것을 먼저 둔다. ("지에스GS25"를 "지에스"보다 먼저)
final List<(RegExp, String)> _brands = [
  // GS더프레시는 GS리테일의 슈퍼마켓이라 GS25가 아니다.
  (RegExp(r'^지에스\s*더\s*프레시\s*'), 'GS더프레시'),
  // "GS25N"은 군부대 안 GS25.
  (RegExp(r'^지에스리테일\s*(GS\s*25\s*N?)?\s*'), 'GS25'),
  // "지에스마트"는 GS25인지 알 수 없어 그대로 둔다.
  (RegExp(r'^지에스(?!\s*마트)\s*(GS\s*25|25|이십오)?\s*'), 'GS25'),
  (RegExp(r'^GS\s*25\s*'), 'GS25'),
  // 비지에프휴먼넷도 BGF리테일 계열로, 휴게소·기숙사 등의 CU를 운영한다.
  // 뒤에 "CU"/"씨유"가 한 번 더 붙은 것도 떼어 낸다. ("CUE"처럼 이어지는 영문은 남긴다)
  (RegExp(r'^비지에프(리테일|휴먼넷)\s*((CU|씨유)(?![A-Za-z]))?\s*'), 'CU'),
  (RegExp(r'^(씨유|CU(?![A-Za-z])|cu(?![A-Za-z]))\s*'), 'CU'),
  (RegExp(r'^(코리아세븐|세븐\s*-?\s*일레븐|세븐)\s*'), '세븐일레븐'),
  (RegExp(r'^이마트\s*24\s*'), '이마트24'),
  (RegExp(r'^(한국)?미니스톱\s*'), '미니스톱'),
];

final _companySuffix = RegExp(r'주\s*코리아$|\s+코리아$|(?<=점)주$');
