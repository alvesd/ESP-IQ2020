// Spa control screen. Everything is generated from the entity list the device reports, so it
// adapts to 1-3 jets, Celsius/Fahrenheit, Coolzone, salt systems, audio, lights modules, etc.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../api/esphome_client.dart';
import '../api/messages.dart';
import '../device_store.dart';
import 'heating_eta.dart';
import 'logo_light_badge.dart';
import 'native_tabs.dart';
import 'salt_shaker_icon.dart';

class SpaScreen extends StatefulWidget {
  final SavedDevice device;
  final DeviceStore store;
  const SpaScreen({super.key, required this.device, required this.store});

  @override
  State<SpaScreen> createState() => _SpaScreenState();
}

class _SpaScreenState extends State<SpaScreen> {
  late final EspHomeClient _client;
  late final AppLifecycleListener _lifecycle;
  Timer? _pauseTimer;

  @override
  void initState() {
    super.initState();
    _client = EspHomeClient(
      host: widget.device.host,
      port: widget.device.port,
      encryptionKey: widget.device.encryptionKey,
    );
    unawaited(_client.connect());
    // iOS/Android kill background sockets anyway; drop cleanly and reconnect on resume. Debounced:
    // moving the Flutter view between native tabs briefly reports paused/resumed, which must not
    // churn the connection (ESPHome resets rapid reconnects).
    _lifecycle = AppLifecycleListener(
      onPause: () {
        _pauseTimer?.cancel();
        _pauseTimer = Timer(const Duration(seconds: 3), () => unawaited(_client.disconnect()));
      },
      onResume: () {
        final wasPending = _pauseTimer?.isActive ?? false;
        _pauseTimer?.cancel();
        if (!wasPending) unawaited(_client.connect());
      },
    );
  }

  @override
  void dispose() {
    _pauseTimer?.cancel();
    unawaited(NativeTabs.hide());
    _lifecycle.dispose();
    _client.dispose();
    super.dispose();
  }

  SavedDevice get _device => widget.store.devices.where((d) => d.id == widget.device.id).firstOrNull ?? widget.device;

  Future<void> _rename() async {
    final currentName = _device.name;
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename hot tub'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    final trimmed = newName?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == currentName) return;
    // Only the app's label changes; the ESPHome device name (and Home Assistant) are untouched.
    await widget.store.upsert(_device.copyWith(name: trimmed));
  }

  Future<void> _updatePresetTemp({double? heatUpTempC, double? vacationTempC}) =>
      widget.store.upsert(_device.copyWith(heatUpTempC: heatUpTempC, vacationTempC: vacationTempC));

  void _run(Future<void> Function() action) {
    action().catchError((Object e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    });
  }

  /// Selected tab, by label so it survives the Salt tab appearing once entities arrive.
  String _tab = 'Comfort';

  /// True once the native iOS tab bar is showing our tabs (iPhone Duo: its system bar), in
  /// which case Flutter draws no navigation of its own.
  bool _nativeTabs = false;

  static const _symbols = {
    'Comfort': 'thermometer.medium',
    'Power': 'bolt.fill',
    'Usage': 'timer',
    'Salt': 'saltshaker', // custom asset in ios/Runner/Assets.xcassets (no SF Symbol exists)
    'Settings': 'gearshape.fill',
  };

  /// Salt uses the custom salt shaker drawing; every other tab a Material icon.
  static Widget _tabIcon(String label, IconData icon) =>
      label == 'Salt' ? const SaltShakerIcon() : Icon(icon);

