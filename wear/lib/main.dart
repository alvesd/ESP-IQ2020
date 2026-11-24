// IQ2020 Spa for Wear OS: a one-screen glance with the key controls (target temperature,
// jets, lights) and the salt zone. The watch connects to the hot tub itself over Wi-Fi with the
// phone app's ESPHome client, so it works without the phone nearby.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iq2020_mobile/api/esphome_client.dart';
import 'package:iq2020_mobile/device_store.dart';
import 'package:iq2020_mobile/main.dart' show Iq2020App, SpaColors;
import 'package:iq2020_mobile/ui/spa_screen.dart' as ui show saltZone;
import 'package:iq2020_mobile/watch/spa_snapshot.dart';
import 'package:iq2020_mobile/watch/watch_pairing.dart';
import 'package:qr_flutter/qr_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = DeviceStore();
  await store.load();
  runApp(WearApp(store: store));
}

class WearApp extends StatelessWidget {
  final DeviceStore store;
  const WearApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'IQ2020 Spa',
        debugShowCheckedModeBanner: false,
        theme: Iq2020App.theme().copyWith(scaffoldBackgroundColor: Colors.black),
        home: ListenableBuilder(
          listenable: store,
          builder: (context, _) => store.devices.isEmpty
              ? SetupScreen(store: store)
              : WearSpaScreen(key: ValueKey(store.devices.first.id), store: store, device: store.devices.first),
        ),
      );
}

/// Round watch faces clip the corners; keep content inside the inscribed square-ish area.
EdgeInsets _roundInsets(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  return EdgeInsets.symmetric(horizontal: s.width * 0.11, vertical: s.height * 0.12);
}

/// First run. Easiest: "Set up from phone" shows a QR code that the phone app scans and answers
/// with the saved hot tub over Wi-Fi (lib/watch/watch_pairing.dart). Manual host + key below.
class SetupScreen extends StatefulWidget {
  final DeviceStore store;
  const SetupScreen({super.key, required this.store});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _host = TextEditingController(text: 'hotspring.local');
  final _key = TextEditingController();

  @override
  void dispose() {
    _host.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    final id = host.split('.').first;
    await widget.store.upsert(SavedDevice(id: id, name: id, host: host, encryptionKey: _key.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: ListView(
        padding: _roundInsets(context),
        children: [
          Text('Add hot tub', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => PairFromPhoneScreen(store: widget.store)),
            ),
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Set up from phone'),
          ),
          const SizedBox(height: 8),
          Text('Or enter it here', textAlign: TextAlign.center, style: theme.textTheme.labelSmall),
          TextField(controller: _host, decoration: const InputDecoration(labelText: 'Host'), keyboardType: TextInputType.url),
          TextField(controller: _key, decoration: const InputDecoration(labelText: 'API key'), obscureText: true),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}

/// Shows a one-time QR code; the phone app scans it and sends the saved hot tub.
class PairFromPhoneScreen extends StatefulWidget {
  final DeviceStore store;
  const PairFromPhoneScreen({super.key, required this.store});
  @override
  State<PairFromPhoneScreen> createState() => _PairFromPhoneScreenState();
}

class _PairFromPhoneScreenState extends State<PairFromPhoneScreen> {
  PairingListener? _listener;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final l = await PairingListener.start();
      if (!mounted) return await l.close();
      setState(() => _listener = l);
      final device = await l.received;
      await widget.store.upsert(device);
      if (mounted) Navigator.of(context).pop();
    } on TimeoutException {
      if (mounted) setState(() => _error = 'Code expired');
    } on SocketException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _listener?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context).shortestSide;
    final l = _listener;
    return Scaffold(
      body: Center(
        child: _error != null
            ? Padding(
                padding: _roundInsets(context),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                  TextButton(onPressed: _start, child: const Text('Try again')),
                ]),
              )
            : l == null
                ? const CircularProgressIndicator()
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    // White quiet zone so phone cameras read it off a dark watch face.
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(6),
                      child: QrImageView(data: l.code.encode(), size: size * 0.56, padding: EdgeInsets.zero),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: size * 0.7,
                      child: Text('Phone app: ⋯ › Set up watch',
                          textAlign: TextAlign.center, style: theme.textTheme.labelSmall),
                    ),
                  ]),
      ),
    );
  }
}

class WearSpaScreen extends StatefulWidget {
  final DeviceStore store;
  final SavedDevice device;
  const WearSpaScreen({super.key, required this.store, required this.device});
  @override
  State<WearSpaScreen> createState() => _WearSpaScreenState();
}

