"""소상공인시장진흥공단 상가(상권)정보 → 앱에 내장할 매장 데이터로 변환한다.

사용법:
    python tool/build_store_data.py <다운로드한 zip 경로> [출력 경로]
    python tool/build_store_data.py --refilter [데이터 경로]   # 이미 만든 데이터에 제외 규칙만 다시 적용

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
import re
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


# 슈퍼마켓 코드(G20404)로 등록됐지만 마트가 아닌 가게들.
#
# 1) 아이스크림·과자 할인점(약 3,400곳): 'snack'으로 따로 둔다. 마트로 넣으면 우유·젖병솔도
#    "여기서 살 수 있어요"라고 틀리게 알리고, 빼 버리면 아이스크림을 등록해도 이 가게들을
#    못 찾는다. 이름에 "마트/마켓"이 있어도 대부분 같은 가게라, 슈퍼·편의점·하나로처럼
#    확실히 장 보는 곳일 때만 마트로 남긴다.
# 2) 빵집·방앗간·정육점·담배 가게 등: 파는 물건이 제각각이라 뺀다.
_SNACK = re.compile(r'아이스|과자|스낵|간식|캔디|젤리')
_NARROW = re.compile(r'빵|분식|키즈카페|놀이터|쿠키|떡|디저트|커피|와인|주류|담배|'
                     r'홍삼|건강원|방앗간|정육|축산|수산|건어물|청과|과일|반찬|펫|반려')
_GROCERY_STRONG = re.compile(r'슈퍼|편의점|하나로|농협|식자재|상회|연쇄점')
_GROCERY = re.compile(r'마트|마켓|상점|생협|한살림|두레|아이쿱|자연드림|종합|'
                      + _GROCERY_STRONG.pattern)


def mart_kind(name):
    """슈퍼마켓 코드로 등록된 가게를 다시 나눈다. 'mart', 'snack', 또는 None(뺀다).

    '더샵아이스크림할인점' -> 'snack', '아이스크림할인마트' -> 'snack',
    '대한방앗간' -> None, '현산청과슈퍼' -> 'mart', '농축산하나로마트' -> 'mart'
    """
    n = name.replace(' ', '')
    if _SNACK.search(n):
        return 'mart' if _GROCERY_STRONG.search(n) else 'snack'
    if _NARROW.search(n) and not _GROCERY.search(n):
        return None
    return 'mart'


def classify(name, code):
    for keyword, category in NAME_RULES:
        if keyword in name:
            return category
    category = CODE_RULES.get(code)
    if category == 'mart':
        return mart_kind(name)
    return category


def refilter(asset):
    """원본 zip 없이, 이미 만든 데이터의 마트에 [mart_kind] 규칙만 다시 적용한다.

    대형 매장(L)은 건드리지 않는다. 여러 번 돌려도 결과가 같다.
    """
    with gzip.open(asset, 'rt', encoding='utf-8') as f:
        lines = f.read().splitlines()
    kept, dropped, snack = [], 0, 0
    for line in lines:
        parts = line.split('\t')
        large = len(parts) > 4 and parts[4] == 'L'
        if parts[0] == 'mart' and not large:
            kind = mart_kind(parts[3])
            if kind is None:
                dropped += 1
                continue
            if kind == 'snack':
                snack += 1
                parts[0] = 'snack'
                line = '\t'.join(parts)
        kept.append(line)
    with gzip.open(asset, 'wt', encoding='utf-8', compresslevel=9) as w:
        w.write('\n'.join(kept) + '\n')
    print(f'{len(lines):,}건 중 아이스크림·과자 할인점 {snack:,}건, 제외 {dropped:,}건 -> {asset}')


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


def is_small_format(name):
    """같은 브랜드의 작은 매장(SSM)인지. 대형 매장 판정(L)을 붙이지 않는다."""
    brand = _brand(name)
    return brand is not None and brand.endswith('-small')


_CORP = re.compile(r'\(주\)|㈜|주식회사|\(유\)|\(합\)')


def clean_name(name):
    """알림에 보일 이름을 다듬는다.

    '(주)이마트 통영점' -> '이마트 통영점', '롯데쇼핑(주)롯데마트통영점' -> '롯데마트통영점',
    '삼성테스코(주)홈플러스 광주하남점' -> '홈플러스 광주하남점'
    """
    n = ' '.join(_CORP.sub(' ', name).split())
    for b in BRANDS:
        i = n.find(b)
        if i > 0:
            n = n[i:]
            break
    return n or name


def _better_name(a, b):
    """같은 매장의 두 이름 중 알림에 쓰기 좋은 쪽. 지점명('~점')이 있는 쪽, 그다음 짧은 쪽."""
    return min(a, b, key=lambda n: (not n.endswith('점'), len(n)))


def _distance_m(lat1, lng1, lat2, lng2):
    # 좌표는 x100000 정수. 짧은 거리라 평면 근사로 충분하다.
    dy = (lat1 - lat2) / 100000 * 111320
    dx = (lng1 - lng2) / 100000 * 111320 * math.cos(math.radians(lat1 / 100000))
    return math.hypot(dx, dy)


def merge_extra_stores(asset, extra_paths):
    """extra_paths 의 매장을 asset 에 합친다. 같은 매장으로 보이는 기존 줄은 뺀다.

    여러 번 실행해도 결과가 같다(이전에 합친 줄도 같은 매장으로 보고 교체된다).
    """
    cell = 300  # x100000 단위, 약 300m
    grid = collections.defaultdict(list)

    def find_same(category, lat, lng, name):
        brand = _brand(name)
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for e in grid.get((lat // cell + i, lng // cell + j), ()):
                    if e[0] != category:
                        continue
                    d = _distance_m(lat, lng, e[1], e[2])
                    if d <= SAME_PLACE_M or (
                            brand and d <= SAME_BRAND_M and brand == _brand(e[3])):
                        return e
        return None

    def duplicate(category, lat, lng, name):
        return find_same(category, lat, lng, name) is not None

    # 대규모점포 데이터에는 같은 매장이 여러 번 있다(재등록, 회사명 변경 등). 하나로 합친다.
    extra = []
    merged = 0
    for path in extra_paths:
        with open(path, encoding='utf-8') as f:
            for line in f:
                parts = line.rstrip('\n').split('\t')
                if len(parts) < 4:
                    continue
                row = [parts[0], int(parts[1]), int(parts[2]), clean_name(parts[3])]
                same = find_same(*row)
                if same is not None:
                    same[3] = _better_name(same[3], row[3])
                    merged += 1
                    continue
                extra.append(row)
                grid[(row[1] // cell, row[2] // cell)].append(row)
    if merged:
        print(f'  같은 매장 중복 {merged:,}건 합침')

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
    # mtime=0: 내용이 같으면 파일도 똑같게 (다시 실행해도 git 변경으로 안 잡히게)
    with gzip.GzipFile(tmp, 'wb', compresslevel=9, mtime=0) as raw, \
            io.TextIOWrapper(raw, encoding='utf-8', newline='\n') as w:
        w.writelines(kept)
        large = 0
        for category, lat, lng, name in extra:
            # 다섯째 칸 L: 대형 매장. 앱이 "매장 안" 판정을 느슨하게 한다.
            # 홈플러스 익스프레스 같은 작은 매장은 일반 매장처럼 판단한다.
            if is_small_format(name):
                w.write(f'{category}\t{lat}\t{lng}\t{name}\n')
            else:
                w.write(f'{category}\t{lat}\t{lng}\t{name}\tL\n')
                large += 1
    os.replace(tmp, asset)
    print(f'대형마트 등 {len(extra):,}곳 합침 (대형 {large:,}곳, 작은 매장 '
          f'{len(extra) - large:,}곳 / 겹치는 기존 {dropped:,}곳 교체) -> {asset}')


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    if len(sys.argv) > 1 and sys.argv[1] == '--refilter':
        refilter(sys.argv[2] if len(sys.argv) > 2 else 'assets/stores.tsv.gz')
    else:
        main()