  void _syncNativeTabs(List<String> labels, String selected) {
    if (!NativeTabs.supported) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final ok = await NativeTabs.show(
        [for (final l in labels) NativeTab(l, l, _symbols[l] ?? 'circle')],
        selected,
        (id) {
          if (mounted && id != _tab) setState(() => _tab = id);
        },
      );
      if (mounted && ok != _nativeTabs) setState(() => _nativeTabs = ok);
    });
  }

  /// Width at which the tabs move from a bottom bar to a rail on the right (e.g. iPhone Duo
  /// unfolded, iPad, landscape). Decided from the space this screen actually has, never from
  /// the device type, so it follows folding, rotation and split-screen resizing live.
  static const double railBreakpoint = 600;

  /// The rail also replaces the bottom bar whenever the system keeps a vertical bar on the
  /// trailing edge (iPhone Duo puts its status bar there). That bar arrives as a right
  /// safe-area inset for the life of the configuration, so navigation sits beside it and
  /// content never goes under it.
  static bool useRail(BoxConstraints constraints, EdgeInsets viewPadding) =>
      constraints.maxWidth >= railBreakpoint || viewPadding.right > 0 && viewPadding.right >= viewPadding.left;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_client, widget.store]),
      builder: (context, _) {
        final c = _client;
        final groups = _EntityGroups(c);
        final tabs = [
          (label: 'Comfort', icon: Icons.hot_tub_outlined, selectedIcon: Icons.hot_tub, page: _comfortPage(c, groups)),
          (
            label: 'Power',
            icon: Icons.bolt_outlined,
            selectedIcon: Icons.bolt,
            page: _sensorPage(c, groups.powerSensors, 'Power', 'No power readings are configured on this spa.'),
          ),
          (
            label: 'Usage',
            icon: Icons.timer_outlined,
            selectedIcon: Icons.timer,
            page: _sensorPage(c, groups.usageSensors, 'Runtime & timers', 'No runtime or timer counters are configured on this spa.'),
          ),
          if (groups.hasSalt)
            (label: 'Salt', icon: Icons.water_drop_outlined, selectedIcon: Icons.water_drop, page: _saltPage(c, groups)),
          (label: 'Settings', icon: Icons.settings_outlined, selectedIcon: Icons.settings, page: _settingsPage(c, groups)),
        ];
        final index = tabs.indexWhere((t) => t.label == _tab).clamp(0, tabs.length - 1);
        _syncNativeTabs([for (final t in tabs) t.label], tabs[index].label);

        return LayoutBuilder(builder: (context, constraints) {
          // Native tab bar when available; otherwise Flutter's own rail (wide) or bottom bar.
          final ownNav = !_nativeTabs;
          final wide = useRail(constraints, MediaQuery.viewPaddingOf(context));
          final body = RefreshIndicator(
            onRefresh: () async {
              await _client.disconnect();
              await _client.connect();
            },
            child: ListView(
              key: PageStorageKey('tab-${tabs[index].label}'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (c.status != ConnectionStatus.connected) _ConnectionBanner(client: c),
                ...tabs[index].page,
              ],
            ),
          );
          void select(int i) => setState(() => _tab = tabs[i].label);

          return Scaffold(
            appBar: AppBar(
              title: Text(_device.name),
              actions: [
                IconButton(tooltip: 'Rename', icon: const Icon(Icons.edit_outlined), onPressed: _rename),
                _StatusChip(client: c),
                const SizedBox(width: 8),
              ],
            ),
            bottomNavigationBar: (!ownNav || wide)
                ? null
                : NavigationBar(
                    selectedIndex: index,
                    onDestinationSelected: select,
                    destinations: [
                      for (final t in tabs)
                        NavigationDestination(icon: _tabIcon(t.label, t.icon), selectedIcon: _tabIcon(t.label, t.selectedIcon), label: t.label),
                    ],
                  ),
            // Side insets apply in every layout: the Duo's system bar and the native tab bar
            // both arrive as trailing safe-area insets that content must not go under.
            body: SafeArea(
              top: false,
              bottom: false,
              child: (ownNav && wide)
                  ? Row(children: [
                      Expanded(child: body),
                      const VerticalDivider(width: 1),
                      // Rail on the trailing edge, next to the Duo's system bar. Scrolls when the
                      // window is short (landscape phone, half-open Duo), so it never overflows;
                      // labels collapse to the selected tab when space is tight.
                      LayoutBuilder(
                        builder: (context, rail) => SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: rail.maxHeight),
                            child: IntrinsicHeight(
                              child: NavigationRail(
                                selectedIndex: index,
                                onDestinationSelected: select,
                                labelType: rail.maxHeight < 80.0 * tabs.length + 40
                                    ? NavigationRailLabelType.selected
                                    : NavigationRailLabelType.all,
                                // Centered vertically: reachable by the thumb holding the device.
                                groupAlignment: 0,
                                destinations: [
                                  for (final t in tabs)
                                    NavigationRailDestination(
                                        icon: _tabIcon(t.label, t.icon), selectedIcon: _tabIcon(t.label, t.selectedIcon), label: Text(t.label)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ])
                  : body,
            ),
          );
        });
      },
    );
  }

  List<Widget> _comfortPage(EspHomeClient c, _EntityGroups g) => [
        for (final e in g.climates)
          _ClimateCard(
            client: c,
            info: e,
            run: _run,
            logoLight: g.logoLight,
            saltLevel: g.saltLevelSensor,
            saltPower: g.saltPowerNumber,
            saltBoost: g.saltBoostSwitch,
            onTapSalt: g.hasSalt ? () => setState(() => _tab = 'Salt') : null,
            heatUpTempC: _device.heatUpTempC,
            vacationTempC: _device.vacationTempC,
          ),
        if (g.fans.isNotEmpty || g.lights.isNotEmpty) ...[
          _Section(g.fans.isNotEmpty && g.lights.isNotEmpty ? 'Jets & Lights' : (g.fans.isNotEmpty ? 'Jets' : 'Lights')),
          _TileGrid(children: [
            for (final e in g.fans) _FanTile(client: c, info: e, run: _run),
            for (final e in g.lights) _LightTile(client: c, info: e, run: _run),
          ]),
        ],
        // Salt boost and production level lead Spa settings (they also stay on the Salt tab).
        if (g.switches.isNotEmpty || g.saltControls.isNotEmpty) ...[
          const _Section('Spa settings'),
          for (final e in g.saltAdjustments)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: e.kind == EntityKind.number
                  ? _NumberRow(client: c, info: e, run: _run, tile: true)
                  : Card(margin: EdgeInsets.zero, child: _GenericRow(client: c, info: e, run: _run)),
            ),
          _TileGrid(children: [
            for (final e in [...g.saltSwitches, ...g.switches]) _ToggleTile(client: c, info: e, run: _run),
          ]),
        ],
        if (g.comfortSensors.isNotEmpty) ...[
          const _Section('Water'),
          _SensorGrid(client: c, sensors: g.comfortSensors),
        ],
      ];

  Widget _cardColumn(List<Widget> children) => Card(child: Column(children: children));

  List<Widget> _sensorPage(EspHomeClient c, List<EntityInfo> sensors, String title, String empty) => [
        if (sensors.isEmpty)
          _EmptyTab(empty)
        else ...[
          _Section(title),
          _SensorGrid(client: c, sensors: sensors),
        ],
      ];

  List<Widget> _saltPage(EspHomeClient c, _EntityGroups g) {
    final level = g.saltLevelSensor;
    final others = g.saltSensors.where((e) => e != level).toList();
    return [
      if (level != null) _SaltLevelCard(client: c, info: level, status: g.saltStatus),
      if (level == null && g.saltStatus.isNotEmpty)
        _cardColumn([for (final e in g.saltStatus) _StatusRow(client: c, info: e)]),
      if (others.isNotEmpty) ...[
        const _Section('Cartridge & generator'),
        _SensorGrid(client: c, sensors: others),
      ],
      if (g.saltControls.isNotEmpty) ...[
        const _Section('Controls'),
        _cardColumn([for (final e in g.saltControls) _GenericRow(client: c, info: e, run: _run)]),
      ],
      if (g.saltButtons.isNotEmpty) ...[
        const _Section('Maintenance'),
        _cardColumn([for (final e in g.saltButtons) _ButtonRow(client: c, info: e, run: _run)]),
      ],
    ];
  }

  List<Widget> _settingsPage(EspHomeClient c, _EntityGroups g) {
    final f = c.entities.values.any((e) => e.kind == EntityKind.sensor && e.unit == '°F');
    final climate = g.climates.firstOrNull;
    final minC = climate?.minValue ?? ((79 - 32) * 5 / 9);
    final maxC = (climate == null || climate.maxValue <= climate.minValue) ? 40.0 : climate.maxValue;
    final stepDisplay = f ? 1.0 : (climate?.step ?? 0.5);
    double toDisplay(double celsius) => f ? celsius * 9 / 5 + 32 : celsius;
    double toCelsius(double disp) => f ? (disp - 32) * 5 / 9 : disp;
    final minDisp = toDisplay(minC);
    final maxDisp = toDisplay(maxC);
    final unit = f ? '°F' : '°C';
    final decimals = (!f && stepDisplay < 1) ? 1 : 0;
    double snapDisp(double v) => ((v / stepDisplay).round() * stepDisplay).clamp(minDisp, maxDisp).toDouble();

    final heatUpDisp = snapDisp(toDisplay(_device.heatUpTempC));
    final vacationDisp = snapDisp(toDisplay(_device.vacationTempC));

    return [
      const _Section('Temperature presets'),
      _cardColumn([
        _PresetTempRow(
          icon: Icons.local_fire_department,
          accent: _heatColor,
          title: 'Heat Up temperature',
          valueText: '${_fmt(heatUpDisp, decimals)}$unit',
          canDecrease: heatUpDisp > minDisp + stepDisplay * 0.1,
          canIncrease: heatUpDisp < maxDisp - stepDisplay * 0.1,
          onDecrease: () => unawaited(_updatePresetTemp(heatUpTempC: toCelsius(snapDisp(heatUpDisp - stepDisplay)))),
          onIncrease: () => unawaited(_updatePresetTemp(heatUpTempC: toCelsius(snapDisp(heatUpDisp + stepDisplay)))),
        ),
        _PresetTempRow(
          icon: Icons.flight_takeoff,
          accent: _jetsColor,
          title: 'Vacation temperature',
          valueText: '${_fmt(vacationDisp, decimals)}$unit',
          canDecrease: vacationDisp > minDisp + stepDisplay * 0.1,
          canIncrease: vacationDisp < maxDisp - stepDisplay * 0.1,
          onDecrease: () => unawaited(_updatePresetTemp(vacationTempC: toCelsius(snapDisp(vacationDisp - stepDisplay)))),
          onIncrease: () => unawaited(_updatePresetTemp(vacationTempC: toCelsius(snapDisp(vacationDisp + stepDisplay)))),
        ),
      ]),
      // On/off spa settings live on the Comfort tab; only adjustable values remain here.
      if (g.selects.isNotEmpty || g.numbers.isNotEmpty) ...[
        const _Section('Adjustments'),
        _cardColumn([
          for (final e in g.selects) _SelectRow(client: c, info: e, run: _run),
          for (final e in g.numbers) _NumberRow(client: c, info: e, run: _run),
        ]),
      ],
      if (g.status.isNotEmpty || g.buttons.isNotEmpty) ...[
        const _Section('Status & maintenance'),
        _cardColumn([
          for (final e in g.status) _StatusRow(client: c, info: e),
          for (final e in g.buttons) _ButtonRow(client: c, info: e, run: _run),
        ]),
      ],
      if (g.config.isNotEmpty || c.deviceInfo != null)
        Card(
          margin: const EdgeInsets.only(top: 16),
          child: ExpansionTile(
            title: const Text('Device & diagnostics'),
            children: [
              for (final e in g.config) _GenericRow(client: c, info: e, run: _run),
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
    ];
  }
}

/// Splits the device's entities into the tabs. Pure function of the entity list, so it adapts
/// to whatever the spa's firmware exposes.
class _EntityGroups {
  late final List<EntityInfo> climates, fans, lights, switches, selects, numbers, status, buttons, config;
  late final List<EntityInfo> comfortSensors, powerSensors, usageSensors;
  late final EntityInfo? logoLight;
  // Freshwater / ACE salt system: everything with "salt" in its id gets its own tab.
  late final List<EntityInfo> saltSensors, saltStatus, saltControls, saltButtons;
  List<EntityInfo> get saltSwitches => saltControls.where((e) => e.kind == EntityKind.switch_).toList();
  List<EntityInfo> get saltAdjustments => saltControls.where((e) => e.kind != EntityKind.switch_).toList();
  EntityInfo? get saltLevelSensor =>
      saltSensors.where((e) => e.objectId == 'salt_level' || e.objectId == 'salt_content').firstOrNull;
  EntityInfo? get saltPowerNumber =>
      saltControls
          .where((e) => e.kind == EntityKind.number && (e.objectId.contains('power') || e.objectId.contains('output')))
          .firstOrNull ??
      saltControls.where((e) => e.kind == EntityKind.number).firstOrNull;
  EntityInfo? get saltBoostSwitch =>
      saltControls.where((e) => e.kind == EntityKind.switch_ && e.objectId.contains('boost')).firstOrNull;
  bool get hasSalt =>
      saltSensors.isNotEmpty || saltStatus.isNotEmpty || saltControls.isNotEmpty || saltButtons.isNotEmpty;

  _EntityGroups(EspHomeClient c) {
    final all = c.entities.values.where((e) => !e.disabledByDefault);
    bool isSalt(EntityInfo e) => e.objectId.contains('salt');
    List<EntityInfo> sorted(Iterable<EntityInfo> it) => it.toList()..sort((a, b) => a.name.compareTo(b.name));
    List<EntityInfo> salt(Set<EntityKind> kinds) => sorted(all.where((e) => isSalt(e) && kinds.contains(e.kind)));
    saltSensors = salt({EntityKind.sensor});
    saltStatus = salt({EntityKind.binarySensor, EntityKind.textSensor});
    saltControls = salt({EntityKind.switch_, EntityKind.number, EntityKind.select});
    saltButtons = salt({EntityKind.button});

    final visible = all.where((e) => !isSalt(e));
    final logoCandidates =
        visible.where((e) => e.objectId.contains('logo_light') && !e.objectId.contains('raw')).toList();
    logoLight = logoCandidates.where((e) => e.kind == EntityKind.textSensor).firstOrNull ??
        logoCandidates.where((e) => e.kind == EntityKind.sensor).firstOrNull;
    List<EntityInfo> kind(EntityKind k, {bool main = true}) =>
        sorted(visible.where((e) => e.kind == k && ((e.category == EntityCategory.none) == main)));

    climates = kind(EntityKind.climate);
    fans = kind(EntityKind.fan);
    final allSwitches = kind(EntityKind.switch_);
    // Light switches get a big tile next to the jets on Comfort; the rest go to Settings.
    bool isLight(EntityInfo e) => e.objectId.contains('light') || e.icon.contains('lightbulb');
    lights = allSwitches.where(isLight).toList();
    switches = allSwitches.where((e) => !isLight(e)).toList();
    selects = kind(EntityKind.select);
    numbers = kind(EntityKind.number);
    status = [...kind(EntityKind.binarySensor), ...kind(EntityKind.textSensor)];
    buttons = kind(EntityKind.button);
    config = [for (final k in EntityKind.values) ...kind(k, main: false)];

    powerSensors = [];
    usageSensors = [];
    comfortSensors = [];
    for (final e in kind(EntityKind.sensor)) {
      if (e == logoLight) continue;
      if (isPowerSensor(e)) {
        powerSensors.add(e);
      } else if (isUsageSensor(e)) {
        usageSensors.add(e);
      } else {
        comfortSensors.add(e);
      }
    }
  }
}

const _powerUnits = {'W', 'kW', 'V', 'A', 'mA', 'VA', 'Wh', 'kWh'};

bool isPowerSensor(EntityInfo e) =>
    _powerUnits.contains(e.unit) || e.deviceClass == 'power' || e.deviceClass == 'energy';

bool isUsageSensor(EntityInfo e) {
  if (_durationSeconds.containsKey(e.unit) || e.deviceClass == 'duration') return true;
  final id = e.objectId;
  return id.contains('runtime') || id.contains('counter') || id.endsWith('_hours') || id.contains('days');
}

/// Freshwater salt display scale (0-120) split into the zones the spa panel colours.
const double saltScaleMax = 120;
const _saltRed = Color(0xFFE5484D), _saltYellow = Color(0xFFF5B83D), _saltGreen = Color(0xFF30A46C);
const _saltZones = <(double, double, String, Color)>[
  (0, 24, 'Too low', _saltRed),
  (24, 36, 'Low', _saltYellow),
  (36, 84, 'Good', _saltGreen),
  (84, 96, 'High', _saltYellow),
  (96, saltScaleMax, 'Too high', _saltRed),
];

/// Zone label and colour for a salt reading, or null when there is no reading yet.
(String, Color)? saltZone(double v) {
  if (v.isNaN) return null;
  for (final z in _saltZones) {
    if (v < z.$2) return (z.$3, z.$4);
  }
  return (_saltZones.last.$3, _saltZones.last.$4);
}

const _gaugeStart = 3 * pi / 4; // 7:30 position
const _gaugeSweep = 3 * pi / 2; // to 4:30
const _gaugeStroke = 14.0;

void _drawGaugeKnob(Canvas canvas, Offset center, double radius, double angle, Color ringColor,
    {bool enabled = true}) {
  final p = center + Offset(cos(angle), sin(angle)) * radius;
  canvas.drawCircle(p, _gaugeStroke * 0.95, Paint()..color = Colors.black.withValues(alpha: 0.18));
  canvas.drawCircle(p, _gaugeStroke * 0.85, Paint()..color = enabled ? Colors.white : Colors.white54);
  canvas.drawCircle(
      p,
      _gaugeStroke * 0.55,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3);
}

class _GaugeBody extends StatelessWidget {
  final CustomPainter painter;
  final Widget center;
  final String minLabel, maxLabel;
  final TextStyle? labelStyle;
  final Alignment centerAlignment;
  final double labelHorizontalAlignment;
  const _GaugeBody({
    required this.painter,
    required this.center,
    required this.minLabel,
    required this.maxLabel,
    required this.labelStyle,
    this.centerAlignment = Alignment.center,
    this.labelHorizontalAlignment = 0.62,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: painter,
        child: Stack(children: [
          Align(alignment: centerAlignment, child: center),
          Align(alignment: Alignment(-labelHorizontalAlignment, 0.95), child: Text(minLabel, style: labelStyle)),
          Align(alignment: Alignment(labelHorizontalAlignment, 0.95), child: Text(maxLabel, style: labelStyle)),
        ]),
      );
}

/// Headline salt reading as a zoned radial gauge, with any salt status flags
/// (e.g. "Salt Level Confirmed") underneath. Read-only: salt is raised by adding salt.
class _SaltLevelCard extends StatelessWidget {
  final EspHomeClient client;
  final EntityInfo info;
  final List<EntityInfo> status;
  const _SaltLevelCard({required this.client, required this.info, required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = client.states[info.key]?.number ?? double.nan;
    final zone = saltZone(value);
    final muted = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(children: [
          Row(children: [
            Icon(Icons.water_drop, color: zone?.$2 ?? theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(info.name, style: theme.textTheme.labelLarge),
          ]),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: AspectRatio(
              aspectRatio: 1.15,
              child: _GaugeBody(
                painter: _SaltGaugePainter(value: value, track: theme.colorScheme.onSurface),
                center: Column(mainAxisSize: MainAxisSize.min, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_fmt(value, 0),
                        style: theme.textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w300, fontSize: 60)),
                  ),
                  if (zone != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                          color: zone.$2.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                      child: Text(zone.$1,
                          style: theme.textTheme.labelLarge?.copyWith(color: zone.$2, fontWeight: FontWeight.w600)),
                    ),
                ]),
                minLabel: '0',
                maxLabel: _fmt(saltScaleMax, 0),
                labelStyle: muted,
              ),
            ),
          ),
          for (final e in status) _StatusRow(client: client, info: e),
        ]),
      ),
    );
  }
}

