// Flutter side of ios/Runner/NativeTabsPlugin.swift: hands the spa screen's tabs to the native
// iOS tab bar (which iPhone Duo shows in its own system bar). On other platforms, or if the
// native side can't attach, the spa screen falls back to drawing its own rail/bottom bar.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeTab {
  final String id;
  final String title;
  final String symbol; // SF Symbol name
  const NativeTab(this.id, this.title, this.symbol);

  Map<String, String> toMap() => {'id': id, 'title': title, 'symbol': symbol};
}

class NativeTabs {
  static const _channel = MethodChannel('iq2020/native_tabs');
  static ValueChanged<String>? _onSelected;
  static String _lastSignature = '';

  static bool get supported => !kIsWeb && Platform.isIOS;

  /// Shows [tabs] in the native tab bar. Returns false if the native bar isn't available, in
  /// which case the caller should draw its own navigation.
  static Future<bool> show(List<NativeTab> tabs, String selected, ValueChanged<String> onSelected) async {
    if (!supported) return false;
    _onSelected = onSelected;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'selected' && call.arguments is String) _onSelected?.call(call.arguments as String);
    });
    final signature = '${tabs.map((t) => t.id).join(',')}|$selected';
    if (signature == _lastSignature) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('setTabs', {
        'tabs': [for (final t in tabs) t.toMap()],
        'selected': selected,
      });
      if (ok == true) _lastSignature = signature;
      return ok == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> hide() async {
    if (!supported) return;
    _onSelected = null;
    _lastSignature = '';
    try {
      await _channel.invokeMethod<void>('hide');
    } on MissingPluginException {
      // Native side not registered (e.g. tests); nothing to hide.
    }
  }
}
