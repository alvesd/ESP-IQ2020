# Privacy Policy — IQ2020 Spa

*Last updated: November 27, 2026*

**IQ2020 Spa** is an open-source companion app for ESPHome-based Watkins / Hot Spring IQ2020 hot tub controllers ([ESP-IQ2020](https://github.com/alvesd/ESP-IQ2020)).

## Data Not Collected

The developer **does not collect, store, track, sell, or share** any personal data, usage analytics, crash telemetry, location history, or advertising identifiers from IQ2020 Spa on iOS, iPadOS, watchOS, Android, or Wear OS.

## Local & User-Configured Connections

- **Local Network Discovery & Control:** On your local Wi-Fi network, the app discovers your ESP32 controller via mDNS (`_esphomelib._tcp`) and communicates directly with it over the Noise-encrypted ESPHome Native API.
- **Optional Remote HTTPS Access:** If you configure an optional remote HTTPS URL (such as your own Cloudflare Tunnel endpoint), the app connects directly to the server address you enter.

## On-Device Storage

Connection profiles, ESPHome API encryption keys, and any optional Cloudflare Access service tokens you configure or provision are stored **only on your own devices** (in the iOS Keychain, Android Keystore, and encrypted paired watch storage). They are never transmitted to the developer or any third party.

## Changes & Support

If you have questions or need support, please open an issue at:
https://github.com/alvesd/ESP-IQ2020/issues
