"""소상공인시장진흥공단 상가(상권)정보 → 앱에 내장할 매장 데이터로 변환한다.

사용법:
    python tool/build_store_data.py <다운로드한 zip 경로> [출력 경로]

데이터: https://www.data.go.kr/data/15083033/fileData.do (분기별 갱신, 이용허락범위 제한 없음)

출력 형식 (gzip으로 압축한 TSV, 한 줄에 매장 하나):
    카테고리<TAB>위도x100000<TAB>경도x100000<TAB>이름
카테고리 이름은 lib/models/store_category.dart 의 enum 이름과 같아야 한다.
"""

import collections
import csv
import gzip
import io
import sys
import zipfile

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


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()
