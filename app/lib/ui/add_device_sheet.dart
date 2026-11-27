import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/cf_access.dart';
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
  late final TextEditingController _remoteUrl;
  late final TextEditingController _cfClientId;
  late final TextEditingController _cfClientSecret;
  bool _showKey = false;
  bool _showCfSecret = false;
  bool _useCfToken = false;

  Future<void> _pasteKey() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    // Accept a whole YAML line like `key: "abc..="` as well as the bare key.
    final match = RegExp(r'[A-Za-z0-9+/]{42,43}=').firstMatch(text);
    _key.text = match?.group(0) ?? text;
    _form.currentState?.validate();
  }

  Future<void> _pasteCfSecret() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    _cfClientSecret.text = text;
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
    _remoteUrl = TextEditingController(text: e?.remoteUrl ?? '');
    _cfClientId = TextEditingController(text: e?.cfAccessClientId ?? '');
    _cfClientSecret = TextEditingController(text: e?.cfAccessClientSecret ?? '');
    _useCfToken = (e?.cfAccessClientId.isNotEmpty ?? false) || (e?.cfAccessClientSecret.isNotEmpty ?? false);
  }

  @override
  void dispose() {
    for (final c in [_name, _host, _port, _key, _remoteUrl, _cfClientId, _cfClientSecret]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _hasRemoteInput => _remoteUrl.text.trim().isNotEmpty;

  void _save() {
    if (!_form.currentState!.validate()) return;
    final host = _host.text.trim();
    final remoteUrl = normalizeRemoteUrl(_remoteUrl.text);
    final derivedRemoteId =
        remoteUrl.isEmpty ? 'hot-tub' : (Uri.tryParse(remoteUrl)?.host.split('.').first ?? 'hot-tub');
    final id = widget.existing?.id ??
        widget.discovered?.id ??
        (host.isNotEmpty ? host.split('.').first : derivedRemoteId);
    Navigator.of(context).pop(SavedDevice(
      id: id,
      name: _name.text.trim(),
      host: host,
      port: int.tryParse(_port.text.trim()) ?? 6053,
      encryptionKey: _key.text.trim(),
      remoteUrl: remoteUrl,
      cfAccessClientId: _useCfToken ? _cfClientId.text.trim() : '',
      cfAccessClientSecret: _useCfToken ? _cfClientSecret.text.trim() : '',
      heatUpTempC: widget.existing?.heatUpTempC ?? SavedDevice.defaultHeatUpTempC,
      vacationTempC: widget.existing?.vacationTempC ?? SavedDevice.defaultVacationTempC,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final needsKey = widget.discovered?.encrypted ?? true;
    final e = widget.existing;
    final hasExistingRemote = e != null &&
        (e.remoteUrl.isNotEmpty || e.cfAccessClientId.isNotEmpty || e.cfAccessClientSecret.isNotEmpty);
    final defaultRemote = normalizeRemoteUrl(kDefaultRemoteUrl);
    final hasDefaultCreds =
        kDefaultCfAccessClientId.trim().isNotEmpty && kDefaultCfAccessClientSecret.trim().isNotEmpty;

    return SingleChildScrollView(
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
              decoration: const InputDecoration(
                labelText: 'Host or IP',
                hintText: 'hotspring.local (optional if Remote URL set)',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: (v) {
                if ((v == null || v.trim().isEmpty) && !_hasRemoteInput) {
                  return 'Enter a local Host/IP or a Remote URL';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _port,
              decoration: const InputDecoration(labelText: 'API port'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty && _host.text.trim().isEmpty && _hasRemoteInput) return null;
                final p = int.tryParse(s);
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
                if (s.isEmpty) {
                  if (_host.text.trim().isEmpty && _hasRemoteInput) return null;
                  return needsKey ? 'Required for this device' : null;
                }
                try {
                  decodeNoisePsk(s);
                  return null;
                } on FormatException catch (err) {
                  return err.message;
                }
              },
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: hasExistingRemote,
              title: const Text('Remote access (optional)'),
              subtitle: const Text('Cloudflare Tunnel or HTTPS URL when away from home'),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Leave blank for local Wi-Fi only. When configured, the app tries local Wi-Fi first and falls back to this URL.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (defaultRemote.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ActionChip(
                            avatar: const Icon(Icons.cloud_outlined, size: 16),
                            label: Text('Use $defaultRemote'),
                            onPressed: () => setState(() {
                              _remoteUrl.text = defaultRemote;
                            }),
                          ),
                        ),
                      ],
                      TextFormField(
                        controller: _remoteUrl,
                        decoration: const InputDecoration(
                          labelText: 'Remote URL',
                          hintText: 'https://spa.alves.us',
                        ),
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          final norm = normalizeRemoteUrl(v ?? '');
                          if (norm.isEmpty) return null;
                          final uri = Uri.tryParse(norm);
                          if (uri == null ||
                              (uri.scheme != 'http' && uri.scheme != 'https') ||
                              uri.host.isEmpty) {
                            return 'Enter a valid http:// or https:// URL';
                          }
                          return null;
                        },
                      ),
                      if (_hasRemoteInput && !_useCfToken) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.vpn_key_outlined, size: 16),
                            label: const Text('Add Cloudflare Access token'),
                            onPressed: () => setState(() => _useCfToken = true),
                          ),
                        ),
                      ],
                      if (_useCfToken) ...[
                        TextFormField(
                          controller: _cfClientId,
                          decoration: InputDecoration(
                            labelText: 'CF-Access-Client-Id',
                            helperText: hasDefaultCreds && defaultRemote.isNotEmpty
                                ? 'Leave blank to use build-time token for $defaultRemote'
                                : 'Stored encrypted in Keychain / Keystore',
                          ),
                          autocorrect: false,
                          enableSuggestions: false,
                          validator: (v) {
                            final id = (v ?? '').trim();
                            final sec = _cfClientSecret.text.trim();
                            if (id.isEmpty != sec.isEmpty) {
                              return 'Enter both Client ID and Client Secret';
                            }
                            return null;
                          },
                        ),
                        TextFormField(
                          controller: _cfClientSecret,
                          decoration: InputDecoration(
                            labelText: 'CF-Access-Client-Secret',
                            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                tooltip: 'Paste',
                                icon: const Icon(Icons.content_paste),
                                onPressed: _pasteCfSecret,
                              ),
                              IconButton(
                                tooltip: _showCfSecret ? 'Hide' : 'Show',
                                icon: Icon(_showCfSecret ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _showCfSecret = !_showCfSecret),
                              ),
                            ]),
                          ),
                          autocorrect: false,
                          enableSuggestions: false,
                          obscureText: !_showCfSecret,
                          validator: (v) {
                            final sec = (v ?? '').trim();
                            final id = _cfClientId.text.trim();
                            if (id.isEmpty != sec.isEmpty) {
                              return 'Enter both Client ID and Client Secret';
                            }
                            return null;
                          },
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => setState(() {
                              _cfClientId.clear();
                              _cfClientSecret.clear();
                              _useCfToken = false;
                            }),
                            child: const Text('Remove token'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
