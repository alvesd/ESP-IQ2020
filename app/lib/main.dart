import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  static const _seed = Color(0xFF0E7C86); // spa teal

  static ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final dark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF0F1416) : const Color(0xFFF3F6F7),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF1A2124) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        // Transparent bar: tell iOS which status bar text colour to use or it can turn invisible.
        systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
          letterSpacing: -0.5,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: dark ? const Color(0xFF151B1D) : Colors.white,
        indicatorColor: scheme.primaryContainer,
        selectedLabelTextStyle: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF151B1D) : Colors.white,
        indicatorColor: scheme.primaryContainer,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hot Tub',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: HomeScreen(store: store),
    );
  }
}
