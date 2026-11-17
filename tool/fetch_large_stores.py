"""대규모점포(이마트·홈플러스 등) 인허가 정보를 받아 앱 내장 매장 데이터에 합친다.

소상공인 상가정보에는 대형마트가 거의 빠져 있어서, 대형마트는 이 데이터로 보완한다.

사용법:
    python tool/fetch_large_stores.py <서비스키>
    (또는 환경변수 DATA_GO_KR_KEY 에 서비스키를 넣고 인자 없이 실행)

    python tool/fetch_large_stores.py --merge-only
    (API 호출 없이 tool/large_stores.tsv 만 다시 합친다)

데이터: 행정안전부_생활_대규모점포 조회서비스 (공공데이터포털 15154948, 매일 갱신,
이용허락범위 제한 없음). https://www.data.go.kr/data/15154948/openapi.do 에서
활용신청하면 서비스키가 나온다.

결과:
    tool/large_stores.tsv     받은 대형마트 목록 (build_store_data.py 와 같은 형식).
                              커밋해 두면 소상공인 데이터를 다시 만들 때 서비스키 없이 합칠 수 있다.
    assets/stores.tsv.gz      위 목록을 합친 앱 내장 데이터
"""

import collections
import json
import math
import os
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

from build_store_data import merge_extra_stores

API_URL = 'https://apis.data.go.kr/1741000/large_scale_retail_stores/info'
PAGE_SIZE = 1000
HERE = os.path.dirname(os.path.abspath(__file__))
LARGE_STORES = os.path.join(HERE, 'large_stores.tsv')
ASSET = os.path.join(HERE, '..', 'assets', 'stores.tsv.gz')

# 상호명으로 고른다. 점포구분이 '대형마트'가 아니어도(쇼핑센터·복합쇼핑몰 안 매장 등) 포함한다.
NAME_RULES = [
    ('다이소', 'daiso'),
    ('이마트', 'mart'),
    ('트레이더스', 'mart'),
    ('홈플러스', 'mart'),
    ('롯데마트', 'mart'),
    ('코스트코', 'mart'),
    ('하나로마트', 'mart'),
    ('하나로클럽', 'mart'),
    ('메가마트', 'mart'),
    ('탑마트', 'mart'),
]


def classify(name, store_kind):
    for keyword, category in NAME_RULES:
        if keyword in name:
            return category
    if '대형마트' in store_kind:
        return 'mart'
    return None


# --- 좌표 변환: EPSG:5174 (보정 안 된 Bessel 중부원점 TM) -> WGS84 ---

_BESSEL_A = 6377397.155
_BESSEL_F = 1 / 299.1528128
_WGS_A = 6378137.0
_WGS_F = 1 / 298.257223563
_LAT0 = math.radians(38.0)
_LON0 = math.radians(127.0 + 10.405 / 3600)  # 127°00'10.405"
_X0, _Y0, _K0 = 200000.0, 500000.0, 1.0
# proj 의 +towgs84 (position vector, 각도는 초, 축척은 ppm)
_TOWGS84 = (-115.80, 474.99, 674.11, 1.16, -2.31, -1.63, 6.43)


def _meridian_arc(lat, a, e2):
    e4, e6 = e2 * e2, e2 * e2 * e2
    return a * ((1 - e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256) * lat
                - (3 * e2 / 8 + 3 * e4 / 32 + 45 * e6 / 1024) * math.sin(2 * lat)
                + (15 * e4 / 256 + 45 * e6 / 1024) * math.sin(4 * lat)
                - (35 * e6 / 3072) * math.sin(6 * lat))


