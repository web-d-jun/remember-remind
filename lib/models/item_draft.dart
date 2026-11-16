import 'store_category.dart';

/// 추가 화면에서 만든, 아직 저장하지 않은 물건.
typedef ItemDraft = ({
  String name,
  Set<StoreCategory> categories,
  bool important,
  String? photo,
});
