import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'hud_view.dart';
import 'obd_service.dart';
import 'obd_settings.dart';
import 'settings_screen.dart';

/// Full-screen HUD. White-on-black, big km/L readout, throttle bar that lights
/// up when you press the pedal. Optionally mirrored (flipped horizontally) so
/// the HUD reads correctly when reflected off the windshield.
class HudScreen extends StatefulWidget {
  const HudScreen({super.key});

  @override
  State<HudScreen> createState() => _HudScreenState();
}

class _HudScreenState extends State<HudScreen> {
  ObdSettings? _settings;
  ObdService? _service;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // keep screen on while driving
    _boot();
  }

  Future<void> _boot() async {
    final settings = await ObdSettings.load();
    final service = ObdService(settings.buildTransport());
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _service = service;
    });
    service.start();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _service?.dispose();
    super.dispose();
  }

  Future<void> _openSettings() async {
    final current = _settings;
    final service = _service;
    if (current == null || service == null) return;
    final updated = await Navigator.of(context).push<ObdSettings>(
      MaterialPageRoute(builder: (_) => SettingsScreen(settings: current)),
    );
    if (updated == null) return;
    await updated.save();
    if (!mounted) return;
    setState(() => _settings = updated);
    // Reconnect with the newly chosen transport.
    await service.restart(updated.buildTransport());
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (service == null)
              const Center(child: CircularProgressIndicator())
            else
              Transform(
                alignment: Alignment.center,
                // Flip horizontally when mirroring is enabled.
                transform: Matrix4.diagonal3Values(
                    _settings?.mirror == true ? -1.0 : 1.0, 1.0, 1.0),
                child: StreamBuilder<ObdData>(
                  stream: service.stream,
                  initialData: service.current,
                  builder: (context, snap) {
                    final d = snap.data ?? const ObdData();
                    return _body(d);
                  },
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.settings, color: Colors.white38),
                onPressed: _openSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(ObdData d) {
    if (!d.connected) {
      final isBt = _settings?.type == ConnectionType.bluetooth;
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
            Text(
                isBt
                    ? 'Pair the ELM327 in Bluetooth settings, then pick it in ⚙.'
                    : 'Join the WiFi_OBDII network first.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 14)),
          ],
        ),
      );
    }

    return HudView(
      data: d,
      template: _settings?.template ?? HudTemplate.number,
      color: Color(_settings?.hudColor ?? ObdSettings.defaultHudColor),
    );
  }
}
