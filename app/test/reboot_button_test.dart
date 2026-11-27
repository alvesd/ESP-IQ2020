import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iq2020_mobile/api/messages.dart';
import 'package:iq2020_mobile/ui/spa_screen.dart';

void main() {
  test('isRestartButtonEntity identifies ESP restart buttons and ignores spa buttons', () {
    expect(
      isRestartButtonEntity(EntityInfo(
        kind: EntityKind.button,
        key: 1,
        objectId: 'esp_restart',
        name: 'ESP Restart',
        deviceClass: 'restart',
      )),
      isTrue,
    );
    expect(
      isRestartButtonEntity(EntityInfo(
        kind: EntityKind.button,
        key: 2,
        objectId: 'custom_reboot',
        name: 'Reboot',
      )),
      isTrue,
    );
    expect(
      isRestartButtonEntity(EntityInfo(
        kind: EntityKind.button,
        key: 3,
        objectId: 'salt_test',
        name: 'Salt Test',
      )),
      isFalse,
    );
    expect(
      isRestartButtonEntity(EntityInfo(
        kind: EntityKind.button,
        key: 4,
        objectId: 'reset_salt_cartridge',
        name: 'Reset Salt Cartridge',
      )),
      isFalse,
    );
    expect(
      isRestartButtonEntity(EntityInfo(
        kind: EntityKind.sensor,
        key: 5,
        objectId: 'esp_restart_count',
        name: 'Restart Count',
      )),
      isFalse,
    );
  });

  testWidgets('RebootSystemRow confirms before rebooting and respects enabled flag', (tester) async {
    var reboots = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RebootSystemRow(
            enabled: false,
            onReboot: () => reboots++,
          ),
        ),
      ),
    );
    expect(find.text('Reboot system'), findsOneWidget);
    await tester.tap(find.text('Reboot'));
    await tester.pumpAndSettle();
    expect(find.text('Reboot system?'), findsNothing);
    expect(reboots, 0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RebootSystemRow(
            enabled: true,
            onReboot: () => reboots++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Reboot'));
    await tester.pumpAndSettle();
    expect(find.text('Reboot system?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(reboots, 0);

    await tester.tap(find.text('Reboot'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reboot'));
    await tester.pumpAndSettle();
    expect(reboots, 1);
  });
}
