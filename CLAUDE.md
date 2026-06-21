# OBD2 Fuel HUD — How It Works

A Flutter heads-up display that reads live engine data from an **ELM327** OBD-II
adapter (WiFi or Bluetooth) and shows a large **km/L** fuel-economy readout, plus
throttle, speed, L/h and RPM.

This document explains the data flow and, most importantly, **the calculation
methods** used to turn raw OBD-II PIDs into a fuel-economy number.

---

## 1. Architecture at a glance

```
ELM327 adapter (WiFi/Bluetooth)
        │  ASCII "AT"/PID commands over a byte channel
        ▼
Elm327Transport  ──────────  WifiObdTransport / BluetoothObdTransport
  (lib/obd_transport.dart)      (lib/wifi_transport.dart, bluetooth_transport.dart)
        │  send("010C") → "41 0C 1A F8"
        ▼
ObdService  (lib/obd_service.dart)
   • polls PIDs in a loop
   • decodes them (lib/pids.dart)
   • computes economy (lib/fuel_calc.dart)
   • emits ObdData snapshots on a Stream
        ▼
HudScreen  (lib/hud_screen.dart)  → big km/L display
```

| File | Responsibility |
|------|----------------|
| [obd_transport.dart](lib/obd_transport.dart) | Shared ELM327 protocol (init handshake, `>`-prompt reply framing) over an abstract byte channel |
| [wifi_transport.dart](lib/wifi_transport.dart) / [bluetooth_transport.dart](lib/bluetooth_transport.dart) | Concrete channels — both speak identical ELM327 ASCII |
| [pids.dart](lib/pids.dart) | Parse ELM327 text replies and decode mode-01 PIDs |
| [fuel_calc.dart](lib/fuel_calc.dart) | The fuel-economy math |
| [obd_service.dart](lib/obd_service.dart) | Poll loop, MAF-support detection, state stream |
| [hud_screen.dart](lib/hud_screen.dart) | Full-screen landscape HUD |
| [obd_settings.dart](lib/obd_settings.dart) | Persisted connection settings (WiFi host/port or BT device) |

---

## 2. Talking to the adapter

