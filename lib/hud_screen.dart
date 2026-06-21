import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'hud_view.dart';
import 'obd_service.dart';
import 'obd_settings.dart';
import 'trip_recorder.dart';
import 'trip_store.dart';

/// Full-screen HUD. White-on-black, big km/L readout, throttle bar that lights
/// up when you press the pedal. Optionally mirrored (flipped horizontally) so
/// the HUD reads correctly when reflected off the windshield.
///
/// Connection is owned by the home screen; this screen only renders the live
/// snapshots from the [service] it is handed.
class HudScreen extends StatefulWidget {
  const HudScreen({
    super.key,
    required this.service,
    required this.settings,
    this.tripStore,
  });

  final ObdService service;
  final ObdSettings settings;

  /// When provided, the whole HUD session is recorded as one trip. Null in
  /// previews / when history is unavailable.
  final TripStore? tripStore;

  @override
  State<HudScreen> createState() => _HudScreenState();
}

class _HudScreenState extends State<HudScreen> {
  TripRecorder? _recorder;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // keep screen on while driving
    final store = widget.tripStore;
    if (store != null) {
      final recorder = TripRecorder(store);
      _recorder = recorder;
      // Records by riding the existing service stream — no extra polling.
      recorder.start(widget.service.stream);
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _recorder?.stop(); // finalise the trip when leaving the HUD
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Transform(
              alignment: Alignment.center,
              // Flip horizontally when mirroring is enabled.
              transform: Matrix4.diagonal3Values(
                  settings.mirror ? -1.0 : 1.0, 1.0, 1.0),
              child: StreamBuilder<ObdData>(
                stream: widget.service.stream,
                initialData: widget.service.current,
                builder: (context, snap) {
                  final d = snap.data ?? const ObdData();
                  return _body(d);
                },
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white38),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
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
            const Text('Connection lost…',
                style: TextStyle(color: Colors.white70, fontSize: 22)),
            if (d.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(d.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
          ],
        ),
      );
    }

    return HudView(
      data: d,
      template: widget.settings.template,
      color: Color(widget.settings.hudColor),
    );
  }
}
