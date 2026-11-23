import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/noise.dart';
import '../device_store.dart';

class AddDeviceSheet extends StatefulWidget {
  final DiscoveredDevice? discovered;
  final SavedDevice? existing;
  const AddDeviceSheet({super.key, this.discovered, this.existing});

  @override
  State<AddDeviceSheet> createState() => _AddDeviceSheetState();
}

class _AddDeviceSheetState extends State<AddDeviceSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _key;
  bool _showKey = false;

  Future<void> _pasteKey() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    // Accept a whole YAML line like `key: "abc..="` as well as the bare key.
    final match = RegExp(r'[A-Za-z0-9+/]{42,43}=').firstMatch(text);
    _key.text = match?.group(0) ?? text;
    _form.currentState?.validate();
  }

  @override
  void initState() {
    super.initState();
    final d = widget.discovered;
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? d?.friendlyName ?? 'Hot Tub');
    _host = TextEditingController(text: e?.host ?? d?.host ?? '');
    _port = TextEditingController(text: '${e?.port ?? d?.port ?? 6053}');
    _key = TextEditingController(text: e?.encryptionKey ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _host, _port, _key]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final host = _host.text.trim();
    final id = widget.existing?.id ?? widget.discovered?.id ?? host.split('.').first;
    Navigator.of(context).pop(SavedDevice(
      id: id,
      name: _name.text.trim(),
      host: host,
      port: int.parse(_port.text.trim()),
      encryptionKey: _key.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final needsKey = widget.discovered?.encrypted ?? true;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Add hot tub' : 'Edit hot tub',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
            TextFormField(
              controller: _host,
              decoration: const InputDecoration(labelText: 'Host or IP', hintText: 'hot-tub.local'),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _port,
              decoration: const InputDecoration(labelText: 'API port'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final p = int.tryParse(v ?? '');
                return (p == null || p < 1 || p > 65535) ? 'Invalid port' : null;
              },
            ),
            TextFormField(
              controller: _key,
              decoration: InputDecoration(
                labelText: 'API encryption key',
                helperText: needsKey ? 'api.encryption.key from the ESPHome YAML' : 'Device is not encrypted',
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Paste',
                    icon: const Icon(Icons.content_paste),
                    onPressed: _pasteKey,
                  ),
                  IconButton(
                    tooltip: _showKey ? 'Hide' : 'Show',
                    icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  ),
                ]),
              ),
              autocorrect: false,
              enableSuggestions: false,
              obscureText: !_showKey,
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return needsKey ? 'Required for this device' : null;
                try {
                  decodeNoisePsk(s);
                  return null;
                } on FormatException catch (e) {
                  return e.message;
                }
              },
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
