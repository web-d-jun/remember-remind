import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remember_remind/core/geo.dart';
import 'package:remember_remind/data/store_index.dart';
import 'package:remember_remind/models/store_category.dart';

void main() {
  const cityHall = LatLng(37.56650, 126.97800);

  group('StoreIndex', () {
    final index = StoreIndex.parse(
      [
        'convenience\t3756660\t12697810\t씨유 시청점', // 약 15m
        'convenience\t3757100\t12697800\tGS25 북쪽점', // 약 500m
        'convenience\t3760000\t12697800\t세븐일레븐 먼곳', // 약 3.7km
        'pharmacy\t3756650\t12697850\t시청약국',
        'mart\t3756700\t12697900\t홈플러스 시청점\tL',
        'mart\t3756660\t12697900\t달콤한상회\tU',
        'unknown\t3756650\t12697800\t모르는종류',
        '깨진줄',
        '',
      ].join('\n'),
    );

    test('깨진 줄과 모르는 종류는 건너뛴다', () {
      expect(index.length, 6);
    });

    test('다섯째 칸이 U면 불확실한 매장이다', () {
      final marts = index.nearby(
        center: cityHall,
        category: StoreCategory.mart,
        radiusMeters: 500,
      );
      final byName = {for (final s in marts) s.name: s};
      expect(byName['달콤한상회']!.certain, isFalse);
      expect(byName['달콤한상회']!.large, isFalse);
      expect(byName['홈플러스 시청점']!.certain, isTrue);
    });

    test('다섯째 칸이 L이면 대형 매장이다', () {
      final mart = index.nearby(
        center: cityHall,
        category: StoreCategory.mart,
        radiusMeters: 500,
      );
      expect(mart.singleWhere((s) => s.name == '홈플러스 시청점').large, isTrue);
      final conv = index.nearby(
        center: cityHall,
        category: StoreCategory.convenience,
        radiusMeters: 500,
      );
      expect(conv.every((s) => !s.large), isTrue);
    });

    test('반경 안의 같은 종류 매장만 가까운 순서로 돌려준다', () {
      final stores = index.nearby(
        center: cityHall,
        category: StoreCategory.convenience,
        radiusMeters: 1000,
      );
      // 이름은 브랜드 이름으로 바꿔서 돌려준다. ("씨유" → "CU", lib/core/store_name.dart)
      expect(stores.map((s) => s.name), ['CU 시청점', 'GS25 북쪽점']);
      expect(stores.first.location.latitude, closeTo(37.5666, 1e-6));
    });

    test('격자 칸 경계를 넘는 매장도 찾는다', () {
      // 37.56650 → 37.57100 은 위도 칸(0.01도)이 37.56 → 37.57 로 바뀐다.
      final stores = index.nearby(
        center: cityHall,
        category: StoreCategory.convenience,
        radiusMeters: 600,
      );
      expect(stores, hasLength(2));
    });
  });

  test('내장 전국 데이터로 서울시청 주변 편의점과 약국을 찾는다', () {
    final file = File('assets/stores.tsv.gz');
    final index = StoreIndex.parse(
      utf8.decode(gzip.decode(file.readAsBytesSync())),
    );
    expect(index.length, greaterThan(100000));

    final conv = index.nearby(
      center: cityHall,
      category: StoreCategory.convenience,
      radiusMeters: 500,
    );
    final pharmacy = index.nearby(
      center: cityHall,
      category: StoreCategory.pharmacy,
      radiusMeters: 500,
    );
    expect(conv, isNotEmpty);
    expect(pharmacy, isNotEmpty);
    for (final s in conv) {
      expect(distanceMeters(cityHall, s.location), lessThanOrEqualTo(500));
    }
  });
}
