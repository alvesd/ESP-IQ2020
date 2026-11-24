import 'package:flutter/material.dart';

import '../device_store.dart';
import 'add_device_sheet.dart';
import 'spa_backdrop.dart';
import 'spa_screen.dart';
import 'watch_setup_screen.dart';

class HomeScreen extends StatefulWidget {
  final DeviceStore store;
  const HomeScreen({super.key, required this.store});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Discovery _discovery = Discovery();
  bool _openedSingle = false;

  @override
  void initState() {
    super.initState();
    _discovery.start().catchError((Object _) {});
    // With exactly one saved spa, go straight to it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_openedSingle && widget.store.devices.length == 1) {
        _openedSingle = true;
        _open(widget.store.devices.single);
      }
    });
  }

  @override
  void dispose() {
    _discovery.dispose();
    super.dispose();
  }

  void _open(SavedDevice d) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SpaBackdrop(child: SpaScreen(device: d, store: widget.store))));
  }

  Future<void> _add({DiscoveredDevice? from, SavedDevice? edit}) async {
    final saved = await showModalBottomSheet<SavedDevice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddDeviceSheet(discovered: from, existing: edit),
    );
    if (saved != null) await widget.store.upsert(saved);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hot Tubs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(),
        icon: const Icon(Icons.add),
        label: const Text('Add manually'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.store, _discovery]),
        builder: (context, _) {
          final savedIds = widget.store.devices.map((d) => d.id).toSet();
          final newOnes = _discovery.found.values.where((d) => !savedIds.contains(d.id)).toList()
            ..sort((a, b) => (b.looksLikeSpa ? 1 : 0) - (a.looksLikeSpa ? 1 : 0));
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (widget.store.devices.isNotEmpty) const _Header('My spas'),
              for (final d in widget.store.devices)
                ListTile(
                  leading: const Icon(Icons.hot_tub),
                  title: Text(d.name),
                  subtitle: Text('${d.host}:${d.port}${d.encryptionKey.isEmpty ? '  (unencrypted)' : ''}'),
                  onTap: () => _open(d),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') await _add(edit: d);
                      if (v == 'remove') await widget.store.remove(d.id);
                      if (v == 'watch' && context.mounted) {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => WatchSetupScreen(device: d)),
                        );
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'watch', child: Text('Set up watch')),
                      PopupMenuItem(value: 'remove', child: Text('Remove')),
                    ],
                  ),
                ),
              const _Header('Found on this network'),
              if (newOnes.isEmpty)
                const ListTile(
                  leading: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                  title: Text('Searching for ESPHome devices…'),
                  subtitle: Text('Phone and hot tub must be on the same Wi-Fi.'),
                ),
              for (final d in newOnes)
                ListTile(
                  leading: Icon(d.looksLikeSpa ? Icons.hot_tub : Icons.memory),
                  title: Text(d.friendlyName),
                  subtitle: Text('${d.host}  ·  ${d.encrypted ? 'encrypted' : 'unencrypted'}'),
                  trailing: const Icon(Icons.add_circle_outline),
                  onTap: () => _add(from: d),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}
