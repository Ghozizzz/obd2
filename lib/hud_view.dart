import 'package:flutter/material.dart';

import 'obd_service.dart';
import 'obd_settings.dart';

/// The connected HUD readout, shared by the live [HudScreen] and the
/// no-connection [PreviewScreen]. Renders either the big km/L number
/// (Template 1) or the 0–50 km/L bar graph (Template 2), plus the throttle
/// bar and speed / L·h / rpm stats.
class HudView extends StatelessWidget {
  const HudView({
    super.key,
    required this.data,
    required this.template,
    this.color = const Color(0xFF18FFFF), // cyanAccent
  });

  final ObdData data;
  final HudTemplate template;

  /// Resting HUD accent colour (turns amber while the throttle is pressed).
  final Color color;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final accent = color;

    // Template 2: bar (0–50 km/L) + number only.
    if (template == HudTemplate.bar) {
      const maxKmL = 50.0;
      final value = (d.kmPerLiter / maxKmL).clamp(0.0, 1.0);
      final avg = (d.avgKmPerLiter / maxKmL).clamp(0.0, 1.0);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                '${d.kmPerLiter.toStringAsFixed(1)} km / L',
                style: TextStyle(
                  color: accent,
                  fontSize: 64,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 56,
                child: Stack(
                  children: [
                    // Live km/L fill.
                    LinearProgressIndicator(
                      value: value,
                      minHeight: 56,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                    // Thin marker line = session average km/L (the benchmark).
                    Align(
                      alignment: Alignment(avg * 2 - 1, 0),
                      child: Container(width: 3, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0', style: TextStyle(color: Colors.white38, fontSize: 16)),
                Text('10', style: TextStyle(color: Colors.white38, fontSize: 16)),
                Text('20', style: TextStyle(color: Colors.white38, fontSize: 16)),
                Text('30', style: TextStyle(color: Colors.white38, fontSize: 16)),
                Text('40', style: TextStyle(color: Colors.white38, fontSize: 16)),
                Text('50', style: TextStyle(color: Colors.white38, fontSize: 16)),
              ],
            ),
          ],
        ),
      );
    }

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
