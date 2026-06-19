import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'obd_service.dart';

/// Full-screen HUD. Not mirrored. White-on-black, big km/L readout,
/// throttle bar that lights up when you press the pedal.
class HudScreen extends StatefulWidget {
  const HudScreen({super.key});

  @override
  State<HudScreen> createState() => _HudScreenState();
}

class _HudScreenState extends State<HudScreen> {
  final ObdService _service = ObdService();

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // keep screen on while driving
    _service.start();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: StreamBuilder<ObdData>(
          stream: _service.stream,
          initialData: _service.current,
          builder: (context, snap) {
            final d = snap.data ?? const ObdData();
            return _body(d);
          },
        ),
      ),
    );
  }

  Widget _body(ObdData d) {
    if (!d.connected) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Connecting to ELM327…',
                style: TextStyle(color: Colors.white70, fontSize: 22)),
            if (d.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(d.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            const SizedBox(height: 8),
            const Text('Join the WiFi_OBDII network first.',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
          ],
        ),
      );
    }

    final throttlePressed = d.throttle > 5;
    final accent = throttlePressed ? Colors.amber : Colors.cyanAccent;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!d.mafSupported)
            const Text('No MAF — using speed-density estimate (QR25)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orangeAccent, fontSize: 16)),
          // Primary readout: km/L
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              d.kmPerLiter.toStringAsFixed(1),
              style: TextStyle(
                color: accent,
                fontSize: 180,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
          ),
          const Center(
            child: Text('km / L',
                style: TextStyle(color: Colors.white54, fontSize: 28)),
          ),
          const SizedBox(height: 24),
          _throttleBar(d.throttle, accent),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat('${d.speed}', 'km/h'),
              _stat(d.litersPerHour.toStringAsFixed(1), 'L/h'),
              _stat('${d.rpm}', 'rpm'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _throttleBar(double pct, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Throttle ${pct.toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.white54, fontSize: 18)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            minHeight: 18,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation(accent),
          ),
        ),
      ],
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 36, fontWeight: FontWeight.w600)),
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 16)),
      ],
    );
  }
}