ELM327 adapters speak a simple ASCII protocol. On connect, the transport runs an
init handshake ([obd_transport.dart:71](lib/obd_transport.dart#L71)):

| Command | Meaning |
|---------|---------|
| `ATZ`  | reset the adapter |
| `ATE0` | echo off |
| `ATL0` | linefeeds off |
| `ATH0` | headers off (replies become `41 0C 1A F8`) |
| `ATSP0`| auto-detect the OBD protocol |

Each command is terminated with a carriage return (`\r`). A reply is considered
complete when the adapter sends its `>` prompt character; the bytes before `>`
are the response ([obd_transport.dart:40](lib/obd_transport.dart#L40)).

Only **one command may be in flight at a time**, with a 5-second timeout.

---

## 3. PIDs read and how they are decoded

All readings use **OBD-II Mode 01** (current data). A request like `010C` asks
for PID `0C`; with headers off, the reply is `41 0C <data bytes>` — `41` echoes
mode 01, then the PID byte, then data.

Decoders live in [pids.dart:63](lib/pids.dart#L63). Using the standard SAE J1979
formulas (`A` = first data byte, `B` = second):

| PID | Name | Formula | Unit |
|-----|------|---------|------|
| `0110` | MAF (mass air flow) | `(256·A + B) / 100` | g/s |
| `010D` | Vehicle speed | `A` | km/h |
| `0111` | Throttle position | `A · 100 / 255` | % |
| `010C` | Engine RPM | `(256·A + B) / 4` | rpm |
| `010B` | Intake manifold abs. pressure (MAP) | `A` | kPa |
| `010F` | Intake air temperature (IAT) | `A − 40` | °C |
| `0100` | Supported-PID bitmask | bitmask | — |

Replies that contain `NO DATA`, `SEARCHING`, `UNABLE`, `ERROR`, or `?` are
treated as null (no reading) rather than parsed.

---

## 4. The fuel-economy calculation (the core method)

All math is in [fuel_calc.dart](lib/fuel_calc.dart). The strategy is to find the
**air mass flow** into the engine, convert it to **fuel flow**, then to
**fuel volume per hour**, and finally to **distance per liter**.

### Step A — get air flow (g/s)

There are two paths depending on whether the car has a MAF sensor:

**Path 1 — MAF sensor present (preferred).**
Read PID `0110` directly. The sensor reports air mass flow in grams/second.

**Path 2 — no MAF sensor → speed-density estimate.**
Many engines (e.g. the Nissan QR25DE in the X-Trail T31, the trim this app is
tuned for) have no MAF and instead use MAP + IAT. We reconstruct air flow from
the **ideal gas law** ([fuel_calc.dart:25](lib/fuel_calc.dart#L25)):

```
air mass per intake cycle = (MAP · VE · displacement · M_air) / (R · IAT_K)
intake cycles per second   = RPM / 60 / 2          (4-stroke: 1 intake every 2 revs)

⇒  MAF (g/s) = MAP_Pa · VE · disp_m³ · M_air · RPM / (R · IAT_K · 120)
```

Constants used:

| Symbol | Value | Meaning |
|--------|-------|---------|
| VE | 0.85 | volumetric efficiency estimate |
| displacement | 2.488 L | QR25DE engine size |
| M_air | 28.97 g/mol | molar mass of air |
| R | 8.314 J/(mol·K) | universal gas constant |
| IAT_K | IAT°C + 273.15 | intake air temp in Kelvin |

> The `120` in the denominator = `60 s × 2 revs/cycle`. MAP is converted kPa→Pa
> (×1000) and displacement L→m³ (÷1000) so all units are SI before the result is
> expressed in g/s.

### Step B — air flow → fuel volume (L/h)

Gasoline burns at a fixed air-to-fuel ratio, so fuel mass = air mass / AFR.
Dividing by fuel density and scaling to an hour gives L/h
([fuel_calc.dart:17](lib/fuel_calc.dart#L17)):

```
litersPerHour = MAF(g/s) · 3600 / (AFR · density)
```

| Constant | Value | Meaning |
|----------|-------|---------|
| AFR | 14.7 | gasoline stoichiometric air/fuel ratio |
| density | 745 g/L | typical gasoline density |

Derivation:
`fuel mass flow (g/s) = MAF / AFR` → `÷ density` = L/s → `× 3600` = L/h.

### Step C — fuel volume → economy (km/L)

```
kmPerLiter = speed(km/h) / litersPerHour
```

(km/h ÷ L/h cancels the time and leaves km/L,
[fuel_calc.dart:40](lib/fuel_calc.dart#L40).)

**Idle guard:** when the vehicle is stopped (`speed ≤ 0`) economy is undefined
(would be 0/x or x/0 → infinity), so the app reports `0.0` instead of `∞` while
idling. Likewise a non-positive L/h yields `0.0`.

---

## 5. MAF-support detection

On connect, `ObdService` queries PID `0100`, a bitmask of which PIDs `01–20` the
ECU supports ([obd_service.dart:87](lib/obd_service.dart#L87)). The bit for MAF
(PID `0x10`) is checked:

```dart
mask & (1 << (32 - 0x10))   // bit 16 from the MSB
```

If MAF is supported the loop reads PID `0110`; otherwise it falls back to the
speed-density path (Step A, Path 2) using MAP + RPM + IAT. The HUD shows a small
"No MAF — using speed-density estimate (QR25)" banner in that mode.

---

## 6. The poll loop

`ObdService._loop()` ([obd_service.dart:106](lib/obd_service.dart#L106)) runs
continuously while connected. Each iteration:

1. Read speed, throttle, RPM.
2. Read MAF — or estimate it from MAP/RPM/IAT if no MAF sensor.
3. Compute `kmPerLiter` and `litersPerHour`.
4. Emit an `ObdData` snapshot on the broadcast stream.

The HUD subscribes to that stream via a `StreamBuilder` and repaints on every
snapshot. A wakelock keeps the screen on while driving.

---

## 7. Worked example

Cruising with a MAF reading of **6 g/s** at **90 km/h**:

```
litersPerHour = 6 × 3600 / (14.7 × 745) = 21600 / 10951.5 ≈ 1.97 L/h
kmPerLiter    = 90 / 1.97 ≈ 45.7 km/L
```

(High because steady highway cruise needs little fuel; city/acceleration figures
are much lower.)

---

## 8. Accuracy notes & assumptions

- **AFR is fixed at 14.7.** Real engines run rich under load (lower AFR → more
  fuel), so economy can read optimistically during hard acceleration. Reading
  short/long-term fuel trim (PIDs `06`/`07`) would refine this.
- **Density 745 g/L** assumes gasoline; diesel/E85 differ.
- **Speed-density path is an estimate.** VE = 0.85 is a constant; real VE varies
  with RPM and load, so the no-MAF path is less accurate than a true MAF sensor.
- Constants are tuned for the **Nissan QR25DE (2.488 L)** — change
  `displacementL`, `ve`, `afr`, and `density` in
  [fuel_calc.dart](lib/fuel_calc.dart) for other engines/fuels.
