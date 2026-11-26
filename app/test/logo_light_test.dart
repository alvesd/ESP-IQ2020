import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iq2020_mobile/api/messages.dart';
import 'package:iq2020_mobile/ui/logo_light_badge.dart';

void main() {
  group('parseLogoLightState', () {
    test('handles null and missing states', () {
      expect(parseLogoLightState(null), LogoLightState.unknown);
      expect(parseLogoLightState(const EntityState(key: 1, missing: true, text: 'Power on')), LogoLightState.unknown);
    });

    test('parses all template text sensor strings case-insensitively', () {
      const cases = {
        'Unknown': LogoLightState.unknown,
        'Power on': LogoLightState.powerOn,
        'Power on & ready on': LogoLightState.powerAndReady,
        'Ready flash': LogoLightState.readyFlash,
        'Power flash': LogoLightState.powerFlash,
        'Power and ready flash': LogoLightState.powerAndReadyFlash,
        'Power and ready alternate': LogoLightState.powerAndReadyAlternate,
        'Power and ready salt error': LogoLightState.saltError,
        'POWER ON & READY ON': LogoLightState.powerAndReady,
      };
      for (final entry in cases.entries) {
        expect(parseLogoLightState(EntityState(key: 1, text: entry.key)), entry.value, reason: entry.key);
      }
    });

    test('parses numeric states 0..7 from number or string', () {
      const expected = [
        LogoLightState.unknown,
        LogoLightState.powerOn,
        LogoLightState.powerAndReady,
        LogoLightState.readyFlash,
        LogoLightState.powerFlash,
        LogoLightState.powerAndReadyFlash,
        LogoLightState.powerAndReadyAlternate,
        LogoLightState.saltError,
      ];
      for (var i = 0; i < expected.length; i++) {
        expect(parseLogoLightState(EntityState(key: 1, number: i.toDouble())), expected[i]);
        expect(parseLogoLightState(EntityState(key: 1, text: '$i')), expected[i]);
      }
      expect(parseLogoLightState(const EntityState(key: 1, number: 99)), LogoLightState.unknown);
    });
  });

  group('logoLightLedsAt', () {
    test('returns expected (green, blue) LEDs across phases 0.1, 0.4, 0.7', () {
      expect(logoLightLedsAt(LogoLightState.unknown, 0.1), (false, false));
      expect(logoLightLedsAt(LogoLightState.powerOn, 0.4), (false, true));
      expect(logoLightLedsAt(LogoLightState.powerAndReady, 0.7), (true, true));

      expect(logoLightLedsAt(LogoLightState.readyFlash, 0.1), (true, true));
      expect(logoLightLedsAt(LogoLightState.readyFlash, 0.7), (false, true));

      expect(logoLightLedsAt(LogoLightState.powerFlash, 0.4), (false, true));
      expect(logoLightLedsAt(LogoLightState.powerFlash, 0.7), (false, false));

      expect(logoLightLedsAt(LogoLightState.powerAndReadyFlash, 0.4), (true, true));
      expect(logoLightLedsAt(LogoLightState.powerAndReadyFlash, 0.7), (false, false));

      expect(logoLightLedsAt(LogoLightState.powerAndReadyAlternate, 0.1), (true, false));
      expect(logoLightLedsAt(LogoLightState.powerAndReadyAlternate, 0.7), (false, true));

      expect(logoLightLedsAt(LogoLightState.saltError, 0.1), (true, true));
      expect(logoLightLedsAt(LogoLightState.saltError, 0.4), (false, true));
      expect(logoLightLedsAt(LogoLightState.saltError, 0.7), (false, true));
    });
  });

  test('parseHotSpringSvgPath produces non-empty bounds for cubic and smooth commands', () {
    final p = parseHotSpringSvgPath('M0,0 C10,0 10,10 20,10 s10,10 20,10 H50 V20 z');
    final bounds = p.getBounds();
    expect(bounds.isEmpty, isFalse);
    expect(bounds.width, closeTo(50, 0.1));
    expect(bounds.height, closeTo(20, 0.1));
  });

  group('LogoLightBadge widget', () {
    testWidgets('renders solid state and status label without overflow in narrow header', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Heater off'),
                  SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: LogoLightBadge(
                        state: LogoLightState.powerAndReady,
                        customLabel: 'Power on & ready on',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Power on & ready on'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('animates flashing state cleanly across frames without overflow', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Heater off'),
                  SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: LogoLightBadge(
                        state: LogoLightState.powerAndReadyAlternate,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Power & ready alternate'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