/// 270° gauge like the temperature dial: the five salt zones as a dim coloured track, the
/// part up to the reading in full colour, and a knob ringed in the current zone's colour.
class _SaltGaugePainter extends CustomPainter {
  final double value;
  final Color track;
  _SaltGaugePainter({required this.value, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 0.025; // radians between zones
    final radius = (size.shortestSide / 2) - _gaugeStroke;
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: radius);
    double angle(double v) => _gaugeStart + _gaugeSweep * (v / saltScaleMax).clamp(0.0, 1.0);
    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _gaugeStroke;

    for (final z in _saltZones) {
      final a0 = angle(z.$1) + (z.$1 > 0 ? gap / 2 : 0);
      final a1 = angle(z.$2) - (z.$2 < saltScaleMax ? gap / 2 : 0);
      canvas.drawArc(rect, a0, a1 - a0, false, arc(z.$4.withValues(alpha: 0.25)));
      if (!value.isNaN && value > z.$1) {
        final end = min(a1, angle(value));
        canvas.drawArc(rect, a0, end - a0, false, arc(z.$4));
      }
    }

    // Tick marks at the zone boundaries.
    final tick = Paint()
      ..color = track.withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final z in _saltZones.skip(1)) {
      final a = angle(z.$1);
      final dir = Offset(cos(a), sin(a));
      canvas.drawLine(c + dir * (radius - _gaugeStroke - 4), c + dir * (radius - _gaugeStroke - 10), tick);
    }