def _tm_inverse(x, y):
    """TM 평면좌표 -> Bessel 위경도(라디안). Snyder, Map Projections 8-?."""
    a, f = _BESSEL_A, _BESSEL_F
    e2 = f * (2 - f)
    ep2 = e2 / (1 - e2)
    m = _meridian_arc(_LAT0, a, e2) + (y - _Y0) / _K0
    mu = m / (a * (1 - e2 / 4 - 3 * e2 ** 2 / 64 - 5 * e2 ** 3 / 256))
    e1 = (1 - math.sqrt(1 - e2)) / (1 + math.sqrt(1 - e2))
    lat1 = (mu + (3 * e1 / 2 - 27 * e1 ** 3 / 32) * math.sin(2 * mu)
            + (21 * e1 ** 2 / 16 - 55 * e1 ** 4 / 32) * math.sin(4 * mu)
            + (151 * e1 ** 3 / 96) * math.sin(6 * mu)
            + (1097 * e1 ** 4 / 512) * math.sin(8 * mu))
    c1 = ep2 * math.cos(lat1) ** 2
    t1 = math.tan(lat1) ** 2
    n1 = a / math.sqrt(1 - e2 * math.sin(lat1) ** 2)
    r1 = a * (1 - e2) / (1 - e2 * math.sin(lat1) ** 2) ** 1.5
    d = (x - _X0) / (n1 * _K0)
    lat = lat1 - (n1 * math.tan(lat1) / r1) * (
        d ** 2 / 2
        - (5 + 3 * t1 + 10 * c1 - 4 * c1 ** 2 - 9 * ep2) * d ** 4 / 24
        + (61 + 90 * t1 + 298 * c1 + 45 * t1 ** 2 - 252 * ep2 - 3 * c1 ** 2) * d ** 6 / 720)
    lon = _LON0 + (d - (1 + 2 * t1 + c1) * d ** 3 / 6
                   + (5 - 2 * c1 + 28 * t1 - 3 * c1 ** 2 + 8 * ep2 + 24 * t1 ** 2) * d ** 5 / 120
                   ) / math.cos(lat1)
    return lat, lon


def _to_ecef(lat, lon, a, f):
    e2 = f * (2 - f)
    n = a / math.sqrt(1 - e2 * math.sin(lat) ** 2)
    return (n * math.cos(lat) * math.cos(lon),
            n * math.cos(lat) * math.sin(lon),
            n * (1 - e2) * math.sin(lat))


def _from_ecef(x, y, z, a, f):
    e2 = f * (2 - f)
    lon = math.atan2(y, x)
    p = math.hypot(x, y)
    lat = math.atan2(z, p * (1 - e2))
    for _ in range(10):
        n = a / math.sqrt(1 - e2 * math.sin(lat) ** 2)
        lat = math.atan2(z + e2 * n * math.sin(lat), p)
    return lat, lon


def epsg5174_to_wgs84(x, y):
    """중부원점 TM(EPSG:5174) 좌표를 WGS84 (위도, 경도) 도 단위로 바꾼다."""
    lat, lon = _tm_inverse(x, y)
    bx, by, bz = _to_ecef(lat, lon, _BESSEL_A, _BESSEL_F)
    tx, ty, tz, rx, ry, rz, s = _TOWGS84
    sec = math.pi / (180 * 3600)
    rx, ry, rz, s = rx * sec, ry * sec, rz * sec, 1 + s * 1e-6
    wx = tx + s * (bx - rz * by + ry * bz)
    wy = ty + s * (rz * bx + by - rx * bz)
    wz = tz + s * (-ry * bx + rx * by + bz)
    lat, lon = _from_ecef(wx, wy, wz, _WGS_A, _WGS_F)
    return math.degrees(lat), math.degrees(lon)


# --- API 호출 ---

def _fetch_page(key, page):
    # 포털에서 받은 '인코딩' 키(%가 들어간 것)는 그대로, '디코딩' 키는 인코딩해서 보낸다.
    key_param = key if '%' in key else urllib.parse.quote(key, safe='')
    query = urllib.parse.urlencode(
        {'pageNo': page, 'numOfRows': PAGE_SIZE, 'returnType': 'json'})
    url = f'{API_URL}?serviceKey={key_param}&{query}'
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=60) as res:
                text = res.read().decode('utf-8')
            return _parse(text)
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                body = e.read().decode('utf-8', 'replace')[:300]
                sys.exit('서비스키가 거부되었습니다. 활용신청 승인 여부와 키를 확인하세요.\n'
                         '(신청 직후에는 키가 동작하기까지 1~2시간 걸릴 수 있습니다)\n' + body)
            if attempt == 2:
                raise
            print(f'  {page}쪽 다시 시도 ({e})')
            time.sleep(2)
        except (OSError, ValueError) as e:
            if attempt == 2:
                raise
            print(f'  {page}쪽 다시 시도 ({e})')
            time.sleep(2)


