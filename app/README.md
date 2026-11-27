# IQ2020 Spa (`app/`)

An iPhone, iPad, and Android app (built with Flutter) — with an embedded Apple Watch companion in [`ios/IQ2020Watch/`](ios/IQ2020Watch/) — that controls an IQ2020 hot tub **directly** through the ESP32 running this repo's ESPHome components. It needs no Home Assistant and no cloud account.

```
Phone ──Wi-Fi, TCP 6053, encrypted ESPHome native API──► ESP32 (ESPHome + iq2020) ──RS485──► spa
      └─(optional fallback)── HTTPS / Web UI v3 SSE ────► Cloudflare Tunnel + Access ─────┘
```

## Setup

1. Flash the ESP32 with [`../firmware/hotspring.yaml`](../firmware/hotspring.yaml) (full feature set with embedded Web UI, 2-year NVS history, global presets, heating ETA, and Freshwater Salt/IQ) or [`../firmware/hot-tub-mobile.yaml`](../firmware/hot-tub-mobile.yaml) (minimal config).
   Copy [`../firmware/secrets.example.yaml`](../firmware/secrets.example.yaml) to `firmware/secrets.yaml` first and generate an encryption key with `openssl rand -base64 32`.
2. Install Flutter (3.22 or later), then:

   ```bash
   cd app
   flutter pub get
   flutter test
   flutter run
   ```

   *(Note: `ios/` and `android/` are already checked into the repository; [`tool/bootstrap.sh`](tool/bootstrap.sh) is only needed if regenerating platform folders under a new bundle ID.)*
3. In the app, pick the hot tub under **Found on this network** (or add it by IP address) and paste the API encryption key. Optionally configure a **Remote URL** (such as `https://spa.example.com`) and Cloudflare Access Service Token for away-from-home fallback.

## Code layout

| Path | Purpose |
|---|---|
| `lib/api/noise.dart` | The `Noise_NNpsk0_25519_ChaChaPoly_SHA256` encrypted handshake and the per-message ciphers. |
| `lib/api/protobuf.dart` | A small hand-written protobuf codec, so no code generation (`protoc`) is needed. |
| `lib/api/messages.dart` | API message IDs and field numbers, entity and state models, and command builders. |
| `lib/api/esphome_client.dart` | Connection transport: local Noise TCP (`6053`), automatic HTTPS `web_server` v3 SSE fallback, keepalive, reconnect, and commands. |
| `lib/api/cf_access.dart` | Remote HTTPS URL normalization and optional Cloudflare Access service token header handling. |
| `lib/device_store.dart` | Saved spas & credentials (Keychain/Keystore) and mDNS discovery of `_esphomelib._tcp`. |
| `lib/watch/` | Apple Watch `WatchRelay` headless bridge and X25519/HKDF QR-code pairing for Wear OS (`../wear/`). |
| `lib/ui/` | Adaptive tabs (Comfort, Salt, Power, Settings & History), native iOS/iPadOS/Duo tabs, and Reboot system dialog. |

## Checking the protocol against a real device

`flutter test` only proves the Dart client is consistent with itself. To check the device side on its own, use the official Python client:

```bash
pip install aioesphomeapi
aioesphomeapi-logs --noise-psk '<key>' hot-tub.local
```

If that connects but the app doesn't, the bug is in the Dart client, not in the firmware.
