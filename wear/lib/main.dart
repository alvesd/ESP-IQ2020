// IQ2020 Spa for Wear OS: a one-screen glance with the key controls (target temperature,
// jets, lights) and the salt zone. The watch connects to the hot tub itself over Wi-Fi with the
// phone app's ESPHome client, so it works without the phone nearby.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iq2020_mobile/api/esphome_client.dart';
import 'package:iq2020_mobile/device_store.dart';
import 'package:iq2020_mobile/main.dart' show Iq2020App, SpaColors;
import 'package:iq2020_mobile/ui/heating_eta.dart';
import 'package:iq2020_mobile/ui/salt_shaker_icon.dart';
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
  late final EspHomeClient _client = () {
    final remote = widget.device.effectiveRemote;
    return EspHomeClient(
      host: widget.device.host,
      port: widget.device.port,
      encryptionKey: widget.device.encryptionKey.isEmpty ? null : widget.device.encryptionKey,
      remoteUrl: remote.remoteUrl,
      cfAccessClientId: remote.clientId,
      cfAccessClientSecret: remote.clientSecret,
      clientInfo: 'IQ2020 Wear OS',
      onRemoteConfigReceived: (cfg) {
        if (cfg.remoteUrl == widget.device.remoteUrl &&
            cfg.clientId == widget.device.cfAccessClientId &&
            cfg.clientSecret == widget.device.cfAccessClientSecret) {
          return;
        }
        unawaited(widget.store.upsert(widget.device.copyWith(
          remoteUrl: cfg.remoteUrl,
          cfAccessClientId: cfg.clientId,
          cfAccessClientSecret: cfg.clientSecret,
        )));
      },
    );
  }();
  double? _pendingTarget;
  Timer? _debounce;
  Timer? _etaTick;
  final Set<int> _busy = {};
  final HeatingEtaTracker _eta = HeatingEtaTracker();

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
    _etaTick?.cancel();
    _client.dispose();
    super.dispose();
  }

  void _syncEtaTimer(bool active) {
    if (!active) {
      _etaTick?.cancel();
      _etaTick = null;
      return;
    }
    if (_etaTick?.isActive ?? false) return;
    _etaTick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
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

  void _setTargetImmediate(SpaSnapshot snap, double value, {required bool isHeatUp}) {
    _debounce?.cancel();
    setState(() => _pendingTarget = value);
    if (isHeatUp) {
      _eta.start(currentTemp: snap.current ?? double.nan, targetTemp: value, now: DateTime.now());
    } else {
      _eta.reset();
    }
    _run(() => applyWatchCommand(_client, snap, {'op': 'setTarget', 'value': value}));
    Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _pendingTarget = null);
    });
  }

  void _nudge(SpaSnapshot snap, int steps) {
    final base = _pendingTarget ?? snap.target ?? snap.current ?? snap.min;
    final next = (((base + steps * snap.step) / snap.step).round() * snap.step).clamp(snap.min, snap.max).toDouble();
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
            final snap = SpaSnapshot.fromClient(
              _client,
              name: widget.device.name,
              heatUpTempC: widget.device.heatUpTempC,
              vacationTempC: widget.device.vacationTempC,
            );
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
    final tol = snap.unit == '°F' ? 0.45 : 0.2;
    final heatUpActive = target != null && (target - snap.heatUpTemp).abs() < tol;
    final vacationActive = target != null && (target - snap.vacationTemp).abs() < tol;
    final current = snap.current ?? double.nan;
    final now = DateTime.now();
    final isFahrenheit = snap.unit == '°F';
    _eta.update(
      currentTemp: current,
      targetTemp: snap.heatUpTemp,
      active: heatUpActive && !current.isNaN && current < snap.heatUpTemp - 0.05,
      isFahrenheit: isFahrenheit,
      now: now,
    );
    final eta = heatUpActive
        ? _eta.estimate(currentTemp: current, targetTemp: snap.heatUpTemp, isFahrenheit: isFahrenheit, now: now)
        : null;
    final heatUpReached = heatUpActive && (eta?.reached ?? false);
    final serverEtaSec = (_pendingTarget == null && heatUpActive && !heatUpReached) ? snap.readyEtaSeconds : null;
    final useServerEta = serverEtaSec != null && serverEtaSec > 0;
    final readyAt = useServerEta ? now.add(Duration(seconds: serverEtaSec)) : eta?.readyAt;
    final etaCalibrated = useServerEta ? snap.readyEtaCalibrated : (eta?.calibrated ?? false);
    _syncEtaTimer(heatUpActive && !heatUpReached && !current.isNaN);

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
              const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
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

    final etaTimeText = readyAt == null
        ? '${fmt(snap.heatUpTemp)}${snap.unit}'
        : MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(readyAt));

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
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: _WearPresetChip(
              icon: heatUpReached ? Icons.check_circle : Icons.local_fire_department,
              title: heatUpReached
                  ? 'Ready'
                  : (heatUpActive ? (etaCalibrated ? 'Ready by' : 'Est. Ready') : 'Heat Up'),
              subtitle: heatUpReached ? 'At ${fmt(snap.heatUpTemp)}${snap.unit}' : etaTimeText,
              accent: heatUpReached ? const Color(0xFF30A46C) : const Color(0xFFFF8A4C),
              active: heatUpActive,
              onTap: canControl ? () => _setTargetImmediate(snap, snap.heatUpTemp, isHeatUp: true) : null,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _WearPresetChip(
              icon: Icons.flight_takeoff,
              title: 'Vacation',
              subtitle: vacationActive ? 'On · ${fmt(snap.vacationTemp)}${snap.unit}' : '${fmt(snap.vacationTemp)}${snap.unit}',
              accent: SpaColors.aqua,
              active: vacationActive,
              onTap: canControl ? () => _setTargetImmediate(snap, snap.vacationTemp, isHeatUp: false) : null,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        for (final t in snap.toggles)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ToggleChip(
              toggle: t,
              busy: _busy.contains(t.key),
              onTap: snap.online ? () => _toggle(snap, t) : null,
            ),
          ),
        if (snap.salt != null || snap.saltPower != null || snap.saltBoost) _SaltRow(snap: snap),
        if (snap.tempHistory.isNotEmpty)
          _WatchMicrochart(
            title: '14d Water',
            values: snap.tempHistory,
            accent: const Color(0xFFFF8A4C),
            unit: snap.unit,
            decimals: snap.step < 1 ? 1 : 0,
          ),
        if (snap.saltHistory.isNotEmpty)
          _WatchMicrochart(
            title: '14d Salt',
            values: snap.saltHistory,
            accent: (snap.salt == null ? null : ui.saltZone(snap.salt!)?.$2) ?? SpaColors.aqua,
          ),
        if (snap.dailyEnergyHistory.isNotEmpty)
          _WatchMicrochart(
            title: '${snap.dailyEnergyHistory.length}d Energy',
            values: snap.dailyEnergyHistory,
            accent: SpaColors.aqua,
            unit: ' kWh',
            decimals: 1,
            bars: true,
            showTotal: true,
          ),
        if (snap.monthlyEnergyHistory.isNotEmpty)
          _WatchMicrochart(
            title: snap.monthlyEnergyHistory.length > 12
                ? '2yr Energy'
                : '${snap.monthlyEnergyHistory.length}mo Energy',
            values: snap.monthlyEnergyHistory,
            accent: SpaColors.aqua,
            unit: ' kWh',
            decimals: 0,
            bars: true,
            showTotal: true,
          ),
      ],
    );
  }
}

