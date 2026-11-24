---
name: apppush
description: >
  One-shot release of the IQ2020 Spa app: commit the working tree, push, merge the work
  into `mobile-app`, bump the build number, then ship iOS to TestFlight and Android to
  Google Play Internal testing. Trigger on: "apppush", "commit and ship", "push and deploy
  the app", "release to the stores". NOT for the ESP32 firmware (`firmwarepush`).
disable-model-invocation: true
---

# AppPush — commit, push, merge, ship

Repo `alvesd/ESP-IQ2020`, release branch **`mobile-app`**, Flutter app in `app/`.
Bundle/package `com.alvesd.iq2020Mobile`. Never touch `upstream` (Ylianst/ESP-IQ2020):
never push or open PRs there.

## 1. Gate

```bash
cd app && flutter analyze && flutter test
```

Stop on any error, warning or failing test (the existing `deprecated_member_use` infos for
`package:flutter/material.dart` are known and allowed). Look at `git status` and the diff
first; never stage `key.properties`, keystores, `.p8`/`.p12`, `firmware/secrets.yaml` or
build output. The secretguard hook backs this up; never bypass it.

## 2. Commit and push

- Stage only the intended files by name (not `git add -A`). One commit with a message that
  says what changed for the user, ending with the session's attribution trailer.
- On `mobile-app`: `git push origin mobile-app`.
- On another branch: `git push -u origin <branch>`, then go to step 3.

## 3. Merge into `mobile-app`

Only when the work is on a branch other than `mobile-app`:

```bash
gh pr create --repo alvesd/ESP-IQ2020 --base mobile-app --head <branch> --fill
gh pr merge --repo alvesd/ESP-IQ2020 <PR#> --merge --delete-branch
git checkout mobile-app && git pull --ff-only origin mobile-app
```

Merge only PRs into `mobile-app` of the fork, and only the one this run created. If it has
conflicts, stop and report; don't resolve them silently.

## 4. Bump the build number

`app/pubspec.yaml` `version: X.Y.Z+N` → `+N+1` (both stores reject a reused N). Bump the
`X.Y.Z` part only if the owner asks. Commit the bump on `mobile-app` ("Bump build to N+1")
and push it.

## 5. iOS → TestFlight

```bash
cd app && flutter build ios --release --no-codesign
cd app/ios && xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Release \
  -destination generic/platform=iOS -archivePath ../build/ios/archive/Runner.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO archive
cd app && rm -rf build/ios/upload && xcodebuild -exportArchive \
  -archivePath build/ios/archive/Runner.xcarchive -exportPath build/ios/upload \
  -exportOptionsPlist ios/ExportOptionsUpload.plist -allowProvisioningUpdates
```

Use `-destination`, not `-sdk iphoneos`: the archive embeds the Apple Watch app
(`IQ2020Watch`), and forcing the iPhone SDK makes its build fail ("app icon set … did not have
any applicable content"). Check `Runner.app/Watch/IQ2020Watch.app` is in the archive and its
`CFBundleVersion` matches the iPhone app's.

Success = "Upload succeeded" / "EXPORT SUCCEEDED". Processing takes 5–15 min; the owner
answers export compliance in App Store Connect. The Internal TestFlight group gets it
automatically.

## 6. Android → Play Internal testing

```bash
cd app && flutter build appbundle --release
/opt/homebrew/opt/openjdk@17/bin/keytool -printcert -jarfile \
  build/app/outputs/bundle/release/app-release.aab | grep Owner   # CN=Alves, not "Android Debug"
```

Never print `key.properties`. Upload in Chrome (Play Console account **Alvesd**,
`/console/u/1/`), IQ2020 Spa → Test and release → Internal testing → Create new release:

1. The `.aab` (~51 MB) is too big for a direct tool upload. Copy it to an empty scratch folder
   and serve it on `127.0.0.1:8765` with a tiny Python server that adds
   `Access-Control-Allow-Origin: *` and `Access-Control-Allow-Private-Network: true` (run it in
   the background; stop it afterwards).
2. In the page: `fetch('http://127.0.0.1:8765/app-release.aab', {targetAddressSpace:'loopback'})`
   → `File` → `DataTransfer` → set it on `input[type=file][accept=".aab"]` and dispatch one
   `change` event (one only: a second uploads a duplicate). If Chrome asks to allow local
   network access, the owner clicks Allow.
3. Wait until the bundle row shows the new version code, then replace the release notes
   (select all, delete) with `<en-US>…</en-US>` describing the user-visible changes.
4. Next → check "Ready to release" with no errors → Save and publish → confirm.

Success = the track shows the new release "Available to internal testers".

The Wear OS app (`wear/`, same package, version code 100000+N) is not shipped by this skill
until the Wear OS form factor is enabled for the listing in Play Console; then build it with
`cd wear && flutter build appbundle --release` and add it to a Wear OS release.
Opt-in link: https://play.google.com/apps/internaltest/4699945925693455410

## Safety

- Never interact with the live hot tub while testing a build: no taps or swipes that start on
  the dial, −/+, switches, sliders or buttons. Scroll only by slow drags from headings/empty
  space, or use screenshots. If something changes by accident, say so at once and restore it.
- This publishes to testers. Production (App Store review / Play production) is never done by
  this skill; Play production also needs a 12-tester, 14-day closed test first.

## Report

Commit SHA(s), PR (if any), version shipped, and per store: uploaded / processing /
available, with the tester link.