    final zone = saltZone(value);
    if (zone != null) _drawGaugeKnob(canvas, c, radius, angle(value), zone.$2);
  }

  @override
  bool shouldRepaint(_SaltGaugePainter old) => old.value != value || old.track != track;
}

class _EmptyTab extends StatelessWidget {
  final String text;
  const _EmptyTab(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(child: Text(text, textAlign: TextAlign.center)),
      );
}

typedef _Runner = void Function(Future<void> Function() action);

String _fmt(double v, int decimals) => v.isNaN ? '—' : v.toStringAsFixed(decimals.clamp(0, 3));

const _durationSeconds = {'s': 1, 'min': 60, 'h': 3600, 'd': 86400};
final _thousandsRe = RegExp(r'\B(?=(\d{3})+(?!\d))');

/// Runtime counters arrive in seconds (or minutes/hours); show them as "1,848d 8h" style text.
String formatDuration(double value, String unit) {
  if (value.isNaN) return '—';
  final perUnit = _durationSeconds[unit];
  if (perUnit == null) return '${value.toStringAsFixed(0)} $unit';
  final total = (value * perUnit).round();
  final days = total ~/ 86400;
  final hours = (total % 86400) ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  String grouped(int n) => n.toString().replaceAllMapped(_thousandsRe, (_) => ',');
  if (days > 0) return '${grouped(days)}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

/// Value + unit text for a sensor; durations are humanised.
String _sensorText(EspHomeClient client, EntityInfo e) {
  final v = client.states[e.key]?.number ?? double.nan;
  if (_durationSeconds.containsKey(e.unit)) return formatDuration(v, e.unit);
  // e.g. "Salt Generation Hours" is published without a unit.
  if (e.unit.isEmpty && e.objectId.endsWith('_hours')) return formatDuration(v, 'h');
  return '${_fmt(v, e.accuracyDecimals)} ${e.unit}'.trim();
}

IconData _iconFor(EntityInfo e) {
  final id = '${e.objectId} ${e.icon}';
  if (id.contains('light')) return Icons.lightbulb;
  if (id.contains('summer') || id.contains('sun')) return Icons.wb_sunny; // before 'lock': "sun-clock"
  if (id.contains('lock')) return Icons.lock;
  if (id.contains('clean') || id.contains('vacuum')) return Icons.cleaning_services;
  if (id.contains('jet') || id.contains('turbine')) return Icons.air;
  if (id.contains('audio') || id.contains('volume') || id.contains('music')) return Icons.music_note;
  if (id.contains('salt')) return Icons.water_drop;
  if (id.contains('power') || e.unit == 'W' || e.unit == 'A' || e.unit == 'V') return Icons.bolt;
  if (id.contains('temp') || e.unit == '°F' || e.unit == '°C') return Icons.thermostat;
  if (id.contains('runtime') || _durationSeconds.containsKey(e.unit)) return Icons.timer_outlined;
  if (id.contains('counter')) return Icons.restart_alt;
  if (id.contains('wifi')) return Icons.wifi;
  return Icons.tune;
}

// Accent colours by what an entity is about, so the same thing looks the same on every tab.
const _jetsColor = Color(0xFF1FA2B4);
const _lightsColor = Color(0xFFF5A623);
const _heatColor = Color(0xFFF0643C);
const _powerColor = Color(0xFFE8A317);
const _saltColor = Color(0xFF3D8BFD);
const _usageColor = Color(0xFF8E6CEF);
const _lockColor = Color(0xFF5C6BC0);
const _cleanColor = Color(0xFF2EAD6B);

Color _accentFor(EntityInfo e) {
  final id = '${e.objectId} ${e.icon}';
  if (id.contains('light')) return _lightsColor;
  if (id.contains('jet') || id.contains('turbine')) return _jetsColor;
  if (id.contains('salt')) return _saltColor;
  if (id.contains('summer') || id.contains('sun')) return _heatColor;
  if (id.contains('lock')) return _lockColor;
  if (id.contains('clean') || id.contains('vacuum')) return _cleanColor;
  if (isPowerSensor(e)) return _powerColor;
  if (isUsageSensor(e)) return _usageColor;
  if (id.contains('temp') || e.unit == '°F' || e.unit == '°C') return _heatColor;
  return _jetsColor;
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelLarge?.copyWith(
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Lays tiles out in 2 columns on phones and 4 when there is room (Duo open, iPad, landscape).
class _TileGrid extends StatelessWidget {
  final List<Widget> children;
  const _TileGrid({required this.children});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 4 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final child in children) SizedBox(width: width, child: child),
        ]);
      });
}

