---
name: prodpush
description: >
  Release the IQ2020 Spa apps for this repo (`alvesd/ESP-IQ2020`, branch `mobile-app`):
  gate, commit/PR/merge into `mobile-app`, bump build numbers, ship iOS (+ watchOS) to
  TestFlight, and ship Android phone + Wear OS builds to Google Play Store Internal testing.
  Trigger on: "prodpush", "prod push", "release to prod", "ship to stores". NOT for ESP32
  firmware (`firmwarepush`) and NOT Docker/SSH server deploys (this repo has no backend server).
---

# ProdPush — IQ2020 Spa (TestFlight + Google Play Store Internal testing)

Repo `alvesd/ESP-IQ2020`, release branch **`mobile-app`**, Flutter phone app in `app/` (with embedded watchOS app `app/ios/IQ2020Watch`) and Wear OS app in `wear/`. Bundle/package `com.alvesd.iq2020Mobile`. Never touch `upstream` (`Ylianst/ESP-IQ2020`): never push or open PRs there.

This repo has no backend server or Docker stack. Android distribution uses **Google Play Store Internal testing** (signed `.aab` uploads for both Phone and Wear OS tracks), not EAS and not sideload APKs.

## 1. Gate

```bash
cd app && flutter analyze && flutter test
cd wear && flutter analyze
```

Stop on any error, warning, or failing test (the existing `deprecated_member_use` infos for `package:flutter/material.dart` are known and allowed). Inspect `git status` and `git diff` first; never stage `key.properties`, keystores, `.p8`/`.p12`, `firmware/secrets.yaml`, or build output. Never bypass the secretguard hook.

## 2. Commit, push, and merge into `mobile-app`

- Stage only the intended files by name (never `git add -A`).
- If working on a feature branch (or when a PR is requested):
  ```bash
  git push -u origin <branch>
  gh pr create --repo alvesd/ESP-IQ2020 --base mobile-app --head <branch> --fill
  gh pr merge --repo alvesd/ESP-IQ2020 <PR#> --merge --delete-branch
  git checkout mobile-app && git pull --ff-only origin mobile-app
  ```
- If already on `mobile-app` with no PR requested: `git push origin mobile-app`.
- Never merge into `upstream`, and if a PR has merge conflicts, stop and report.

## 3. Bump the build number

- Bump `version: X.Y.Z+N` → `+N+1` in **both** `app/pubspec.yaml` and `wear/pubspec.yaml` (both TestFlight and Google Play reject a reused build number / version code; Wear Gradle adds `100000 + N`).
- Run `cd wear && flutter pub get` so `wear/pubspec.lock` records the new `iq2020_mobile` version.
- Commit (`"Bump build to N+1"`) and push on `mobile-app`.

## 4. iOS (+ watchOS) → TestFlight

Prereq: Xcode is signed in to your Apple Developer team (`JBD3U73AKM`). Public App Store / Play Store builds must omit `--dart-define-from-file=cf_access.local.json` so personal URLs or tokens are never compiled into public binaries.

```bash
cd app && flutter build ios --release --no-codesign
cd app/ios && xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Release \
  -destination generic/platform=iOS -archivePath ../build/ios/archive/Runner.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO archive
cd app && rm -rf build/ios/upload && xcodebuild -exportArchive \
  -archivePath build/ios/archive/Runner.xcarchive -exportPath build/ios/upload \
  -exportOptionsPlist ios/ExportOptionsUpload.plist -allowProvisioningUpdates
```

- Always use `-destination generic/platform=iOS` (never `-sdk iphoneos`) so the embedded Apple Watch app (`IQ2020Watch.app`) builds cleanly.
- Verify `Runner.xcarchive/Products/Applications/Runner.app/Watch/IQ2020Watch.app` is present and its `CFBundleVersion` matches the iPhone app's build number.
- Success = `EXPORT SUCCEEDED` / `Upload succeeded`. Processing takes ~5–15 min; the owner completes export compliance in App Store Connect.

## 5. Android Phone → Google Play Store Internal testing

Prereq: git-ignored `app/android/key.properties` points to `~/.android-keys/iq2020-upload.jks`. Never print `key.properties` or passwords.

```bash
cd app && flutter build appbundle --release
/opt/homebrew/opt/openjdk@17/bin/keytool -printcert -jarfile \
  app/build/app/outputs/bundle/release/app-release.aab | grep Owner   # must be CN=Alves, not "Android Debug"
```

Upload to **Google Play Console** (account **Alvesd**, `/console/u/1/`): **IQ2020 Spa → Test and release → Testing → Internal testing → Create new release**:

1. Because the `.aab` (~51 MB) exceeds direct browser-tool upload limits, copy it to an empty scratch folder and serve on `127.0.0.1:8765` with `Access-Control-Allow-Origin: *` and `Access-Control-Allow-Private-Network: true` (stop the server afterwards), OR have the owner drag it into the Play Console upload zone.
2. In the page, fetch `http://127.0.0.1:8765/app-release.aab` (`{targetAddressSpace: 'loopback'}`) → `File` → `DataTransfer` → assign to `input[type=file][accept=".aab"]` and dispatch **one** `change` event.
3. Wait until the bundle table shows version code `N+1`, replace release notes with `<en-US>…</en-US>`, click Next → verify "Ready to release" with no errors → Save and publish → confirm.

Success = track shows the new release **Available to internal testers**.

## 6. Wear OS → Google Play Store Wear OS Internal testing

```bash
cd wear && flutter build appbundle --release
/opt/homebrew/opt/openjdk@17/bin/keytool -printcert -jarfile \
  wear/build/app/outputs/bundle/release/app-release.aab | grep Owner   # must be CN=Alves, not "Android Debug"
```

Upload to **Google Play Console** on the **Wear OS only** form-factor Internal testing track (`tracks/internal-testing?releaseType=wear`), version code `100000 + (N+1)`:

- Verify the camera feature is marked `uses-feature-not-required` (`aapt2 dump badging` or bundle manifest check) and confirm on the Play review page's **Wearable** row that "Devices no longer supported" is `0`.
- After publishing, expand the release summary and verify **Version codes** shows `100000 + (N+1)`.

Tester opt-in link: https://play.google.com/apps/internaltest/4699945925693455410

## Safety

- Never interact with the live hot tub while testing a build.
- Never publish to Play production or App Store review from this skill (Internal testing / TestFlight only).

## Report

Commit SHA(s), PR (if any), version shipped (`0.1.0+N` / Wear `100000+N`), and per store status: uploaded / processing / available, with tester link.
