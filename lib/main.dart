import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/item_repository.dart';
import 'data/place_source.dart';
import 'data/store_cache.dart';
import 'services/location_tracker.dart';
import 'services/notification_service.dart';
import 'state/shopping_list.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final list = ShoppingList(ItemRepository(prefs));
  final notifications = NotificationService();
  await notifications.init();

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
      ],
      child: const RememberApp(),
    ),
  );

  await tracker.start();
}

class RememberApp extends StatelessWidget {
  const RememberApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D5B);
    return MaterialApp(
      title: '빠짐없이',
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
