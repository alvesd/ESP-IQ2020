// Spa control screen. Everything is generated from the entity list the device reports, so it
// adapts to 1-3 jets, Celsius/Fahrenheit, Coolzone, salt systems, audio, lights modules, etc.
import 'dart:async';

import 'package:flutter/material.dart';

import '../api/esphome_client.dart';
import '../api/messages.dart';
import '../device_store.dart';

class SpaScreen extends StatefulWidget {
  final SavedDevice device;
  const SpaScreen({super.key, required this.device});

  @override
  State<SpaScreen> createState() => _SpaScreenState();
}

class _SpaScreenState extends State<SpaScreen> {
  late final EspHomeClient _client;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _client = EspHomeClient(
      host: widget.device.host,
      port: widget.device.port,
      encryptionKey: widget.device.encryptionKey,
    );
    unawaited(_client.connect());
    // iOS/Android kill background sockets anyway; drop cleanly and reconnect on resume.
    _lifecycle = AppLifecycleListener(
      onPause: () => unawaited(_client.disconnect()),
      onResume: () => unawaited(_client.connect()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _client.dispose();
    super.dispose();
  }

  void _run(Future<void> Function() action) {
    action().catchError((Object e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _client,
      builder: (context, _) {
        final c = _client;
        final visible = c.entities.values.where((e) => !e.disabledByDefault);
        List<EntityInfo> kind(EntityKind k, {bool main = true}) => visible
            .where((e) => e.kind == k && ((e.category == EntityCategory.none) == main))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

        final climates = kind(EntityKind.climate);
        final fans = kind(EntityKind.fan);
        final switches = kind(EntityKind.switch_);
        final selects = kind(EntityKind.select);
        final numbers = kind(EntityKind.number);
        final sensors = kind(EntityKind.sensor);
        final status = [...kind(EntityKind.binarySensor), ...kind(EntityKind.textSensor)];
        final buttons = kind(EntityKind.button);
        final config = [
          for (final k in EntityKind.values) ...kind(k, main: false),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Text(c.deviceInfo?.displayName ?? widget.device.name),
            actions: [_StatusChip(client: c), const SizedBox(width: 8)],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await _client.disconnect();
              await _client.connect();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (c.status != ConnectionStatus.connected) _ConnectionBanner(client: c),
                for (final e in climates) _ClimateCard(client: c, info: e, run: _run),
                if (fans.isNotEmpty) ...[
                  const _Section('Jets'),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [for (final e in fans) _FanTile(client: c, info: e, run: _run)],
                  ),
                ],
                if (switches.isNotEmpty || selects.isNotEmpty || numbers.isNotEmpty) ...[
                  const _Section('Controls'),
                  Card(
                    child: Column(children: [
                      for (final e in switches) _SwitchRow(client: c, info: e, run: _run),
                      for (final e in selects) _SelectRow(client: c, info: e, run: _run),
                      for (final e in numbers) _NumberRow(client: c, info: e, run: _run),
                    ]),
                  ),
                ],
                if (sensors.isNotEmpty) ...[
                  const _Section('Readings'),
                  _SensorGrid(client: c, sensors: sensors),
                ],
                if (status.isNotEmpty || buttons.isNotEmpty) ...[
                  const _Section('Status'),
                  Card(
                    child: Column(children: [
                      for (final e in status) _StatusRow(client: c, info: e),
                      for (final e in buttons) _ButtonRow(client: c, info: e, run: _run),
                    ]),
                  ),
                ],
                if (config.isNotEmpty || c.deviceInfo != null)
                  Card(
                    margin: const EdgeInsets.only(top: 16),
                    child: ExpansionTile(
                      title: const Text('Device & diagnostics'),
                      children: [
                        for (final e in config) _GenericRow(client: c, info: e, run: _run),
                        if (c.deviceInfo != null) ...[
                          ListTile(dense: true, title: const Text('ESPHome'), trailing: Text(c.deviceInfo!.esphomeVersion)),
                          ListTile(dense: true, title: const Text('MAC'), trailing: Text(c.deviceInfo!.macAddress)),
                          if (c.deviceInfo!.projectVersion.isNotEmpty)
                            ListTile(
                                dense: true,
                                title: const Text('Firmware'),
                                trailing: Text('${c.deviceInfo!.projectName} ${c.deviceInfo!.projectVersion}')),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

typedef _Runner = void Function(Future<void> Function() action);

String _fmt(double v, int decimals) => v.isNaN ? '—' : v.toStringAsFixed(decimals.clamp(0, 3));

IconData _iconFor(EntityInfo e) {
  final id = '${e.objectId} ${e.icon}';
  if (id.contains('light')) return Icons.lightbulb;
  if (id.contains('lock')) return Icons.lock;
  if (id.contains('clean') || id.contains('vacuum')) return Icons.cleaning_services;
  if (id.contains('summer') || id.contains('sun')) return Icons.wb_sunny;
  if (id.contains('jet') || id.contains('turbine')) return Icons.air;
  if (id.contains('audio') || id.contains('volume') || id.contains('music')) return Icons.music_note;
  if (id.contains('salt')) return Icons.water_drop;
  if (id.contains('power') || e.unit == 'W' || e.unit == 'A' || e.unit == 'V') return Icons.bolt;
  if (id.contains('temp')) return Icons.thermostat;
  if (id.contains('wifi')) return Icons.wifi;
  return Icons.tune;
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _StatusChip extends StatelessWidget {
  final EspHomeClient client;
  const _StatusChip({required this.client});
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (client.status) {
      ConnectionStatus.connected => ('Online', Colors.green),
      ConnectionStatus.connecting => ('Connecting', Colors.orange),
      ConnectionStatus.failed => ('Offline', Colors.red),
      ConnectionStatus.disconnected => ('Offline', Colors.grey),
    };
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 5),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  final EspHomeClient client;
  const _ConnectionBanner({required this.client});
  @override
  Widget build(BuildContext context) {
    final connecting = client.status == ConnectionStatus.connecting;
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: ListTile(
        leading: connecting
            ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.wifi_off),
        title: Text(connecting ? 'Connecting to ${client.host}…' : 'Not connected'),
        subtitle: client.lastError == null ? null : Text(client.lastError!),
        trailing: connecting ? null : TextButton(onPressed: client.connect, child: const Text('Retry')),
      ),
    );
  }
}

class _ClimateCard extends StatefulWidget {
  final EspHomeClient client;
  final EntityInfo info;
  final _Runner run;
  const _ClimateCard({required this.client, required this.info, required this.run});
  @override
  State<_ClimateCard> createState() => _ClimateCardState();
}

class _ClimateCardState extends State<_ClimateCard> {
  double? _pendingTarget;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _nudge(double current, int direction) {
    final info = widget.info;
    final next = ((_pendingTarget ?? current) + direction * info.step)
        .clamp(info.minValue, info.maxValue == 0 ? 200.0 : info.maxValue)
        .toDouble();
    setState(() => _pendingTarget = next);
    // The spa remote also debounces; send one command after the user stops tapping.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      widget.run(() => widget.client.setClimate(info.key, target: next));
      Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _pendingTarget = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final s = widget.client.states[info.key];
    final theme = Theme.of(context);
    final current = s?.currentTemperature ?? double.nan;
    final target = _pendingTarget ?? s?.targetTemperature ?? double.nan;
    final decimals = info.step < 1 ? 1 : 0;
    final action = switch (s?.climateAction) {
      ClimateAction.heating => ('Heating', Icons.local_fire_department, Colors.deepOrange),
      ClimateAction.cooling => ('Cooling', Icons.ac_unit, Colors.lightBlue),
      ClimateAction.idle => ('Idle', Icons.pause_circle_outline, theme.colorScheme.outline),
      _ => ('Off', Icons.power_settings_new, theme.colorScheme.outline),
    };
    final modes = info.climateModes;
    final presets = info.climatePresets.where((p) => p == ClimatePreset.boost || p == ClimatePreset.eco).toList();
    final enabled = widget.client.status == ConnectionStatus.connected && !target.isNaN;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Row(children: [
            Icon(action.$2, color: action.$3),
            const SizedBox(width: 6),
            Text(action.$1, style: theme.textTheme.labelLarge?.copyWith(color: action.$3)),
            const Spacer(),
            Text(info.name, style: theme.textTheme.labelLarge),
          ]),
          const SizedBox(height: 8),
          Text('${_fmt(current, decimals)}°', style: theme.textTheme.displayLarge),
          Text('Water temperature', style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton.filledTonal(
              iconSize: 32,
              onPressed: enabled ? () => _nudge(target, -1) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 140,
              child: Column(children: [
                Text('${_fmt(target, decimals)}°', style: theme.textTheme.headlineMedium),
                Text(_pendingTarget == null ? 'Target' : 'Setting…', style: theme.textTheme.bodySmall),
              ]),
            ),
            IconButton.filledTonal(
              iconSize: 32,
              onPressed: enabled ? () => _nudge(target, 1) : null,
              icon: const Icon(Icons.add),
            ),
          ]),
          if (modes.length > 1) ...[
            const SizedBox(height: 16),
            SegmentedButton<int>(
              segments: [
                for (final m in modes)
                  ButtonSegment(value: m, label: Text(switch (m) {
                    ClimateMode.heat => 'Heat',
                    ClimateMode.cool => 'Chill',
                    ClimateMode.auto => 'Auto',
                    ClimateMode.off => 'Off',
                    _ => 'Mode $m',
                  })),
              ],
              selected: {if (s != null && modes.contains(s.climateMode)) s.climateMode},
              emptySelectionAllowed: true,
              onSelectionChanged: (v) => widget.run(() => widget.client.setClimate(info.key, mode: v.first)),
            ),
          ],
          if (presets.isNotEmpty && s?.climateMode != ClimateMode.cool) ...[
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                for (final p in presets)
                  ButtonSegment(value: p, label: Text(p == ClimatePreset.boost ? 'Boost' : 'Saver')),
              ],
              selected: {if (s != null && presets.contains(s.climatePreset)) s.climatePreset},
              emptySelectionAllowed: true,
              onSelectionChanged: (v) => widget.run(() => widget.client.setClimate(info.key, preset: v.first)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _FanTile extends StatelessWidget {
  final EspHomeClient client;
  final EntityInfo info;
  final _Runner run;
  const _FanTile({required this.client, required this.info, required this.run});

  @override
  Widget build(BuildContext context) {
    final s = client.states[info.key];
    final on = s?.boolValue ?? false;
    final scheme = Theme.of(context).colorScheme;
    final speeds = info.fanSpeedCount;
    final label = !on
        ? 'Off'
        : speeds <= 1
            ? 'On'
            : (s!.fanSpeedLevel <= 1 ? 'Low' : 'High');

    void tap() {
      // Cycle Off -> Low -> High -> Off for 2-speed jets, toggle for single-speed.
      if (speeds <= 1 || !on) {
        run(() => client.setFan(info.key, on: !on, speedLevel: (!on && speeds > 1) ? 1 : null));
      } else if (s!.fanSpeedLevel < speeds) {
        run(() => client.setFan(info.key, on: true, speedLevel: s.fanSpeedLevel + 1));
      } else {
        run(() => client.setFan(info.key, on: false));
      }
    }

    return SizedBox(
      width: 160,
      child: Card(
        color: on ? scheme.primaryContainer : null,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: client.status == ConnectionStatus.connected ? tap : null,
          onLongPress: on ? () => run(() => client.setFan(info.key, on: false)) : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.air, size: 32, color: on ? scheme.primary : scheme.outline),
              const SizedBox(height: 8),
              Text(info.name, style: Theme.of(context).textTheme.titleMedium),
              Text(label),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final EspHomeClient client;
  final EntityInfo info;
  final _Runner run;
  const _SwitchRow({required this.client, required this.info, required this.run});
  @override
  Widget build(BuildContext context) {
    final s = client.states[info.key];
    return SwitchListTile(
      secondary: Icon(_iconFor(info)),
      title: Text(info.name),
      value: s?.boolValue ?? false,
      onChanged: (s == null || client.status != ConnectionStatus.connected)
          ? null
          : (v) => run(() => client.setSwitch(info.key, v)),
    );
  }
}

class _SelectRow extends StatelessWidget {
  final EspHomeClient client;
  final EntityInfo info;
  final _Runner run;
  const _SelectRow({required this.client, required this.info, required this.run});
  @override
  Widget build(BuildContext context) {
    final s = client.states[info.key];
    final current = (s != null && info.options.contains(s.text)) ? s.text : null;
    return ListTile(
      leading: Icon(_iconFor(info)),
      title: Text(info.name),
      trailing: DropdownButton<String>(
        value: current,
        hint: const Text('—'),
        items: [for (final o in info.options) DropdownMenuItem(value: o, child: Text(o))],
        onChanged: client.status != ConnectionStatus.connected
            ? null
            : (v) {
                if (v != null) run(() => client.setSelect(info.key, v));
              },
      ),
    );
  }
}

class _NumberRow extends StatefulWidget {
  final EspHomeClient client;
  final EntityInfo info;
  final _Runner run;
  const _NumberRow({required this.client, required this.info, required this.run});
  @override
  State<_NumberRow> createState() => _NumberRowState();
}

class _NumberRowState extends State<_NumberRow> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final s = widget.client.states[info.key];
    final min = info.minValue;
    final max = info.maxValue <= min ? min + 1 : info.maxValue;
    final raw = _drag ?? s?.number ?? min;
    final value = (raw.isNaN ? min : raw).clamp(min, max).toDouble();
    final divisions = ((max - min) / info.step).round();
    return ListTile(
      leading: Icon(_iconFor(info)),
      title: Text(info.name),
      subtitle: Slider(
        min: min,
        max: max,
        divisions: divisions > 0 && divisions <= 200 ? divisions : null,
        value: value,
        label: _fmt(value, info.step < 1 ? 1 : 0),
        onChanged: widget.client.status == ConnectionStatus.connected ? (v) => setState(() => _drag = v) : null,
        onChangeEnd: (v) {
          setState(() => _drag = null);
          widget.run(() => widget.client.setNumber(info.key, v));
        },
      ),
      trailing: Text('${_fmt(value, info.step < 1 ? 1 : 0)}${info.unit}'),
    );
  }
}

class _SensorGrid extends StatelessWidget {
  final EspHomeClient client;
  final List<EntityInfo> sensors;
  const _SensorGrid({required this.client, required this.sensors});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth > 600 ? 4 : 2;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final e in sensors)
          SizedBox(
            width: width,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(_iconFor(e), size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(e.name, style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    '${_fmt(client.states[e.key]?.number ?? double.nan, e.accuracyDecimals)} ${e.unit}',
                    style: theme.textTheme.titleLarge,
                  ),
                ]),
              ),
            ),
          ),
      ]);
    });
  }
}

class _StatusRow extends StatelessWidget {
  final EspHomeClient client;
  final EntityInfo info;
  const _StatusRow({required this.client, required this.info});
  @override
  Widget build(BuildContext context) {
    final s = client.states[info.key];
    final value = s == null || s.missing
        ? '—'
        : info.kind == EntityKind.binarySensor
            ? (s.boolValue ? 'Yes' : 'No')
            : s.text;
    return ListTile(dense: true, leading: Icon(_iconFor(info)), title: Text(info.name), trailing: Text(value));
  }
}

class _ButtonRow extends StatelessWidget {
  final EspHomeClient client;
  final EntityInfo info;
  final _Runner run;
  const _ButtonRow({required this.client, required this.info, required this.run});
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(_iconFor(info)),
        title: Text(info.name),
        trailing: OutlinedButton(
          onPressed: client.status != ConnectionStatus.connected
              ? null
              : () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: Text('${info.name}?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Confirm')),
                      ],
                    ),
                  );
                  if (ok == true) run(() => client.pressButton(info.key));
                },
          child: const Text('Run'),
        ),
      );
}

/// Config/diagnostic entities of any kind, shown compactly.
class _GenericRow extends StatelessWidget {
  final EspHomeClient client;
  final EntityInfo info;
  final _Runner run;
  const _GenericRow({required this.client, required this.info, required this.run});
  @override
  Widget build(BuildContext context) => switch (info.kind) {
        EntityKind.switch_ => _SwitchRow(client: client, info: info, run: run),
        EntityKind.select => _SelectRow(client: client, info: info, run: run),
        EntityKind.number => _NumberRow(client: client, info: info, run: run),
        EntityKind.button => _ButtonRow(client: client, info: info, run: run),
        EntityKind.sensor => ListTile(
            dense: true,
            leading: Icon(_iconFor(info)),
            title: Text(info.name),
            trailing: Text('${_fmt(client.states[info.key]?.number ?? double.nan, info.accuracyDecimals)} ${info.unit}'),
          ),
        _ => _StatusRow(client: client, info: info),
      };
}
