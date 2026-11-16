import 'package:flutter_test/flutter_test.dart';
import 'package:remember_remind/core/ocr_name_picker.dart';

void main() {
  test('사전에 있는 물건 이름을 먼저, 그다음 큰 글자를 추천한다', () {
    final names = pickNamesFromOcr(const [
      OcrLine('해피바스', 120),
      OcrLine('퍼퓸 샴푸', 60),
      OcrLine('500ml', 40),
      OcrLine('1+1 증정', 50),
    ]);
    expect(names, ['샴푸', '해피바스', '퍼퓸 샴푸']);
  });

  test('긴 단어를 고르면 그 안의 짧은 단어는 뺀다', () {
    final names = pickNamesFromOcr(const [OcrLine('어린이 감기약 시럽', 80)]);
    expect(names.first, '감기약');
    expect(names, isNot(contains('약')));
  });

  test('용량과 숫자는 이름에서 지운다', () {
    final names = pickNamesFromOcr(const [
      OcrLine('삼다수 2L', 100),
      OcrLine('2000', 90),
    ]);
    expect(names, ['삼다수']);
  });

  test('영어만 있는 줄은 빼고, 한글 제품명만 추천한다', () {
    final names = pickNamesFromOcr(const [
      OcrLine('NATURAL', 150),
      OcrLine('촉촉 로션', 70),
    ]);
    expect(names, ['로션', '촉촉 로션']);
  });

  test('한 글자 단어는 그 글자만 있는 줄일 때만 추천한다', () {
    expect(pickNamesFromOcr(const [OcrLine('물티슈', 80)]), ['물티슈']);
    expect(pickNamesFromOcr(const [OcrLine('약', 80)]), ['약']);
  });

  test('글자가 없으면 추천하지 않는다', () {
    expect(pickNamesFromOcr(const []), isEmpty);
    expect(pickNamesFromOcr(const [OcrLine('!!!', 50)]), isEmpty);
  });

  test('최대 개수까지만', () {
    final names = pickNamesFromOcr(const [
      OcrLine('가나다', 10),
      OcrLine('라마바', 20),
      OcrLine('사아자', 30),
      OcrLine('차카타', 40),
      OcrLine('파하가', 50),
    ], max: 3);
    expect(names, ['파하가', '차카타', '사아자']);
  });
}
