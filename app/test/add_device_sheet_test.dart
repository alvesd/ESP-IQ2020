import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iq2020_mobile/device_store.dart';
import 'package:iq2020_mobile/ui/add_device_sheet.dart';

void main() {
  testWidgets('AddDeviceSheet hides CF token fields when not used and shows them when present', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AddDeviceSheet(
            key: ValueKey('no-cf'),
            existing: SavedDevice(
              id: 'hotspring',
              name: 'Hot Tub',
              host: '192.0.2.55',
              port: 6053,
              encryptionKey: 'dGVzdGtleXRlc3RrZXl0ZXN0a2V5dGVzdGtleXRlc3Q=',
              remoteUrl: 'https://spa.example.com',
            ),
          ),
        ),
      ),
    );
    expect(find.text('CF-Access-Client-Id'), findsNothing);
    expect(find.text('CF-Access-Client-Secret'), findsNothing);
    expect(find.text('Add Cloudflare Access token'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AddDeviceSheet(
            key: ValueKey('with-cf'),
            existing: SavedDevice(
              id: 'hotspring',
              name: 'Hot Tub',
              host: '192.0.2.55',
              port: 6053,
              encryptionKey: 'dGVzdGtleXRlc3RrZXl0ZXN0a2V5dGVzdGtleXRlc3Q=',
              remoteUrl: 'https://spa.example.com',
              cfAccessClientId: 'id-123',
              cfAccessClientSecret: 'sec-456',
            ),
          ),
        ),
      ),
    );
    expect(find.text('CF-Access-Client-Id'), findsOneWidget);
    expect(find.text('CF-Access-Client-Secret'), findsOneWidget);
    expect(find.text('Remove token'), findsOneWidget);
  });
}
