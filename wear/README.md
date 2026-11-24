# IQ2020 Spa for Wear OS

A one-screen watch app: water and target temperature (−/+), heater state, jets and lights,
salt level zone. It connects to the hot tub's ESPHome API itself over Wi-Fi, reusing the phone
app's client from `../app` (path dependency), so it works without the phone.

```bash
flutter build apk --debug                      # build/app/outputs/flutter-apk/app-debug.apk
flutter build appbundle --release              # Play: Wear OS form factor of the same listing
```

Same `applicationId` as the phone app (`com.alvesd.iq2020Mobile`); Gradle adds 100000 to the
build number so the watch's version code never collides with the phone's.