class _WearSpaScreenState extends State<WearSpaScreen> with WidgetsBindingObserver {
  late final EspHomeClient _client = EspHomeClient(
    host: widget.device.host,
    port: widget.device.port,
    encryptionKey: widget.device.encryptionKey.isEmpty ? null : widget.device.encryptionKey,
    clientInfo: 'IQ2020 Wear OS',
  );
  double? _pendingTarget;
  Timer? _debounce;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _client.connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _client.dispose();
    super.dispose();
  }

  // The ESP32 allows only a few API connections: free ours whenever the watch screen is off.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _client.connect();
    } else if (state == AppLifecycleState.paused) {
      _client.disconnect();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _nudge(SpaSnapshot snap, int steps) {
    final base = SpaSnapshot.fromMap({...snap.toMap(), 'target': _pendingTarget ?? snap.target});
    final next = base.nudged(steps);
    setState(() => _pendingTarget = next);
    // Like the phone and the spa remote: one command after the taps stop.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      _run(() => applyWatchCommand(_client, snap, {'op': 'setTarget', 'value': next}));
      Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _pendingTarget = null);
      });
    });
  }

  Future<void> _toggle(SpaSnapshot snap, WatchToggle t) async {
    setState(() => _busy.add(t.key));
    await _run(() => applyWatchCommand(_client, snap, {'op': 'toggle', 'key': t.key, 'kind': t.kind, 'on': !t.on}));
    if (mounted) setState(() => _busy.remove(t.key));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListenableBuilder(
          listenable: _client,
          builder: (context, _) {
            final snap = SpaSnapshot.fromClient(_client, name: widget.device.name);
            return _body(context, snap);
          },
        ),
      );

  Widget _body(BuildContext context, SpaSnapshot snap) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    String fmt(double? v) => v == null ? '—' : v.toStringAsFixed(snap.step < 1 ? 1 : 0);
    final target = _pendingTarget ?? snap.target;
    final canControl = snap.online && snap.climateKey != null && target != null;
    final (heaterLabel, heaterColor) = switch (snap.heater) {
      'heating' => ('Heating', const Color(0xFFFF8A4C)),
      'cooling' => ('Cooling', const Color(0xFF4FC3F7)),
      'idle' => ('Holding', SpaColors.aqua),
      _ => ('Heater off', muted),
    };

    if (!snap.online && snap.current == null) {
      return Center(
        child: Padding(
          padding: _roundInsets(context),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_client.status == ConnectionStatus.failed) ...[
              Icon(Icons.cloud_off, color: muted),
              const SizedBox(height: 6),
              Text(_client.lastError ?? 'Offline', textAlign: TextAlign.center, maxLines: 3, style: theme.textTheme.bodySmall),
              TextButton(onPressed: () => widget.store.remove(widget.device.id), child: const Text('Change hot tub')),
            ] else ...[
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 8),
              Text('Connecting to ${snap.name}…', textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            ],
          ]),
        ),
      );
    }

    Widget roundButton(IconData icon, VoidCallback? onPressed) => IconButton.filledTonal(
          onPressed: onPressed,
          icon: Icon(icon),
          iconSize: 22,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
        );

    return ListView(
      padding: _roundInsets(context),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.circle, size: 8, color: snap.online ? const Color(0xFF4CAF50) : muted),
          const SizedBox(width: 6),
          Flexible(child: Text(snap.name, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium?.copyWith(color: muted))),
        ]),
        Text('${fmt(snap.current)}${snap.unit}',
            textAlign: TextAlign.center, style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w300)),
        Text(heaterLabel, textAlign: TextAlign.center, style: theme.textTheme.labelMedium?.copyWith(color: heaterColor)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          roundButton(Icons.remove, canControl ? () => _nudge(snap, -1) : null),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${fmt(target)}${snap.unit}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            Text(_pendingTarget != null ? 'Setting…' : 'Set to', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
          ]),
          roundButton(Icons.add, canControl ? () => _nudge(snap, 1) : null),
        ]),
        const SizedBox(height: 10),
        for (final t in snap.toggles)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ToggleChip(
              toggle: t,
              busy: _busy.contains(t.key),
              onTap: snap.online ? () => _toggle(snap, t) : null,
            ),
          ),
        if (snap.salt != null) _SaltRow(salt: snap.salt!),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final WatchToggle toggle;
  final bool busy;
  final VoidCallback? onTap;
  const _ToggleChip({required this.toggle, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = toggle.kind == 'fan' ? SpaColors.aqua : SpaColors.amber;
    final icon = toggle.kind == 'fan' ? Icons.air : Icons.lightbulb_outline;
    return Material(
      color: toggle.on ? accent.withValues(alpha: 0.22) : SpaColors.glass,
      shape: StadiumBorder(side: BorderSide(color: toggle.on ? accent : SpaColors.glassBorder)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Icon(icon, size: 18, color: toggle.on ? accent : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(toggle.name, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge)),
            if (busy)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Text(toggle.on ? 'On' : 'Off',
                  style: theme.textTheme.labelMedium?.copyWith(color: toggle.on ? accent : theme.colorScheme.outline)),
          ]),
        ),
      ),
    );
  }
}

class _SaltRow extends StatelessWidget {
  final double salt;
  const _SaltRow({required this.salt});

  @override
  Widget build(BuildContext context) {
    final zone = ui.saltZone(salt);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.water_drop, size: 16, color: zone?.$2),
        const SizedBox(width: 6),
        Text('Salt ${salt.toStringAsFixed(0)}', style: theme.textTheme.labelLarge),
        if (zone != null) ...[
          const SizedBox(width: 6),
          Text(zone.$1, style: theme.textTheme.labelLarge?.copyWith(color: zone.$2, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }
}
