# OBD2 Fuel HUD — Nissan X-Trail T31

Live **km/L** fuel-economy HUD for Android, talking to an **ELM327 WiFi** adapter.
Shows instantaneous economy, throttle, speed, L/h, RPM. Not mirrored.

## How it works

- Joins the adapter's WiFi (`WiFi_OBDII`, host `192.168.0.10:35000`).
- Polls OBD-II PIDs over a TCP socket.
- Computes fuel economy from **MAF** (PID `0110`):
  - `L/h = MAF(g/s) * 3600 / (14.7 * 745)`
  - `km/L = speed / (L/h)`

## Setup

These `lib/` files are the app. Generate the platform shells around them:

```bash
flutter create --org com.yourname --project-name obd2_hud .
# overwrite lib/main.dart etc. with the files here, keep this pubspec.yaml
flutter pub get
flutter run
```

### Android permissions

Add to `android/app/src/main/AndroidManifest.xml` inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

Android 9+ blocks cleartext sockets by default. The ELM327 is a raw TCP host,
so allow it. In `<application ... android:usesCleartextTraffic="true">`.

## MAF vs speed-density (automatic)

Some T31 trims report MAP, not MAF. On connect the app reads `0100`:

- **MAF present** → uses PID `0110` directly.
- **MAF absent** → automatically falls back to a **speed-density** estimate
  from MAP `010B` + RPM `010C` + IAT `010F`, tuned for the **QR25DE 2.5L**
  (displacement 2.488 L, VE 0.85). HUD shows a "speed-density estimate" note.

Speed-density airflow (ideal gas, 4-stroke):

```
g/s = MAP_Pa * VE * disp_m³ * 28.97 * RPM / (8.314 * IAT_K * 120)
```

Constants live in [lib/fuel_calc.dart](lib/fuel_calc.dart). If economy reads
high/low under load, tune `ve` (0.80–0.95) to match real fuel-up numbers.

## Tuning

- `FuelCalc.afr` / `FuelCalc.density` in [lib/fuel_calc.dart](lib/fuel_calc.dart) — adjust if running E10 etc.
- Poll is sequential (one command in flight). T31 single-PID round-trip over
  WiFi ELM327 ≈ 50–100 ms, so ~3–5 full updates/sec. Good enough for a HUD.

## Files

| File | Role |
|------|------|
| [lib/obd_connection.dart](lib/obd_connection.dart) | TCP socket + ELM327 AT handshake |
| [lib/pids.dart](lib/pids.dart) | PID command strings + reply parsing/decoders |
| [lib/fuel_calc.dart](lib/fuel_calc.dart) | MAF → L/h → km/L math |
| [lib/obd_service.dart](lib/obd_service.dart) | Poll loop, MAF-support check, state stream |
| [lib/hud_screen.dart](lib/hud_screen.dart) | Black HUD UI, throttle bar |
| [lib/main.dart](lib/main.dart) | Landscape fullscreen bootstrap |