/// Icon in a soft tinted circle, used by tiles and readings.
class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool filled;
  final double size;
  const _IconBadge({required this.icon, required this.color, this.filled = false, this.size = 22});
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(size * 0.45),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? Colors.white.withValues(alpha: 0.25) : color.withValues(alpha: 0.14),
        ),
        child: Icon(icon, size: size, color: filled ? Colors.white : color),
      );
}

/// On/off spa setting (clean cycle, locks, summer timer) as a tile with a switch.
class _ToggleTile extends StatelessWidget {
  final EspHomeClient client;
  final EntityInfo info;
  final _Runner run;
  const _ToggleTile({required this.client, required this.info, required this.run});

  @override
  Widget build(BuildContext context) {
    final s = client.states[info.key];
    final on = s?.boolValue ?? false;
    final enabled = s != null && client.status == ConnectionStatus.connected;
    final accent = _accentFor(info);
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: on ? accent : Colors.transparent, width: 1.5),
      ),
      child: InkWell(
        onTap: enabled ? () => run(() => client.setSwitch(info.key, !on)) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
          // Icon and switch on top, full-width name below, so long names fit in half a phone width.
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _IconBadge(icon: _iconFor(info), color: accent, size: 18),
              const Spacer(),
              Switch(
                value: on,
                activeTrackColor: accent,
                onChanged: enabled ? (v) => run(() => client.setSwitch(info.key, v)) : null,
              ),
            ]),
            const SizedBox(height: 8),
            Text(info.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(s == null ? '—' : (on ? 'On' : 'Off'),
                style: theme.textTheme.bodySmall?.copyWith(color: on ? accent : theme.colorScheme.outline)),
          ]),
        ),
      ),
    );
  }
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
      margin: const EdgeInsets.only(bottom: 12),
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
  final EntityInfo? logoLight;
  final EntityInfo? saltLevel;
  final EntityInfo? saltPower;
  final EntityInfo? saltBoost;
  final VoidCallback? onTapSalt;
  final double heatUpTempC;
  final double vacationTempC;
  const _ClimateCard({
    required this.client,
    required this.info,
    required this.run,
    this.logoLight,
    this.saltLevel,
    this.saltPower,
    this.saltBoost,
    this.onTapSalt,
    this.heatUpTempC = SavedDevice.defaultHeatUpTempC,
    this.vacationTempC = SavedDevice.defaultVacationTempC,
  });
  @override
  State<_ClimateCard> createState() => _ClimateCardState();
}

class _ClimateCardState extends State<_ClimateCard> {
  double? _pendingTarget;
  Timer? _debounce;
  Timer? _etaTick;
  final HeatingEtaTracker _eta = HeatingEtaTracker();

  @override
  void dispose() {
    _debounce?.cancel();
    _etaTick?.cancel();
    super.dispose();
  }

