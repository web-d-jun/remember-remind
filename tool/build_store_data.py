"""소상공인시장진흥공단 상가(상권)정보 → 앱에 내장할 매장 데이터로 변환한다.

사용법:
    python tool/build_store_data.py <다운로드한 zip 경로> [출력 경로]

데이터: https://www.data.go.kr/data/15083033/fileData.do (분기별 갱신, 이용허락범위 제한 없음)

출력 형식 (gzip으로 압축한 TSV, 한 줄에 매장 하나):
    카테고리<TAB>위도x100000<TAB>경도x100000<TAB>이름[<TAB>L]
    (다섯째 칸 L은 대형 매장. fetch_large_stores.py 로 합친 대형마트에 붙는다)
카테고리 이름은 lib/models/store_category.dart 의 enum 이름과 같아야 한다.
"""

import collections
import csv
import gzip
import io
import math
import os
import sys
import zipfile

# fetch_large_stores.py 가 만든 대형마트 목록. 있으면 자동으로 합친다.
LARGE_STORES = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            'large_stores.tsv')

# 상호명 규칙이 업종코드보다 우선한다. (다이소가 슈퍼마켓 코드로 등록된 경우 등)
NAME_RULES = [
    ('다이소', 'daiso'),
    ('올리브영', 'drugstore'),
]

CODE_RULES = {
    'G20405': 'convenience',  # 편의점
    'G20404': 'mart',  # 슈퍼마켓
    'G21501': 'pharmacy',  # 약국
    'G21302': 'stationery',  # 문구/회화용품 소매업
}


def classify(name, code):
    for keyword, category in NAME_RULES:
        if keyword in name:
            return category
    return CODE_RULES.get(code)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else 'assets/stores.tsv.gz'

    counts = collections.Counter()
    rows = 0
    with zipfile.ZipFile(src) as z, gzip.open(out, 'wt', encoding='utf-8',
                                              compresslevel=9) as w:
        for member in sorted(z.namelist()):
            if not member.endswith('.csv'):
                continue
            with z.open(member) as raw:
                reader = csv.reader(io.TextIOWrapper(raw, encoding='utf-8-sig'))
                cols = {c: i for i, c in enumerate(next(reader))}
                for row in reader:
                    rows += 1
                    name = row[cols['상호명']].strip()
                    category = classify(name, row[cols['상권업종소분류코드']])
                    if category is None:
                        continue
                    try:
                        lat = round(float(row[cols['위도']]) * 100000)
                        lng = round(float(row[cols['경도']]) * 100000)
                    except ValueError:
                        continue
                    branch = row[cols['지점명']].strip()
                    label = f'{name} {branch}' if branch else name
                    label = label.replace('\t', ' ').replace('\n', ' ')
                    w.write(f'{category}\t{lat}\t{lng}\t{label}\n')
                    counts[category] += 1

    print(f'전체 {rows:,}건 중 {sum(counts.values()):,}건 추출 -> {out}')
    for category, n in counts.most_common():
        print(f'  {category}: {n:,}')

    if os.path.exists(LARGE_STORES):
        merge_extra_stores(out, [LARGE_STORES])


# 같은 매장으로 볼 거리(m). 이름에 같은 브랜드가 있으면 더 넓게 본다.
SAME_PLACE_M = 30
SAME_BRAND_M = 200
BRANDS = ['이마트', '트레이더스', '홈플러스', '롯데마트', '코스트코', '하나로',
          '메가마트', '탑마트', '다이소']


def _brand(name):
    compact = name.replace(' ', '')
    brand = next((b for b in BRANDS if b in compact), None)
    # 홈플러스 익스프레스, 이마트 에브리데이 등은 근처에 따로 있는 슈퍼마켓이다.
    if brand and any(s in compact for s in ('익스프레스', '에브리데이', '노브랜드')):
        return brand + '-small'
    return brand


def _distance_m(lat1, lng1, lat2, lng2):
    # 좌표는 x100000 정수. 짧은 거리라 평면 근사로 충분하다.
    dy = (lat1 - lat2) / 100000 * 111320
    dx = (lng1 - lng2) / 100000 * 111320 * math.cos(math.radians(lat1 / 100000))
    return math.hypot(dx, dy)


def merge_extra_stores(asset, extra_paths):
    """extra_paths 의 매장을 asset 에 합친다. 같은 매장으로 보이는 기존 줄은 뺀다.

    여러 번 실행해도 결과가 같다(이전에 합친 줄도 같은 매장으로 보고 교체된다).
    """
    extra = []
    for path in extra_paths:
        with open(path, encoding='utf-8') as f:
            for line in f:
                parts = line.rstrip('\n').split('\t')
                if len(parts) == 4:
                    extra.append((parts[0], int(parts[1]), int(parts[2]), parts[3]))

    cell = 300  # x100000 단위, 약 300m
    grid = collections.defaultdict(list)
    for e in extra:
        grid[(e[1] // cell, e[2] // cell)].append(e)

    def duplicate(category, lat, lng, name):
        brand = _brand(name)
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for e in grid.get((lat // cell + i, lng // cell + j), ()):
                    if e[0] != category:
                        continue
                    d = _distance_m(lat, lng, e[1], e[2])
                    if d <= SAME_PLACE_M or (
                            brand and d <= SAME_BRAND_M and brand == _brand(e[3])):
                        return True
        return False

    kept = []
    dropped = 0
    with gzip.open(asset, 'rt', encoding='utf-8') as f:
        for line in f:
            parts = line.rstrip('\n').split('\t')
            if len(parts) >= 4 and duplicate(parts[0], int(parts[1]),
                                             int(parts[2]), parts[3]):
                dropped += 1
                continue
            kept.append(line if line.endswith('\n') else line + '\n')

    tmp = asset + '.tmp'
    with gzip.open(tmp, 'wt', encoding='utf-8', compresslevel=9, newline='\n') as w:
        w.writelines(kept)
        for category, lat, lng, name in extra:
            # 다섯째 칸 L: 대형 매장. 앱이 "매장 안" 판정을 느슨하게 한다.
            w.write(f'{category}\t{lat}\t{lng}\t{name}\tL\n')
    os.replace(tmp, asset)
    print(f'대형마트 {len(extra):,}곳 합침 (겹치는 기존 {dropped:,}곳 교체) -> {asset}')


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()
