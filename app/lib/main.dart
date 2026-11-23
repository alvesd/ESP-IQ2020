import 'package:flutter/material.dart';

import 'device_store.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = DeviceStore();
  await store.load();
  runApp(Iq2020App(store: store));
}

class Iq2020App extends StatelessWidget {
  final DeviceStore store;
  const Iq2020App({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0E7C86); // spa teal
    return MaterialApp(
      title: 'Hot Tub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: HomeScreen(store: store),
    );
  }
}