class _WatchMicrochart extends StatelessWidget {
  final String title;
  final List<double> values;
  final Color accent;
  final String unit;
  final int decimals;
  final bool bars;
  final bool showTotal;
  const _WatchMicrochart({
    required this.title,
    required this.values,
    required this.accent,
    this.unit = '',
    this.decimals = 0,
    this.bars = false,
    this.showTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final sumV = values.fold<double>(0.0, (a, b) => a + b);
    String fmt(double v) => '${decimals == 0 ? v.round() : v.toStringAsFixed(decimals)}$unit';
    final badge = showTotal ? fmt(sumV) : '${fmt(minV)}–${fmt(maxV)}';
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 6),
      decoration: BoxDecoration(
        color: SpaColors.glass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SpaColors.glassBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          Text(badge,
              style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
        ]),
        const SizedBox(height: 4),
        SizedBox(
          height: 28,
          child: CustomPaint(painter: _WearSparkPainter(values: values, accent: accent, bars: bars)),
        ),
      ]),
    );
  }
}

class _WearSparkPainter extends CustomPainter {
  final List<double> values;
  final Color accent;
  final bool bars;
  const _WearSparkPainter({required this.values, required this.accent, this.bars = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;
    var minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    if (bars && minV > 0) minV = 0;
    var rng = maxV - minV;
    if (rng < 1e-6) {
      rng = 1.0;
      if (!bars) minV -= 0.5;
    }
    const pad = 2.0;
    final h = math.max(1.0, size.height - pad * 2);
    if (bars) {
      final n = values.length;
      final sw = size.width / math.max(1, n);
      final bw = math.max(1.5, sw * 0.64);
      final paint = Paint()..style = PaintingStyle.fill;
      for (var i = 0; i < n; i++) {
        final frac = ((values[i] - minV) / rng).clamp(0.06, 1.0);
        final bh = frac * h;
        final x = i * sw + (sw - bw) / 2;
        paint.color = i == n - 1 ? accent : accent.withValues(alpha: 0.55);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, pad + (h - bh), bw, bh), const Radius.circular(1.5)),
          paint,
        );
      }
      return;
    }
    double xAt(int i) => values.length <= 1 ? size.width / 2 : (i / (values.length - 1)) * size.width;
    double yAt(double v) => pad + (1.0 - ((v - minV) / rng).clamp(0.0, 1.0)) * h;
    if (values.length == 1) {
      canvas.drawCircle(Offset(xAt(0), yAt(values.first)), 3, Paint()..color = accent);
      return;
    }
    final path = Path()..moveTo(xAt(0), yAt(values[0]));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(xAt(i), yAt(values[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(Offset(xAt(values.length - 1), yAt(values.last)), 2.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_WearSparkPainter old) => old.values != values || old.accent != accent || old.bars != bars;
}

class _WearPresetChip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final bool active;
  final VoidCallback? onTap;
  const _WearPresetChip({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: active ? accent.withValues(alpha: 0.24) : SpaColors.glass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: active ? accent : SpaColors.glassBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            Icon(icon, size: 15, color: active ? accent : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, color: active ? accent : theme.colorScheme.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
      ),
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
              const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
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
  final SpaSnapshot snap;
  const _SaltRow({required this.snap});

  @override
  Widget build(BuildContext context) {
    final salt = snap.salt;
    final zone = salt == null ? null : ui.saltZone(salt);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (salt != null || snap.saltPower != null)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (salt != null) ...[
                SaltShakerIcon(size: 14, color: zone?.$2 ?? theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Text('Salt ${salt.toStringAsFixed(0)}', style: theme.textTheme.labelMedium),
                if (zone != null) ...[
                  const SizedBox(width: 4),
                  Text(zone.$1, style: theme.textTheme.labelMedium?.copyWith(color: zone.$2, fontWeight: FontWeight.w600)),
                ],
              ],
              if (salt != null && snap.saltPower != null)
                Text('  ·  ', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
              if (snap.saltPower != null)
                Text('Pwr ${snap.saltPower}',
                    style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        if (snap.saltBoost) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF38D9F5).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF7CEBFF).withValues(alpha: 0.7)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bolt, size: 12, color: Color(0xFFD8F8FF)),
              SizedBox(width: 2),
              Text('Boost On', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFD8F8FF))),
            ]),
          ),
        ],
      ]),
    );
  }
}
