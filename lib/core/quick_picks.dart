import '../models/store_category.dart';

/// 예전에 기억했던 물건 기록. 자주 사는 물건을 한 번 눌러 다시 추가하는 데 쓴다.
class HistoryEntry {
  const HistoryEntry({
    required this.name,
    required this.categories,
    required this.count,
    required this.lastAt,
  });

  final String name;
  final Set<StoreCategory> categories;
  final int count;
  final DateTime lastAt;

  HistoryEntry bump(Set<StoreCategory> categories, DateTime now) =>
      HistoryEntry(
        name: name,
        categories: categories,
        count: count + 1,
        lastAt: now,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'categories': categories.map((c) => c.name).toList(),
    'count': count,
    'lastAt': lastAt.toIso8601String(),
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    name: json['name'] as String,
    categories: ((json['categories'] as List?) ?? const [])
        .map((e) => StoreCategory.fromName(e as String))
        .whereType<StoreCategory>()
        .toSet(),
    count: json['count'] as int? ?? 1,
    lastAt: DateTime.parse(json['lastAt'] as String),
  );
}

/// 처음 쓸 때(기록이 적을 때) 보여줄 흔한 물건들.
const defaultQuickPicks = [
  '우유', '계란', '휴지', '생수', '라면', '두부', '건전지', '쓰레기봉투', //
  '샴푸', '세제', '감기약', '물티슈',
];

/// 한 번 눌러 추가할 물건 이름을 고른다.
///
/// 자주, 최근에 기억한 물건이 앞에 온다. 이미 목록에 있는 물건은 뺀다.
/// 기록이 [limit]보다 적으면 흔한 물건으로 채운다.
List<String> rankQuickPicks({
  required Iterable<HistoryEntry> history,
  required Set<String> pendingNames,
  required DateTime now,
  int limit = 12,
}) {
  double score(HistoryEntry e) {
    final days = now.difference(e.lastAt).inHours / 24;
    // 한 달 지나면 반쯤 잊는다.
    return e.count / (1 + days / 30);
  }

  final ranked = history.where((e) => !pendingNames.contains(e.name)).toList()
    ..sort((a, b) => score(b).compareTo(score(a)));
  final names = [for (final e in ranked.take(limit)) e.name];

  for (final d in defaultQuickPicks) {
    if (names.length >= limit) break;
    if (!names.contains(d) && !pendingNames.contains(d)) names.add(d);
  }
  return names;
}
