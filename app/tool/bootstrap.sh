#!/usr/bin/env bash
# Generates the ios/ and android/ platform folders (not committed until first run) and applies
# the permissions the app needs for LAN access + mDNS. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

ORG="${ORG:-com.example}"

if [ ! -d ios ] || [ ! -d android ]; then
  flutter create --org "$ORG" --project-name iq2020_mobile --platforms ios,android .
  # flutter create adds a counter-app widget test that doesn't match this app.
  rm -f test/widget_test.dart
fi
flutter pub get

# --- iOS: local network prompt + Bonjour service type (required for mDNS + TCP on iOS 14+) ---
PLIST=ios/Runner/Info.plist
PB=/usr/libexec/PlistBuddy
if ! $PB -c 'Print :NSLocalNetworkUsageDescription' "$PLIST" >/dev/null 2>&1; then
  $PB -c 'Add :NSLocalNetworkUsageDescription string "Finds and controls your hot tub on your home Wi-Fi."' "$PLIST"
fi
if ! $PB -c 'Print :NSBonjourServices' "$PLIST" >/dev/null 2>&1; then
  $PB -c 'Add :NSBonjourServices array' "$PLIST"
  $PB -c 'Add :NSBonjourServices:0 string _esphomelib._tcp' "$PLIST"
fi

# --- Android: network + multicast permissions ---
MANIFEST=android/app/src/main/AndroidManifest.xml
for perm in INTERNET ACCESS_NETWORK_STATE ACCESS_WIFI_STATE CHANGE_WIFI_MULTICAST_STATE; do
  if ! grep -q "android.permission.$perm" "$MANIFEST"; then
    sed -i '' "s#<application#<uses-permission android:name=\"android.permission.$perm\"/>\n    <application#" "$MANIFEST"
  fi
done

echo "Platform folders ready. Run: flutter test && flutter run"