  void _syncEtaTimer(bool shouldTick) {
    if (!shouldTick) {
      _etaTick?.cancel();
      _etaTick = null;
      return;
    }
    if (_etaTick?.isActive ?? false) return;
    _etaTick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  // ESPHome always reports climate temperatures in °C over the API (Home Assistant converts for
  // display). Show °F when the spa's own temperature sensors are configured in °F.
  bool get _fahrenheit => widget.client.entities.values
      .any((e) => e.kind == EntityKind.sensor && e.unit == '°F');
  double _toDisplay(double c, bool f) => f ? c * 9 / 5 + 32 : c;
  double _toCelsius(double d, bool f) => f ? (d - 32) * 5 / 9 : d;

  /// Target range in display units, from the climate entity's visual min/max.
  (double, double) _rangeFor(bool f) {
    final info = widget.info;
    final lo = _toDisplay(info.minValue, f);
    final hi = info.maxValue <= info.minValue ? _toDisplay(40, f) : _toDisplay(info.maxValue, f);
    return (lo, hi);
  }

  double _stepFor(bool f) => f ? 1.0 : widget.info.step;

  double _snapToRange(double displayValue, bool f) {
    final step = _stepFor(f);
    final (lo, hi) = _rangeFor(f);
    return ((displayValue / step).round() * step).clamp(lo, hi).toDouble();
  }

  /// [current] and the pending target are in display units.
  void _nudge(double current, int direction, bool f) =>
      _setTarget((_pendingTarget ?? current) + direction * _stepFor(f), f);

  /// Snaps [value] (display units) to the step and range, shows it, and sends it either
  /// immediately (preset buttons) or after a short debounce (stepper / dial).
  void _setTarget(double value, [bool? fahrenheit, bool immediate = false]) {
    final info = widget.info;
    final f = fahrenheit ?? _fahrenheit;
    final next = _snapToRange(value, f);
    if (!immediate && next == _pendingTarget) return;
    setState(() => _pendingTarget = next);
    void send() {
      widget.run(() => widget.client.setClimate(info.key, target: _toCelsius(next, f)));
      Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _pendingTarget = null);
      });
    }

    _debounce?.cancel();
    if (immediate) {
      send();
    } else {
      // The spa remote also debounces; send one command after the user stops tapping.
      _debounce = Timer(const Duration(milliseconds: 700), send);
    }
  }

  Widget _buildSaltOverlay({
    required double saltVal,
    required (String, Color)? zone,
    required double powerVal,
  }) =>
      Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: widget.onTapSalt,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SaltShakerIcon(size: 13, color: Colors.white.withValues(alpha: 0.88)),
              if (!saltVal.isNaN) ...[
                const SizedBox(width: 5),
                if (zone != null) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: zone.$2, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  zone == null ? '${saltVal.round()}' : '${saltVal.round()} · ${zone.$1}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
              if (!saltVal.isNaN && !powerVal.isNaN)
                Container(
                  width: 1,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: Colors.white.withValues(alpha: 0.28),
                ),
              if (!powerVal.isNaN)
                Text(
                  'Pwr ${powerVal.round()}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w500),
                ),
            ]),
          ),
        ),
      );

  Widget _buildBoostOverlay() => Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: widget.onTapSalt,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF38D9F5).withValues(alpha: 0.26),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFF7CEBFF).withValues(alpha: 0.75)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bolt, size: 12, color: Color(0xFFD8F8FF)),
              SizedBox(width: 2),
              Text(
                'Boost On',
                style: TextStyle(color: Color(0xFFD8F8FF), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.2),
              ),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final s = widget.client.states[info.key];
    final theme = Theme.of(context);
    final f = _fahrenheit;
    final (lo, hi) = _rangeFor(f);
    final current = _toDisplay(s?.currentTemperature ?? double.nan, f);
    final target = _pendingTarget ?? _toDisplay(s?.targetTemperature ?? double.nan, f);
    final decimals = (!f && info.step < 1) ? 1 : 0;
    final unit = f ? '°F' : '°C';
    final action = switch (s?.climateAction) {
      ClimateAction.heating => ('Heating', Icons.local_fire_department, const [Color(0xFFFF8A4C), Color(0xFFE5484D)]),
      ClimateAction.cooling => ('Cooling', Icons.ac_unit, const [Color(0xFF4FC3F7), Color(0xFF3D6BFD)]),
      ClimateAction.idle => ('Holding temperature', Icons.check_circle_outline, const [Color(0xFF26B5C4), Color(0xFF0E6F86)]),
      _ => ('Heater off', Icons.power_settings_new, const [Color(0xFF26B5C4), Color(0xFF0E6F86)]),
    };
    final modes = info.climateModes;
    final presets = info.climatePresets.where((p) => p == ClimatePreset.boost || p == ClimatePreset.eco).toList();
    final enabled = widget.client.status == ConnectionStatus.connected && !target.isNaN;
    const white = Colors.white;
    // Card colour follows the water temperature (blue when cool, red-orange near the top of the
    // range), deepened toward the night palette so white text stays readable.
    const deep = Color(0xFF062530);
    final heat = tempColor((current - lo) / (hi - lo));
    final cardColors = current.isNaN
        ? action.$3
        : [Color.lerp(heat, deep, 0.15)!, Color.lerp(heat, deep, 0.55)!];

    // Salt gauge telemetry
    final saltVal =
        widget.saltLevel == null ? double.nan : (widget.client.states[widget.saltLevel!.key]?.number ?? double.nan);
    final zone = saltZone(saltVal);
    final saltPowerVal =
        widget.saltPower == null ? double.nan : (widget.client.states[widget.saltPower!.key]?.number ?? double.nan);
    final saltBoostOn =
        widget.saltBoost != null && (widget.client.states[widget.saltBoost!.key]?.boolValue ?? false);
    final saltOverlay = (!saltVal.isNaN || !saltPowerVal.isNaN)
        ? _buildSaltOverlay(saltVal: saltVal, zone: zone, powerVal: saltPowerVal)
        : null;
    final boostOverlay = saltBoostOn ? _buildBoostOverlay() : null;

    // Heat Up + Vacation presets & live rate-of-rise Ready ETA
    final heatUpTarget = _snapToRange(_toDisplay(widget.heatUpTempC, f), f);
    final vacationTarget = _snapToRange(_toDisplay(widget.vacationTempC, f), f);
    final presetTol = f ? 0.45 : 0.2;
    final heatUpActive = !target.isNaN && (target - heatUpTarget).abs() < presetTol;
    final vacationActive = !target.isNaN && (target - vacationTarget).abs() < presetTol;
    final now = DateTime.now();
    _eta.update(
      currentTemp: current,
      targetTemp: heatUpTarget,
      active: heatUpActive && !current.isNaN && current < heatUpTarget - 0.05,
      isFahrenheit: f,
      now: now,
    );
    final eta = heatUpActive
        ? _eta.estimate(currentTemp: current, targetTemp: heatUpTarget, isFahrenheit: f, now: now)
        : null;
    final heatUpReached = heatUpActive && (eta?.reached ?? false);
    final heatUpHeating = heatUpActive && !heatUpReached && (eta?.readyAt != null);
    _syncEtaTimer(heatUpHeating);

    Widget roundButton(IconData icon, VoidCallback? onPressed) => Material(
          color: white.withValues(alpha: onPressed == null ? 0.10 : 0.22),
          shape: const CircleBorder(),
          child: IconButton(
            iconSize: 30,
            padding: const EdgeInsets.all(14),
            color: white,
            disabledColor: white.withValues(alpha: 0.4),
            onPressed: onPressed,
            icon: Icon(icon),
          ),
        );

    final heatUpTitle = heatUpReached
        ? 'Ready'
        : (heatUpHeating ? (eta!.calibrated ? 'Ready by' : 'Est. Ready') : 'Heat Up');
    final heatUpSub = heatUpReached
        ? 'At ${_fmt(heatUpTarget, decimals)}$unit'
        : (heatUpHeating
            ? MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(eta!.readyAt!))
            : '${_fmt(heatUpTarget, decimals)}$unit');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: cardColors),
        boxShadow: [BoxShadow(color: cardColors.first.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      child: Theme(
        // Segmented buttons and text on the gradient read best in white.
        data: theme.copyWith(
          segmentedButtonTheme: SegmentedButtonThemeData(
            style: SegmentedButton.styleFrom(
              foregroundColor: white,
              selectedForegroundColor: cardColors.last,
              selectedBackgroundColor: white,
              side: BorderSide(color: white.withValues(alpha: 0.5)),
            ),
          ),
        ),
        child: Column(children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(action.$2, color: white, size: 16),
                  const SizedBox(width: 6),
                  Text(action.$1, style: theme.textTheme.labelMedium?.copyWith(color: white)),
                ]),
              ),
              const SizedBox(width: 8),
              if (widget.logoLight != null)
                Expanded(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Builder(builder: (_) {
                      final logoState = widget.client.states[widget.logoLight!.key];
                      final customLabel =
                          (logoState != null && !logoState.missing && logoState.text.trim().isNotEmpty)
                              ? logoState.text.trim()
                              : null;
                      return LogoLightBadge(
                        state: parseLogoLightState(logoState),
                        customLabel: customLabel,
                      );
                    }),
                  ),
                )
              else ...[
                const Spacer(),
                Text(info.name, style: theme.textTheme.labelLarge?.copyWith(color: white.withValues(alpha: 0.85))),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: _TempDial(
              min: lo,
              max: hi,
              current: current,
              target: target,
              enabled: enabled,
              onDrag: _setTarget,
              saltOverlay: saltOverlay,
              boostOverlay: boostOverlay,
              center: Column(mainAxisSize: MainAxisSize.min, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${_fmt(current, decimals)}$unit',
                      style: theme.textTheme.displayLarge?.copyWith(color: white, fontWeight: FontWeight.w300, fontSize: 64)),
                ),
                Text('Water', style: theme.textTheme.bodyMedium?.copyWith(color: white.withValues(alpha: 0.8))),
              ]),
              minLabel: '${_fmt(lo, decimals)}°',
              maxLabel: '${_fmt(hi, decimals)}°',
            ),
          ),
          const SizedBox(height: 8),
          // The target shrinks to fit between the buttons, so the row never overflows on the
          // narrow column beside the rail (Duo closed) and stays compact on wide screens.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Row(children: [
              roundButton(Icons.remove, enabled ? () => _nudge(target, -1, f) : null),
              Expanded(
                child: Column(children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('${_fmt(target, decimals)}$unit',
                        style: theme.textTheme.headlineMedium?.copyWith(color: white, fontWeight: FontWeight.w600)),
                  ),
                  Text(_pendingTarget == null ? 'Set to' : 'Setting…',
                      style: theme.textTheme.bodySmall?.copyWith(color: white.withValues(alpha: 0.8))),
                ]),
              ),
              roundButton(Icons.add, enabled ? () => _nudge(target, 1, f) : null),
            ]),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Row(children: [
              Expanded(
                child: _PresetButton(
                  icon: heatUpReached ? Icons.check_circle : Icons.local_fire_department,
                  title: heatUpTitle,
                  subtitle: heatUpSub,
                  active: heatUpActive,
                  activeAccent: heatUpReached ? const Color(0xFF17874B) : const Color(0xFFC93E24),
                  progress: heatUpHeating ? eta!.progress : null,
                  onTap: enabled
                      ? () {
                          _eta.start(currentTemp: current, targetTemp: heatUpTarget, now: DateTime.now());
                          _setTarget(heatUpTarget, f, true);
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PresetButton(
                  icon: Icons.flight_takeoff,
                  title: 'Vacation',
                  subtitle: vacationActive
                      ? 'On · ${_fmt(vacationTarget, decimals)}$unit'
                      : '${_fmt(vacationTarget, decimals)}$unit',
                  active: vacationActive,
                  activeAccent: const Color(0xFF175EA8),
                  onTap: enabled
                      ? () {
                          _eta.reset();
                          _setTarget(vacationTarget, f, true);
                        }
                      : null,
                ),
              ),
            ]),
          ),
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

/// Quick preset button inside [_ClimateCard] for Heat Up (with optional rate-of-rise progress bar)
/// and Vacation.
class _PresetButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final Color activeAccent;
  final double? progress;
  final VoidCallback? onTap;
  const _PresetButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.activeAccent,
    this.progress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active ? Colors.white.withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.16);
    final border = active ? Colors.white : Colors.white.withValues(alpha: 0.28);
    final fg = active ? activeAccent : Colors.white;
    final iconBg = active ? activeAccent.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.2);

    return Material(
      color: bg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Icon(icon, size: 16, color: fg),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? fg.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.85),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                    ),
                  ),
                ]),
              ),
            ]),
          ),
          if (progress != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SizedBox(
                height: 3,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.1),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress!.clamp(0.0, 1.0),
                    child: ColoredBox(color: activeAccent),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Cool-to-hot scale used by the dial and the temperature card: blue at the bottom of the
/// spa's range, through aqua and amber, to red-orange at the top.
const _tempColors = [Color(0xFF3D7BFF), Color(0xFF22C3D6), Color(0xFFFFB347), Color(0xFFFF5A36)];
const _tempStops = [0.0, 0.35, 0.72, 1.0];

/// Colour for a position 0..1 within the temperature range.
Color tempColor(double f) {
  final t = f.isNaN ? 0.35 : f.clamp(0.0, 1.0);
  for (var i = 1; i < _tempStops.length; i++) {
    if (t <= _tempStops[i]) {
      final local = (t - _tempStops[i - 1]) / (_tempStops[i] - _tempStops[i - 1]);
      return Color.lerp(_tempColors[i - 1], _tempColors[i], local)!;
    }
  }
  return _tempColors.last;
}

/// 270° radial gauge from [min] to [max]. The filled arc shows the current water temperature;
/// the knob marks the target and can be dragged around the dial to change it.
class _TempDial extends StatelessWidget {
  final double min, max, current, target;
  final bool enabled;
  final ValueChanged<double> onDrag;
  final Widget center;
  final String minLabel, maxLabel;
  final Widget? saltOverlay;
  final Widget? boostOverlay;
  const _TempDial({
    required this.min,
    required this.max,
    required this.current,
    required this.target,
    required this.enabled,
    required this.onDrag,
    required this.center,
    required this.minLabel,
    required this.maxLabel,
    this.saltOverlay,
    this.boostOverlay,
  });

  double _valueAt(Offset local, Size size) {
    final c = size.center(Offset.zero);
    var a = atan2(local.dy - c.dy, local.dx - c.dx) - _gaugeStart;
    a = (a % (2 * pi) + 2 * pi) % (2 * pi);
    // In the 90° gap at the bottom, snap to whichever end is closer.
    if (a > _gaugeSweep) a = (a - _gaugeSweep) < (2 * pi - a) ? _gaugeSweep : 0;
    return min + (a / _gaugeSweep) * (max - min);
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.75));
    final hasBottomBadges = saltOverlay != null || boostOverlay != null;
    return AspectRatio(
      aspectRatio: 1.15,
      child: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        void drag(Offset p) {
          if (enabled) onDrag(_valueAt(p, size));
        }

        return Stack(children: [
          GestureDetector(
            onPanStart: (d) => drag(d.localPosition),
            onPanUpdate: (d) => drag(d.localPosition),
            onTapUp: (d) => drag(d.localPosition),
            child: _GaugeBody(
              painter: _TempDialPainter(min: min, max: max, current: current, target: target, enabled: enabled),
              centerAlignment: hasBottomBadges ? const Alignment(0, -0.26) : Alignment.center,
              labelHorizontalAlignment: hasBottomBadges ? 0.74 : 0.62,
              center: Padding(
                padding: EdgeInsets.fromLTRB(44, hasBottomBadges ? 18 : 48, 44, hasBottomBadges ? 46 : 48),
                child: center,
              ),
              minLabel: minLabel,
              maxLabel: maxLabel,
              labelStyle: labelStyle,
            ),
          ),
          if (saltOverlay != null)
            Align(
              alignment: const Alignment(0, 0.56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 38),
                child: FittedBox(fit: BoxFit.scaleDown, child: saltOverlay!),
              ),
            ),
          if (boostOverlay != null)
            Align(
              alignment: const Alignment(0, 0.94),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: FittedBox(fit: BoxFit.scaleDown, child: boostOverlay!),
              ),
            ),
        ]);
      }),
    );
  }
}

