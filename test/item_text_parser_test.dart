import 'package:flutter_test/flutter_test.dart';
import 'package:remember_remind/core/item_text_parser.dart';

void main() {
  const parser = ItemTextParser();

  final cases = <String, List<String>>{
    // 직접 입력
    '우유': ['우유'],
    '우유, 계란, 휴지': ['우유', '계란', '휴지'],
    '종량제 봉투': ['종량제 봉투'],
    '아이스 아메리카노': ['아이스 아메리카노'],
    // 말하듯이
    '우유 사야 돼': ['우유'],
    '우유랑 계란 사야 돼': ['우유', '계란'],
    '계란이랑 오이랑 두부 사와': ['계란', '오이', '두부'],
    '우유하고 건전지 좀 사야지': ['우유', '건전지'],
    '감기약을 사야 해': ['감기약'],
    '우유를 사 와': ['우유'],
    '우유 계란 휴지 사야 돼': ['우유', '계란', '휴지'],
    '까마귀야 샴푸랑 린스 기억해줘': ['샴푸', '린스'],
    '사과 사기': ['사과'],
    '우유 그리고 빵': ['우유', '빵'],
    '우유랑 우유': ['우유'],
    // 아무것도 없음
    '': [],
    '사야 돼': [],
  };

  for (final MapEntry(key: input, value: expected) in cases.entries) {
    test('"$input" → $expected', () {
      expect(parser.parse(input), expected);
    });
  }
}
