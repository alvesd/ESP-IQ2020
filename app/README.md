# IQ2020 Mobile

An iPhone and Android app (built with Flutter) that controls an IQ2020 hot tub **directly**
through the ESP32 running this repo's ESPHome component. It uses no Home Assistant and no cloud.

```
Phone ──Wi-Fi, TCP 6053, encrypted ESPHome native API──► ESP32 (ESPHome + iq2020) ──RS485──► spa
```

## Setup

1. Flash the ESP32 with [`../firmware/hot-tub-mobile.yaml`](../firmware/hot-tub-mobile.yaml).
   Copy `secrets.example.yaml` to `secrets.yaml` first and generate the key with
   `openssl rand -base64 32`.
2. Install Flutter (3.22 or later), then:

   ```bash
   cd app
   ORG=com.yourname ./tool/bootstrap.sh   # creates the ios/ and android/ folders and adds permissions
   flutter test
   flutter run
   ```

3. In the app, pick the hot tub under **Found on this network** (or add it by IP address) and paste the
   API encryption key.

## Code layout

| Path | Purpose |
|---|---|
| `lib/api/noise.dart` | The `Noise_NNpsk0_25519_ChaChaPoly_SHA256` encrypted handshake and the per-message ciphers. |
| `lib/api/protobuf.dart` | A small hand-written protobuf codec, so no code generation (protoc) is needed. |
| `lib/api/messages.dart` | API message IDs and field numbers, entity and state models, and command builders. |
| `lib/api/esphome_client.dart` | The connection: TCP, message framing, handshake, ping keepalive, automatic reconnect, entity/state store, and commands. |
| `lib/device_store.dart` | Saved spas (stored in the Keychain/Keystore) and mDNS discovery of `_esphomelib._tcp`. |
| `lib/ui/` | The screens. They're built from the entity list the device reports, so they adapt to each hot tub's features. |

## Checking the protocol against a real device

`flutter test` only proves the Dart client is consistent with itself. To check the device side
on its own, use the official Python client:

```bash
pip install aioesphomeapi
aioesphomeapi-logs --noise-psk '<key>' hot-tub.local
```

If that connects but the app doesn't, the bug is in the Dart client, not in the firmware.

## Roadmap

- QR-code pairing (encode `host` and `key` as a QR code when flashing).
- Wi-Fi setup over Bluetooth (`esp32_improv` in the firmware plus an Improv BLE client in the app).
- Remote access (see the root CLAUDE.md for the options).