class _TempDialPainter extends CustomPainter {
  final double min, max, current, target;
  final bool enabled;
  _TempDialPainter({
    required this.min,
    required this.max,
    required this.current,
    required this.target,
    required this.enabled,
  });

  double _frac(double v) => v.isNaN ? double.nan : ((v - min) / (max - min)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide / 2) - _gaugeStroke;
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: radius);
    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _gaugeStroke
      ..strokeCap = StrokeCap.round;

    // Track and tick marks every 10% of the range.
    canvas.drawArc(rect, _gaugeStart, _gaugeSweep, false, arc(Colors.white.withValues(alpha: 0.22)));
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= 10; i++) {
      final a = _gaugeStart + _gaugeSweep * i / 10;
      final dir = Offset(cos(a), sin(a));
      canvas.drawLine(c + dir * (radius - _gaugeStroke - 4), c + dir * (radius - _gaugeStroke - (i % 5 == 0 ? 12 : 8)), tick);
    }

    // Current water temperature: the arc runs blue -> red across the whole range, so its tip
    // shows how hot the water is. A soft glow underneath lifts it off the card.
    final cf = _frac(current);
    if (!cf.isNaN && cf > 0) {
      // Hold the hot end through half the bottom gap, then switch hard to blue, so the round
      // cap that pokes just before the start of the arc is blue rather than wrapped-around red.
      const sf = _gaugeSweep / (2 * pi);
      const gapMid = sf + (1 - sf) / 2;
      final shader = SweepGradient(
        colors: [..._tempColors, _tempColors.last, _tempColors.first, _tempColors.first],
        stops: [..._tempStops.map((s) => s * sf), gapMid, gapMid, 1.0],
        transform: const GradientRotation(_gaugeStart),
      ).createShader(rect);
      canvas.drawArc(
          rect,
          _gaugeStart,
          _gaugeSweep * cf,
          false,
          arc(Colors.white)
            ..shader = shader
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawArc(rect, _gaugeStart, _gaugeSweep * cf, false, arc(Colors.white)..shader = shader);
    }

    // Target knob.
    final tf = _frac(target);
    if (!tf.isNaN) {
      _drawGaugeKnob(canvas, c, radius, _gaugeStart + _gaugeSweep * tf, tempColor(tf), enabled: enabled);
    }
  }

  @override
  bool shouldRepaint(_TempDialPainter old) =>
      old.current != current || old.target != target || old.min != min || old.max != max || old.enabled != enabled;
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

    return _BigTile(
      icon: Icons.air,
      accent: _jetsColor,
      name: info.name,
      label: label,
      on: on,
      onTap: client.status == ConnectionStatus.connected ? tap : null,
      onLongPress: on ? () => run(() => client.setFan(info.key, on: false)) : null,
    );
  }
}

