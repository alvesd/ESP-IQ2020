// "Set up watch": scans the QR code a Wear OS watch shows and sends it this saved hot tub
// (host and API key) over Wi-Fi, encrypted for that watch (lib/watch/watch_pairing.dart).
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../device_store.dart';
import '../watch/watch_pairing.dart';

class WatchSetupScreen extends StatefulWidget {
  final SavedDevice device;
  const WatchSetupScreen({super.key, required this.device});
  @override
  State<WatchSetupScreen> createState() => _WatchSetupScreenState();
}

class _WatchSetupScreenState extends State<WatchSetupScreen> {
  final _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _sending = false;
  String? _message;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_sending) return;
    final code = capture.barcodes.map((b) => PairingCode.tryParse(b.rawValue ?? '')).nonNulls.firstOrNull;
    if (code == null) {
      setState(() => _message = 'That isn\'t an IQ2020 watch code. On the watch, tap "Set up from phone".');
      return;
    }
    setState(() {
      _sending = true;
      _message = 'Sending ${widget.device.name} to the watch…';
    });
    try {
      await sendToWatch(code, widget.device);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Watch set up for ${widget.device.name}')));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _message = 'Couldn\'t reach the watch ($e). Phone and watch must be on the same Wi-Fi.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Set up watch')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Text(
            'On your Wear OS watch, open IQ2020 Spa and tap "Set up from phone", then point the camera at the code.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: MobileScanner(controller: _scanner, onDetect: _onDetect),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            if (_sending) const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            if (_sending) const SizedBox(width: 10),
            Expanded(child: Text(_message ?? '', style: theme.textTheme.bodySmall)),
          ]),
        ),
      ]),
    );
  }
}
