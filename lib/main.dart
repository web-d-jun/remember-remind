import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/item_repository.dart';
import 'data/photo_store.dart';
import 'data/place_source.dart';
import 'data/store_cache.dart';
import 'services/location_tracker.dart';
import 'services/notification_action_bridge.dart';
import 'services/notification_service.dart';
import 'services/photo_text_reader.dart';
import 'services/voice_input.dart';
import 'state/shopping_list.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final photos = await PhotoStore.open();
  final list = ShoppingList(ItemRepository(prefs), photos: photos);
  final notifications = NotificationService(photos: photos);
  await notifications.init(onAction: list.applyAction);
  // 앱이 백그라운드에 있을 때 누른 알림 버튼도 화면의 목록에 바로 반영한다.
  NotificationActionReceiver(list).start();

  final places = OfflinePlaceSource();
  final tracker = LocationTracker(
    list: list,
    cache: StoreCache(places),
    notifications: notifications,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: list),
        ChangeNotifierProvider.value(value: tracker),
        Provider.value(value: photos),
        Provider(create: (_) => VoiceInput()),
        Provider(
          create: (_) => PhotoTextReader(),
          dispose: (_, reader) => reader.close(),
        ),
      ],
      child: const KkamagwiApp(),
    ),
  );

  await tracker.start();
}

class KkamagwiApp extends StatelessWidget {
  const KkamagwiApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 까마귀 깃털의 푸른 빛이 도는 검정.
    const seed = Color(0xFF34416B);
    return MaterialApp(
      title: '까마귀',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
