import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_store.dart';
import 'ui/home_screen.dart';
import 'ui/spa_backdrop.dart';

// Compiled into the app so WatchRelay.swift's headless engine can start it (Apple Watch relay).
export 'watch/watch_relay.dart' show watchRelayMain;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = DeviceStore();
  await store.load();
  runApp(Iq2020App(store: store));
}

/// Night-spa palette. Screens sit on a blurred hot tub scene (ui/spa_backdrop.dart), so the
/// app always uses this one dark theme with translucent "frosted glass" surfaces.
abstract final class SpaColors {
  static const aqua = Color(0xFF4FE3EA); // primary actions, selection
  static const deepTeal = Color(0xFF0B2A33);
  static const ink = Color(0xFF061419); // sheets, dialogs
  static const amber = Color(0xFFFFB86B); // heat / warm accents
  static const glass = Color(0x24FFFFFF); // cards over the backdrop
  static const glassBorder = Color(0x1FFFFFFF);
  static const bar = Color(0xCC0A1E26); // Flutter-drawn rail / bottom bar
}

class Iq2020App extends StatelessWidget {
  final DeviceStore store;
  const Iq2020App({super.key, required this.store});

  static ThemeData theme() {
    WidgetStateProperty<Color?> selectedColor(Color? on, Color off) =>
        WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? on : off);
    final scheme = ColorScheme.fromSeed(seedColor: SpaColors.aqua, brightness: Brightness.dark).copyWith(
      primary: SpaColors.aqua,
      onPrimary: SpaColors.ink,
      primaryContainer: const Color(0xFF14525E),
      onPrimaryContainer: const Color(0xFFCFFBFF),
      secondary: SpaColors.amber,
      surface: SpaColors.deepTeal,
      onSurface: Colors.white,
      onSurfaceVariant: const Color(0xFFB4CCD2),
      outline: const Color(0xFF8FA9B0),
      outlineVariant: const Color(0x40FFFFFF),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      cardTheme: CardThemeData(
        elevation: 0,
        color: SpaColors.glass,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: SpaColors.glassBorder),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: const AppBarTheme(
        // Light status bar text over the dark scene.
        systemOverlayStyle: SystemUiOverlayStyle.light,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: SpaColors.glass,
        side: BorderSide(color: SpaColors.glassBorder),
        labelStyle: TextStyle(color: Colors.white),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: SpaColors.bar,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: const IconThemeData(color: SpaColors.aqua),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: const TextStyle(color: SpaColors.aqua, fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: SpaColors.bar,
        indicatorColor: scheme.primaryContainer,
      ),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: SpaColors.ink),
      dialogTheme: const DialogThemeData(backgroundColor: SpaColors.ink),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: SpaColors.aqua,
        foregroundColor: SpaColors.ink,
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: selectedColor(Colors.transparent, const Color(0x66FFFFFF)),
        thumbColor: selectedColor(Colors.white, const Color(0xCCFFFFFF)),
        trackColor: selectedColor(null, const Color(0x26FFFFFF)),
      ),
      dividerTheme: const DividerThemeData(color: SpaColors.glassBorder),
      listTileTheme: const ListTileThemeData(iconColor: Color(0xFFB4CCD2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = theme();
    return MaterialApp(
      title: 'Hot Tub',
      debugShowCheckedModeBanner: false,
      theme: t,
      themeMode: ThemeMode.dark,
      darkTheme: t,
      home: SpaBackdrop(child: HomeScreen(store: store)),
    );
  }
}
