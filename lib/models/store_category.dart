/// 물건을 살 수 있는 매장 종류.
///
/// enum 이름은 내장 매장 데이터(assets/stores.tsv.gz)의 카테고리 값과 같다.
/// 분류 기준은 tool/build_store_data.py 참고.
enum StoreCategory {
  convenience('편의점'),
  mart('마트·슈퍼'),
  pharmacy('약국'),
  daiso('다이소'),
  drugstore('올리브영'),
  stationery('문구점');

  const StoreCategory(this.label);

  final String label;

  static StoreCategory? fromName(String name) {
    for (final c in values) {
      if (c.name == name) return c;
    }
    return null;
  }
}
