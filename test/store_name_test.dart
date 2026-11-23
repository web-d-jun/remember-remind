import 'package:flutter_test/flutter_test.dart';
import 'package:remember_remind/core/store_name.dart';
import 'package:remember_remind/models/store_category.dart';

String conv(String raw) => displayStoreName(raw, StoreCategory.convenience);

void main() {
  group('편의점 이름을 브랜드 이름으로 바꾼다', () {
    test('CU: 운영 회사 이름(BGF리테일, BGF휴먼넷)과 한글 표기', () {
      expect(conv('비지에프리테일알펜시아리조트 2호점'), 'CU 알펜시아리조트 2호점');
      expect(conv('비지에프휴먼넷CU원주세브란스 1호점'), 'CU 원주세브란스 1호점');
      expect(conv('비지에프휴먼넷씨유음성디씨점'), 'CU 음성디씨점');
      expect(conv('씨유한국프레스 센터점'), 'CU 한국프레스 센터점');
      expect(conv('CU인천점'), 'CU 인천점');
    });

    test('GS25: 한글 표기와 운영 회사 이름', () {
      expect(conv('지에스25뉴국제호텔점'), 'GS25 뉴국제호텔점');
      expect(conv('지에스GS25주문진 오거리점'), 'GS25 주문진 오거리점');
      expect(conv('지에스이십오가산KS'), 'GS25 가산KS');
      expect(conv('지에스리테일GS25N동해해군점주'), 'GS25 동해해군점');
      expect(conv('GS25인천 광장점'), 'GS25 인천 광장점');
    });

    test('GS더프레시는 GS25가 아니다', () {
      expect(conv('지에스더프레시 천안차암점'), 'GS더프레시 천안차암점');
    });

    test('세븐일레븐: 운영 회사 이름과 뒤에 붙은 "코리아"', () {
      expect(conv('코리아세븐횡성 코아루점'), '세븐일레븐 횡성 코아루점');
      expect(conv('세븐청계퍼시픽점 코리아'), '세븐일레븐 청계퍼시픽점');
      expect(conv('세븐원주관설점주 코리아'), '세븐일레븐 원주관설점');
      expect(conv('세븐-일레븐초당점'), '세븐일레븐 초당점');
      expect(conv('세븐일레븐파주 본점'), '세븐일레븐 파주 본점');
    });

    test('이마트24, 미니스톱', () {
      expect(conv('이마트24부천고강 중앙점'), '이마트24 부천고강 중앙점');
      expect(conv('한국미니스톱역삼점'), '미니스톱 역삼점');
    });

    test('브랜드만 있으면 브랜드 이름만', () {
      expect(conv('이마트24'), '이마트24');
    });

    test('모르는 이름, 이어지는 영문, 판단할 수 없는 이름은 그대로 둔다', () {
      expect(conv('씨스페이스강남점'), '씨스페이스강남점');
      expect(conv('CUBE편의점'), 'CUBE편의점');
      expect(conv('지에스마트'), '지에스마트');
    });
  });

  test('편의점이 아니면 바꾸지 않는다 (BGF리테일은 마트도 운영한다)', () {
    expect(
      displayStoreName('비지에프리테일인천큐브에스점', StoreCategory.mart),
      '비지에프리테일인천큐브에스점',
    );
  });
}
