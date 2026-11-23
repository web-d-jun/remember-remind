import '../models/store_category.dart';

/// 물건 이름으로 살 수 있는 매장 종류를 추천한다.
///
/// MVP에서는 키워드 사전을 쓴다. 나중에 LLM 분류로 바꿀 때는
/// 이 클래스만 교체하면 된다.
class ItemCategorizer {
  const ItemCategorizer();

  static const _c = StoreCategory.convenience;
  static const _m = StoreCategory.mart;
  static const _p = StoreCategory.pharmacy;
  static const _d = StoreCategory.daiso;
  static const _o = StoreCategory.drugstore;
  static const _s = StoreCategory.stationery;
  static const _k = StoreCategory.snack;

  static const Map<String, Set<StoreCategory>> _dictionary = {
    // 식품
    '우유': {_c, _m}, '계란': {_c, _m}, '달걀': {_c, _m}, '두부': {_c, _m},
    '라면': {_c, _m}, '빵': {_c, _m}, '물': {_c, _m}, '생수': {_c, _m},
    '커피': {_c, _m}, '음료': {_c, _m}, '맥주': {_c, _m}, '소주': {_c, _m},
    '과자': {_c, _m, _k}, '아이스크림': {_c, _m, _k}, '요거트': {_c, _m},
    '초콜릿': {_c, _m, _k}, '사탕': {_c, _m, _k}, '젤리': {_c, _m, _k},
    '껌': {_c, _m, _k},
    '햇반': {_c, _m}, '즉석밥': {_c, _m},
    '쌀': {_m}, '고기': {_m}, '돼지고기': {_m}, '소고기': {_m}, '닭': {_m},
    '채소': {_m}, '야채': {_m}, '과일': {_m}, '양파': {_m}, '대파': {_m},
    '마늘': {_m}, '감자': {_m}, '고구마': {_m}, '사과': {_m},
    '바나나': {_m}, '생선': {_m}, '참기름': {_m}, '간장': {_m}, '식용유': {_m},
    '설탕': {_m}, '소금': {_m}, '고추장': {_m}, '된장': {_m},
    // 생활용품
    '휴지': {_c, _m, _d}, '화장지': {_c, _m, _d}, '물티슈': {_c, _m, _d},
    '건전지': {_c, _m, _d}, '배터리': {_c, _m, _d}, '충전기': {_c, _d},
    '세제': {_m, _d}, '섬유유연제': {_m}, '주방세제': {_m, _d},
    '수세미': {_m, _d}, '쓰레기봉투': {_c, _m}, '종량제': {_c, _m},
    '비닐봉투': {_c, _m, _d}, '호일': {_m, _d},
    '전구': {_m, _d}, '우산': {_c, _d}, '면도기': {_c, _m, _o},
    '칫솔': {_c, _m, _d, _o}, '치약': {_c, _m, _d, _o},
    '샴푸': {_m, _o}, '린스': {_m, _o}, '바디워시': {_m, _o}, '비누': {_m, _d},
    '생리대': {_c, _m, _o}, '기저귀': {_m},
    // 아기용품
    '젖병': {_m, _d}, '젖병솔': {_m, _d}, '젖꼭지': {_m}, '분유': {_m, _p},
    '이유식': {_m}, '아기물티슈': {_m, _d},
    // 화장품
    '선크림': {_o}, '로션': {_o}, '립밤': {_o, _c}, '마스크팩': {_o, _d},
    '화장품': {_o}, '클렌징': {_o}, '마스크': {_c, _p, _d, _o},
    // 의약품
    '약': {_p}, '감기약': {_p}, '두통약': {_p}, '진통제': {_p},
    '소화제': {_p, _c}, '해열제': {_p}, '파스': {_p}, '밴드': {_p, _c, _d},
    '반창고': {_p, _c}, '연고': {_p}, '영양제': {_p, _o}, '비타민': {_p, _o},
    '안약': {_p}, '인공눈물': {_p},
    // 문구
    '볼펜': {_s, _d, _c}, '연필': {_s, _d}, '공책': {_s, _d},
    '노트': {_s, _d}, '테이프': {_s, _d}, '가위': {_s, _d},
    '포스트잇': {_s, _d}, '편지지': {_s, _d}, '택배상자': {_d, _c},
  };

  /// 모르는 물건이면 가장 범용적인 편의점·마트를 추천한다.
  static const Set<StoreCategory> fallback = {_c, _m};

  /// 사전에 있는 물건 이름들. 음성 인식이 이 단어들을 더 잘 알아듣게 힌트로 준다.
  static Iterable<String> get knownNames => _dictionary.keys;

  /// 사전에 정확히 있는 물건 이름인지.
  bool isKnown(String name) =>
      _dictionary.containsKey(name.replaceAll(' ', ''));

  Set<StoreCategory> suggest(String itemName) {
    final name = itemName.replaceAll(' ', '');
    if (name.isEmpty) return const {};

    final exact = _dictionary[name];
    if (exact != null) return exact;

    // 부분 일치는 가장 긴 키워드가 우선한다. ("감기약 사기"는 "약"보다 "감기약")
    final matches = _dictionary.keys.where(name.contains).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (matches.isNotEmpty) return _dictionary[matches.first]!;

    return fallback;
  }
}
