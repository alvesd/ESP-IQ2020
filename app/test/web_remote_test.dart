import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iq2020_mobile/api/cf_access.dart';
import 'package:iq2020_mobile/api/esphome_client.dart';
import 'package:iq2020_mobile/api/messages.dart';
import 'package:iq2020_mobile/api/protobuf.dart';
import 'package:iq2020_mobile/api/web_client_protocol.dart';
import 'package:iq2020_mobile/device_store.dart';
import 'package:iq2020_mobile/watch/spa_snapshot.dart';

void main() {
  group('SseParser', () {
    test('parses chunked LF and CRLF events with multi-line data and comments', () {
      final p = SseParser();
      expect(p.addChunk(': heartbeat\r\n\r\n'), isEmpty);

      final part1 = p.addChunk('event: ping\r\ndata: {"title":');
      expect(part1, isEmpty);

      final part2 = p.addChunk('"hotspring"}\r\n\r\nevent: state\n'
          'data: {"id":"switch-lights",\n'
          'data: "value":true}\n\n');
      expect(part2.length, 2);
      expect(part2[0].event, 'ping');
      expect(part2[0].data, '{"title":"hotspring"}');
      expect(part2[1].event, 'state');
      expect(part2[1].data, '{"id":"switch-lights",\n"value":true}');
    });
  });

  group('parseWebStateEvent & SpaSnapshot', () {
    test('decodes all entity domains and populates SpaSnapshot', () {
      final client = EspHomeClient(host: 'test');
      final events = <Map<String, dynamic>>[
        {
          'id': 'climate-temperature',
          'domain': 'climate',
          'name': 'Temperature',
          'min_temp': 26.111,
          'max_temp': 40.0,
          'step': 0.5,
          'modes': ['OFF', 'HEAT', 'COOL'],
          'presets': ['NONE', 'BOOST', 'ECO'],
          'mode': 'HEAT',
          'action': 'HEATING',
          'preset': 'BOOST',
          'current_temperature': 38.889,
          'target_temperature': 40.0,
        },
        {
          'id': 'sensor-current_temperature',
          'domain': 'sensor',
          'name': 'Current Temperature',
          'uom': '°F',
          'value': 102,
        },
        {
          'id': 'fan-jets_1',
          'domain': 'fan',
          'name': 'Jets 1',
          'speed_count': 2,
          'speed_level': 1,
          'value': true,
        },
        {
          'id': 'switch-lights',
          'domain': 'switch',
          'name': 'Lights',
          'icon': 'mdi:lightbulb',
          'value': false,
        },
        {
          'id': 'sensor-salt_level',
          'domain': 'sensor',
          'name': 'Salt Level',
          'value': 50,
        },
        {
          'id': 'number-salt_system_power',
          'domain': 'number',
          'name': 'Salt System Power',
          'min_value': 1,
          'max_value': 10,
          'step': 1,
          'value': 6,
        },
        {
          'id': 'binary_sensor-heating_rate_calibrated',
          'domain': 'binary_sensor',
          'name': 'Heating Rate Calibrated',
          'entity_category': 2,
          'value': true,
        },
        {
          'id': 'text_sensor-ready_time',
          'domain': 'text_sensor',
          'name': 'Ready Time',
          'state': '3:15 PM',
        },
        {
          'id': 'select-light_color',
          'domain': 'select',
          'name': 'Light Color',
          'option': ['Blue', 'Cyan'],
          'state': 'Cyan',
        },
        {
          'id': 'button-salt_test',
          'domain': 'button',
          'name': 'Salt Test',
        },
      ];

      for (final raw in events) {
        final key = webEntityKey(raw['id'] as String);
        final parsed = parseWebStateEvent(raw, existing: client.entities[key])!;
        client.entities[parsed.$1.key] = parsed.$1;
        client.states[parsed.$1.key] = parsed.$2;
      }
      client.status = ConnectionStatus.connected;

      final snap = SpaSnapshot.fromClient(client, name: 'hotspring');
      expect(snap.online, isTrue);
      expect(snap.unit, '°F');
      expect(snap.current!.round(), 102);
      expect(snap.target!.round(), 104);
      expect(snap.heater, 'heating');
      expect(snap.salt, 50);
      expect(snap.saltZone, 'Good');
      expect(snap.saltPower, 6);
      expect([for (final t in snap.toggles) '${t.kind}:${t.name}:${t.on}'], ['fan:Jets 1:true', 'light:Lights:false']);

      final selectInfo = client.entities[webEntityKey('select-light_color')]!;
      expect(selectInfo.options, ['Blue', 'Cyan']);
      expect(client.states[selectInfo.key]!.text, 'Cyan');

      // Incremental update without domain/metadata preserves existing options/name,
      // and ESPHome 2026 slash-delimited IDs ("climate/Temperature") resolve domain too.
      final inc = parseWebStateEvent(
        {'id': 'select-light_color', 'state': 'Blue'},
        existing: selectInfo,
      )!;
      expect(inc.$1.name, 'Light Color');
      expect(inc.$1.options, ['Blue', 'Cyan']);
      expect(inc.$2.text, 'Blue');

      final slashClimate = parseWebStateEvent({
        'id': 'climate/Temperature',
        'mode': 'HEAT',
        'action': 'OFF',
        'current_temperature': '39',
        'target_temperature': '29',
      })!;
      expect(slashClimate.$1.kind, EntityKind.climate);
      expect(slashClimate.$2.currentTemperature, 39.0);
      expect(slashClimate.$2.targetTemperature, 29.0);
    });
  });

  group('buildWebCommandUri', () {
    final base = Uri.parse('https://spa.example.com');

    test('builds REST URIs for all 7 command entity kinds', () {
      expect(
        buildWebCommandUri(base, EntityInfo(kind: EntityKind.switch_, key: 1, objectId: 'lights', name: 'Lights'), 'turn_on').toString(),
        'https://spa.example.com/switch/Lights/turn_on',
      );
      expect(
        buildWebCommandUri(base, EntityInfo(kind: EntityKind.fan, key: 2, objectId: 'jets_1', name: 'Jets 1'), 'turn_on', {'speed_level': '2'}).toString(),
        'https://spa.example.com/fan/Jets%201/turn_on?speed_level=2',
      );
      expect(
        buildWebCommandUri(base, EntityInfo(kind: EntityKind.climate, key: 3, objectId: 'temperature', name: 'Temperature'), 'set', {'target_temperature': '38.89'}).toString(),
        'https://spa.example.com/climate/Temperature/set?target_temperature=38.89',
      );
      expect(
        buildWebCommandUri(base, EntityInfo(kind: EntityKind.number, key: 4, objectId: 'salt_system_power', name: 'Salt System Power'), 'set', {'value': '5'}).toString(),
        'https://spa.example.com/number/Salt%20System%20Power/set?value=5',
      );
      expect(
        buildWebCommandUri(base, EntityInfo(kind: EntityKind.select, key: 5, objectId: 'light_color', name: 'Light Color'), 'set', {'option': 'Cyan'}).toString(),
        'https://spa.example.com/select/Light%20Color/set?option=Cyan',
      );
      expect(
        buildWebCommandUri(base, EntityInfo(kind: EntityKind.button, key: 6, objectId: 'salt_test', name: 'Salt Test'), 'press').toString(),
        'https://spa.example.com/button/Salt%20Test/press',
      );
      expect(
        buildWebCommandUri(base, EntityInfo(kind: EntityKind.text, key: 7, objectId: 'note', name: 'Note'), 'set', {'value': 'hi'}).toString(),
        'https://spa.example.com/text/Note/set?value=hi',
      );
    });
  });

  group('CfAccessConfig & SavedDevice', () {
    test('empty remoteUrl stays strictly LAN-only even when build defaults exist', () {
      final cfg = CfAccessConfig.resolve(
        remoteUrl: '',
        clientId: '',
        clientSecret: '',
        defaultRemoteUrl: 'https://spa.example.com',
        defaultClientId: '00000000000000000000000000000000.access',
        defaultClientSecret: 'secret-value',
      );
      expect(cfg.hasRemoteUrl, isFalse);
      expect(cfg.hasCredentials, isFalse);
      expect(cfg.headers, isEmpty);
    });

    test('inherits build-time credentials only when remoteUrl matches defaultRemoteUrl', () {
      final matching = CfAccessConfig.resolve(
        remoteUrl: 'spa.example.com/',
        defaultRemoteUrl: 'https://spa.example.com',
        defaultClientId: '00000000000000000000000000000000.access',
        defaultClientSecret: 'secret-value',
      );
      expect(matching.remoteUrl, 'https://spa.example.com');
      expect(matching.headers, {
        'CF-Access-Client-Id': '00000000000000000000000000000000.access',
        'CF-Access-Client-Secret': 'secret-value',
      });

      final other = CfAccessConfig.resolve(
        remoteUrl: 'https://tailscale-spa.example.ts.net',
        defaultRemoteUrl: 'https://spa.example.com',
        defaultClientId: '00000000000000000000000000000000.access',
        defaultClientSecret: 'secret-value',
      );
      expect(other.remoteUrl, 'https://tailscale-spa.example.ts.net');
      expect(other.hasCredentials, isFalse);
      expect(other.headers, isEmpty);
    });

    test('detects Cloudflare Access blocks via 302 redirect or HTML login page', () {
      expect(
        isCfAccessBlockedResponse(
          statusCode: 302,
          locationHeader: 'https://example.cloudflareaccess.com/cdn-cgi/access/login/spa.example.com',
        ),
        isTrue,
      );
      expect(
        isCfAccessBlockedResponse(
          statusCode: 403,
          contentType: 'text/html',
          bodyPrefix: '<html><title>Cloudflare Access</title></html>',
        ),
        isTrue,
      );
      expect(
        isCfAccessBlockedResponse(statusCode: 200, contentType: 'text/event-stream'),
        isFalse,
      );
    });

    test('SavedDevice JSON round-trip preserves legacy and remote fields', () {
      final legacy = SavedDevice.fromJson({'id': 'hotspring', 'name': 'Hot Tub', 'host': 'hotspring.local'});
      expect(legacy.remoteUrl, '');
      expect(legacy.cfAccessClientId, '');
      expect(legacy.cfAccessClientSecret, '');
      expect(legacy.toJson().containsKey('remoteUrl'), isFalse);

      const remote = SavedDevice(
        id: 'hotspring',
        name: 'Hot Tub',
        host: 'hotspring.local',
        remoteUrl: 'https://spa.example.com',
        cfAccessClientId: 'id-1',
        cfAccessClientSecret: 'sec-1',
      );
      final back = SavedDevice.fromJson(remote.toJson());
      expect(back.remoteUrl, 'https://spa.example.com');
      expect(back.cfAccessClientId, 'id-1');
      expect(back.cfAccessClientSecret, 'sec-1');
    });
  });

  group('EspHomeClient remote integration', () {
    test('LAN-only device fails cleanly without attempting HTTP when remoteUrl is empty', () async {
      // Bind & immediately close a port so connecting to it fails immediately with connection refused.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = probe.port;
      await probe.close();

      final client = EspHomeClient(host: '127.0.0.1', port: closedPort);
      await client.connect();
      expect(client.status, ConnectionStatus.failed);
      expect(client.transport, ConnectionTransport.none);
      expect(client.isRemote, isFalse);
      client.dispose();
    });

    test('plain remote HTTPS/HTTP proxy without Cloudflare Access streams SSE and sends POST without headers', () async {
      final posts = <String>[];
      var sawCfHeader = false;
      final sseDone = Completer<void>();

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((req) async {
        if (req.headers.value('cf-access-client-id') != null ||
            req.headers.value('cf-access-client-secret') != null) {
          sawCfHeader = true;
        }
        if (req.method == 'GET' && req.uri.path == '/events') {
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType('text', 'event-stream');
          req.response.bufferOutput = false;
          req.response.write('event: ping\ndata: {"title":"hotspring"}\n\n');
          req.response.write(
              'event: state\ndata: {"id":"switch-lights","domain":"switch","name":"Lights","value":false}\n\n');
          await req.response.flush();
          await sseDone.future.timeout(const Duration(seconds: 5), onTimeout: () {});
          await req.response.close();
          return;
        }
        if (req.method == 'POST') {
          posts.add('${req.uri.path}${req.uri.hasQuery ? '?${req.uri.query}' : ''}');
          req.response.statusCode = 200;
          await req.response.close();
          return;
        }
        req.response.statusCode = 404;
        await req.response.close();
      });

      final client = EspHomeClient(remoteUrl: 'http://127.0.0.1:${server.port}');
      await client.connect();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(client.status, ConnectionStatus.connected);
      expect(client.isRemote, isTrue);
      expect(client.deviceInfo?.name, 'hotspring');
      final light = client.byObjectId('lights')!;
      expect(client.states[light.key]!.boolValue, isFalse);

      await client.setSwitch(light.key, true);
      expect(posts, ['/switch/Lights/turn_on']);
      expect(sawCfHeader, isFalse);

      sseDone.complete();
      client.dispose();
    });

    test('surfaces clear message when blocked by Cloudflare Access 302', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((req) async {
        req.response.statusCode = 302;
        req.response.headers.set('location', 'https://example.cloudflareaccess.com/cdn-cgi/access/login/spa.example.com');
        await req.response.close();
      });

      final client = EspHomeClient(remoteUrl: 'http://127.0.0.1:${server.port}');
      await client.connect();

      expect(client.status, ConnectionStatus.failed);
      expect(client.lastError, kCfAccessBlockedMessage);
      client.dispose();
    });

    test('falls back from refused local port to authenticated Cloudflare Access SSE and POST commands', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = probe.port;
      await probe.close();

      final posts = <(String, String?, String?)>[];
      final sseDone = Completer<void>();

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((req) async {
        final cid = req.headers.value('cf-access-client-id');
        final csec = req.headers.value('cf-access-client-secret');
        if (cid != 'test-id.access' || csec != 'test-secret') {
          req.response.statusCode = 302;
          req.response.headers.set('location', 'https://example.cloudflareaccess.com/cdn-cgi/access/login/spa.example.com');
          await req.response.close();
          return;
        }
        if (req.method == 'GET' && req.uri.path == '/events') {
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType('text', 'event-stream');
          req.response.bufferOutput = false;
          req.response.write('event: ping\ndata: {"title":"hotspring"}\n\n');
          req.response.write(
              'event: state\ndata: {"id":"climate-temperature","domain":"climate","name":"Temperature","mode":"HEAT","action":"IDLE","current_temperature":37.5,"target_temperature":38.5}\n\n');
          req.response.write(
              'event: state\ndata: {"id":"number-heat_up_temperature","domain":"number","name":"Heat Up Temperature","value":102}\n\n');
          await req.response.flush();
          await sseDone.future.timeout(const Duration(seconds: 5), onTimeout: () {});
          await req.response.close();
          return;
        }
        if (req.method == 'POST') {
          posts.add(('${req.uri.path}?${req.uri.query}', cid, csec));
          req.response.statusCode = 200;
          await req.response.close();
          return;
        }
        req.response.statusCode = 404;
        await req.response.close();
      });

      final client = EspHomeClient(
        host: '127.0.0.1',
        port: closedPort,
        remoteUrl: 'http://127.0.0.1:${server.port}',
        cfAccessClientId: 'test-id.access',
        cfAccessClientSecret: 'test-secret',
      );
      await client.connect();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(client.status, ConnectionStatus.connected);
      expect(client.transport, ConnectionTransport.remote);
      expect(client.isRemote, isTrue);

      final climate = client.byObjectId('temperature')!;
      final heatUp = client.byObjectId('heat_up_temperature')!;
      await client.setClimate(climate.key, target: 39.0);
      await client.setNumber(heatUp.key, 103);

      expect(posts.length, 2);
      expect(posts[0], ('/climate/Temperature/set?target_temperature=39.00', 'test-id.access', 'test-secret'));
      expect(posts[1], ('/number/Heat%20Up%20Temperature/set?value=103.0', 'test-id.access', 'test-secret'));

      sseDone.complete();
      client.dispose();
    });
  });

  group('Local Noise CF auto-provisioning & AddDeviceSheet token visibility', () {
    test('decodes ListEntitiesServicesResponse, ExecuteServiceRequest, and HomeassistantEvent', () {
      final svcProto = (ProtoWriter()
            ..string(1, 'fetch_remote_config')
            ..fixed32(2, 0x12345678))
          .toBytes();
      final svc = ApiServiceInfo.fromProto(ProtoMessage.decode(svcProto));
      expect(svc.name, 'fetch_remote_config');
      expect(svc.key, 0x12345678);

      final (reqId, reqBytes) = Requests.executeService(svc.key);
      expect(reqId, MsgId.executeServiceRequest);
      expect(ProtoMessage.decode(reqBytes).fixed32(1), 0x12345678);

      List<int> kvEntry(String k, String v) => (ProtoWriter()
            ..string(1, k)
            ..string(2, v))
          .toBytes();

      final b = BytesBuilder();
      void addEntry(String k, String v) {
        final raw = kvEntry(k, v);
        // field 2 wire type 2 => (2 << 3) | 2 = 0x12
        b.addByte(0x12);
        b.addByte(raw.length);
        b.add(raw);
      }

      final head = (ProtoWriter()
            ..string(1, 'esphome.iq2020_remote_config')
            ..boolean(5, true))
          .toBytes();
      b.add(head);
      addEntry('remote_url', 'https://spa.example.com');
      addEntry('cf_client_id', 'prov-id.access');
      addEntry('cf_client_secret', 'prov-secret');

      final ev = HomeassistantEvent.fromProto(ProtoMessage.decode(b.toBytes()));
      expect(ev.isEvent, isTrue);
      expect(ev.service, 'esphome.iq2020_remote_config');
      expect(ev.data, {
        'remote_url': 'https://spa.example.com',
        'cf_client_id': 'prov-id.access',
        'cf_client_secret': 'prov-secret',
      });
    });
  });
}