def _parse(text):
    """(전체 개수, 항목 목록)을 돌려준다. JSON/XML 둘 다 받는다."""
    text = text.strip()
    if text.startswith('{'):
        body = json.loads(text)['response']
        code = str(body['header']['resultCode'])
        if code not in ('0', '00'):
            raise RuntimeError(f"API 오류 {code}: {body['header'].get('resultMsg')}")
        body = body['body']
        items = body.get('items') or {}
        items = items.get('item', []) if isinstance(items, dict) else items
        if isinstance(items, dict):
            items = [items]
        return int(body.get('totalCount', 0)), items

    root = ET.fromstring(text)
    code = root.findtext('.//resultCode') or root.findtext('.//returnReasonCode')
    if code not in ('0', '00'):
        msg = (root.findtext('.//resultMsg') or root.findtext('.//returnAuthMsg')
               or root.findtext('.//errMsg'))
        raise RuntimeError(f'API 오류 {code}: {msg}')
    items = [{c.tag: (c.text or '') for c in item} for item in root.iter('item')]
    return int(root.findtext('.//totalCount') or 0), items


def fetch_all(key):
    # 서버가 numOfRows 를 더 작게 잘라 줄 수 있으므로, 쪽 수를 미리 계산하지 않고
    # 전체 개수만큼 모일 때까지(또는 빈 쪽이 나올 때까지) 다음 쪽을 받는다.
    total, items = _fetch_page(key, 1)
    print(f'전체 {total:,}건 (한 쪽에 {len(items):,}건)')
    page = 1
    while items and len(items) < total:
        page += 1
        _, more = _fetch_page(key, page)
        if not more:
            break
        items += more
        print(f'  {page}쪽, {len(items):,}/{total:,}건')
    if len(items) < total:
        print(f'  주의: {total:,}건 중 {len(items):,}건만 받았습니다.')
    return items


def is_open(item):
    # 영업상태: 01 영업/정상, 02 휴업, 03 폐업 ...
    code = (item.get('SALS_STTS_CD') or '').strip()
    name = item.get('SALS_STTS_NM') or ''
    return code == '01' or (not code and '영업' in name)


def to_rows(items):
    rows = []
    skipped = collections.Counter()
    for item in items:
        if not is_open(item):
            skipped['폐업·휴업'] += 1
            continue
        name = ' '.join((item.get('BPLC_NM') or '').split())
        category = classify(name, item.get('STOR_SE_NM') or '')
        if category is None:
            skipped['대상 아님(백화점·쇼핑센터 등)'] += 1
            continue
        try:
            x = float(item['CRD_INFO_X'])
            y = float(item['CRD_INFO_Y'])
        except (KeyError, TypeError, ValueError):
            skipped['좌표 없음'] += 1
            continue
        lat, lng = epsg5174_to_wgs84(x, y)
        if not (33 < lat < 39 and 124 < lng < 132):
            skipped['좌표 이상'] += 1
            continue
        rows.append((category, round(lat * 100000), round(lng * 100000), name))
    for reason, n in skipped.most_common():
        print(f'  제외 {reason}: {n:,}')
    return rows


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    args = sys.argv[1:]
    if args != ['--merge-only']:
        key = args[0] if args else os.environ.get('DATA_GO_KR_KEY')
        if not key:
            print(__doc__)
            sys.exit(1)
        rows = to_rows(fetch_all(key))
        rows.sort()
        with open(LARGE_STORES, 'w', encoding='utf-8', newline='\n') as w:
            for category, lat, lng, name in rows:
                w.write(f'{category}\t{lat}\t{lng}\t{name}\n')
        counts = collections.Counter(r[0] for r in rows)
        print(f'대형마트 등 {len(rows):,}곳 -> {LARGE_STORES}')
        for category, n in counts.most_common():
            print(f'  {category}: {n:,}')
    elif not os.path.exists(LARGE_STORES):
        sys.exit(f'{LARGE_STORES} 가 없습니다. 먼저 서비스키로 한 번 실행하세요.')
    merge_extra_stores(ASSET, [LARGE_STORES])


if __name__ == '__main__':
    main()
