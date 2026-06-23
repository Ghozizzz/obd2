import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hud_view.dart';
import 'obd_service.dart';
import 'obd_settings.dart';

/// A short, connection-free preview of a HUD template. Feeds the [HudView]
/// simulated driving data so you can see how a template looks before saving.
/// Runs for [duration] (default 10 s) then pops automatically; tap anywhere
/// to exit early.
class PreviewScreen extends StatefulWidget {
  const PreviewScreen({
    super.key,
    required this.template,
    this.mirror = false,
    this.color = const Color(0xFF18FFFF), // cyanAccent
    this.duration = const Duration(seconds: 10),
  });

  final HudTemplate template;
  final bool mirror;
  final Color color;
  final Duration duration;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  static const _tick = Duration(milliseconds: 200);

  Timer? _timer;
  Duration _elapsed = Duration.zero;
  ObdData _data = const ObdData(connected: true);

  // Accumulators for a simulated session-average km/L (matches ObdService).
  double _sumSpeed = 0;
  double _sumLh = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tick, _onTick);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onTick(Timer t) {
    _elapsed += _tick;
    if (_elapsed >= widget.duration) {
      _timer?.cancel();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() => _data = _simulate(_elapsed.inMilliseconds / 1000.0));
  }

  /// Fabricate a plausible drive cycle: speed and throttle swell and ease over
  /// time, with economy moving inversely to throttle (heavy pedal → low km/L).
  ObdData _simulate(double s) {
    // 0..1 swing on a slow sine so the bar/number visibly moves.
    final wave = (math.sin(s * 0.9) + 1) / 2; // 0..1
    final throttle = 8 + wave * 70; // 8..78 %
    final speed = (20 + wave * 90).round(); // 20..110 km/h
    final rpm = (900 + wave * 3200).round(); // 900..4100 rpm
    // Light pedal → good economy; heavy pedal → poor economy.
    final kmPerLiter = (4 + (1 - wave) * 38).toDouble(); // ~4..42 km/L
    final litersPerHour = 1.2 + wave * 14; // 1.2..15 L/h

    // Distance-weighted running average, mirroring ObdService.
    _sumSpeed += speed.toDouble();
    _sumLh += litersPerHour;
    final avgKmPerLiter = _sumLh > 0 ? _sumSpeed / _sumLh : 0.0;

    return ObdData(
      connected: true,
      kmPerLiter: kmPerLiter,
      avgKmPerLiter: avgKmPerLiter,
      litersPerHour: litersPerHour,
      throttle: throttle,
      speed: speed,
      rpm: rpm,
    );
  }

  @override
  Widget build(BuildContext context) {
    final remaining =
        (widget.duration - _elapsed).inSeconds.clamp(0, 9999) + 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: SafeArea(
          child: Stack(
            children: [
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(
                    widget.mirror ? -1.0 : 1.0, 1.0, 1.0),
                child: HudView(
                    data: _data,
                    template: widget.template,
                    color: widget.color),
              ),
              // Preview banner + countdown (not mirrored, stays readable).
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'PREVIEW (simulated) · ${remaining}s · tap to exit',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