class _LightTile extends StatelessWidget {
  final EspHomeClient client;
  final EntityInfo info;
  final _Runner run;
  const _LightTile({required this.client, required this.info, required this.run});

  @override
  Widget build(BuildContext context) {
    final s = client.states[info.key];
    final on = s?.boolValue ?? false;
    return _BigTile(
      icon: on ? Icons.lightbulb : Icons.lightbulb_outline,
      accent: _lightsColor,
      name: info.name,
      label: s == null ? '—' : (on ? 'On' : 'Off'),
      on: on,
      onTap: (s == null || client.status != ConnectionStatus.connected)
          ? null
          : () => run(() => client.setSwitch(info.key, !on)),
    );
  }
}

/// Large square-ish toggle used for jets and lights.
class _BigTile extends StatelessWidget {
  final IconData icon;
  final String name;
  final String label;
  final bool on;
  final Color accent;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const _BigTile({
    required this.icon,
    required this.name,
    required this.label,
    required this.on,
    required this.accent,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = on ? Colors.white : theme.colorScheme.onSurface;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: 132,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: on ? null : theme.cardTheme.color ?? theme.colorScheme.surfaceContainerLow,
        border: on ? null : Border.all(color: Colors.white.withValues(alpha: 0.12)),
        gradient: on
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, Color.lerp(accent, Colors.black, 0.25)!],
              )
            : null,
        boxShadow: on ? [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))] : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _IconBadge(icon: icon, color: accent, filled: on),
                const Spacer(),
                Icon(on ? Icons.toggle_on : Icons.toggle_off_outlined,
                    size: 30, color: on ? Colors.white : theme.colorScheme.outlineVariant),
              ]),
              const Spacer(),
              Text(name, style: theme.textTheme.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w600)),
              Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: on ? Colors.white70 : theme.colorScheme.outline)),
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
  /// tile: a full-width card styled like [_ToggleTile] (Comfort tab) instead of a list row.
  final bool tile;
  const _NumberRow({required this.client, required this.info, required this.run, this.tile = false});
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
    final text = '${_fmt(value, info.step < 1 ? 1 : 0)}${info.unit}';
    final slider = Slider(
      min: min,
      max: max,
      divisions: divisions > 0 && divisions <= 200 ? divisions : null,
      value: value,
      label: text,
      onChanged: widget.client.status == ConnectionStatus.connected ? (v) => setState(() => _drag = v) : null,
      onChangeEnd: (v) {
        setState(() => _drag = null);
        widget.run(() => widget.client.setNumber(info.key, v));
      },
    );
    if (!widget.tile) {
      return ListTile(leading: Icon(_iconFor(info)), title: Text(info.name), subtitle: slider, trailing: Text(text));
    }
    final theme = Theme.of(context);
    final accent = _accentFor(info);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _IconBadge(icon: _iconFor(info), color: accent, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(info.name,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            Text(text, style: theme.textTheme.titleLarge?.copyWith(color: accent, fontWeight: FontWeight.w600)),
          ]),
          SliderTheme(
            // Default side padding insets the track well past the icon and value; line them up.
            data: SliderTheme.of(context).copyWith(
                activeTrackColor: accent, thumbColor: accent, padding: const EdgeInsets.fromLTRB(12, 18, 12, 18)),
            child: slider,
          ),
        ]),
      ),
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
    return _TileGrid(children: [
      for (final e in sensors)
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _IconBadge(icon: _iconFor(e), color: _accentFor(e), size: 16),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _sensorText(client, e),
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 2),
              Text(e.name,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
    ]);
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
            trailing: Text(_sensorText(client, info)),
          ),
        _ => _StatusRow(client: client, info: info),
      };
}

class _PresetTempRow extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String valueText;
  final bool canDecrease;
  final bool canIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _PresetTempRow({
    required this.icon,
    required this.accent,
    required this.title,
    required this.valueText,
    required this.canDecrease,
    required this.canIncrease,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: _IconBadge(icon: icon, color: accent, size: 18),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: canDecrease ? onDecrease : null,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 46),
          child: Text(
            valueText,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline),
          onPressed: canIncrease ? onIncrease : null,
        ),
      ]),
    );
  }
}
