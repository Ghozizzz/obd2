import 'package:flutter/material.dart';

import 'trip.dart';
import 'trip_store.dart';

/// History of recorded journeys: distance, fuel used and average economy per
/// trip, newest first. Reads straight from the [TripStore].
class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key, required this.store});

  final TripStore store;

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  late Future<List<Trip>> _trips;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _trips = widget.store.all();

  Future<void> _delete(Trip t) async {
    if (t.id == null) return;
    await widget.store.delete(t.id!);
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Trip History'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<List<Trip>>(
        future: _trips,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final trips = snap.data!;
          if (trips.isEmpty) return _empty();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _summary(trips),
              const SizedBox(height: 20),
              for (final t in trips) ...[
                _card(t),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.route_outlined,
                  size: 72, color: Colors.white.withOpacity(0.18)),
              const SizedBox(height: 20),
              const Text(
                'No trips yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Open Live Fuel Consumption and drive — '
                'each session is saved here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 14, height: 1.4),
              ),
            ],
          ),
        ),
      );

  /// Aggregate stats banner across every saved trip.
  Widget _summary(List<Trip> trips) {
    final distance = trips.fold<double>(0, (s, t) => s + t.distanceKm);
    final fuel = trips.fold<double>(0, (s, t) => s + t.fuelLiters);
    final avg = fuel > 0 ? distance / fuel : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.cyan.withOpacity(0.16), Colors.white10],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          _summaryStat('${trips.length}', 'trips'),
          _summaryDivider(),
          _summaryStat(distance.toStringAsFixed(0), 'km total'),
          _summaryDivider(),
          _summaryStat(avg.toStringAsFixed(1), 'avg km/L'),
        ],
      ),
    );
  }

  Widget _summaryStat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      );

  Widget _summaryDivider() => Container(
        width: 1,
        height: 36,
        color: Colors.white12,
      );

  Widget _card(Trip t) {
    final accent = _economyColor(t.avgKmPerLiter);
    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Colors.red.shade900,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _delete(t),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Economy badge.
              Container(
                width: 76,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    Text(
                      t.avgKmPerLiter.toStringAsFixed(1),
                      style: TextStyle(
                        color: accent,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text('km/L',
                        style: TextStyle(
                            color: accent.withOpacity(0.8), fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Trip details.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _date(t.startedAt),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _meta(Icons.straighten,
                            '${t.distanceKm.toStringAsFixed(1)} km'),
                        const SizedBox(width: 14),
                        _meta(Icons.local_gas_station,
                            '${t.fuelLiters.toStringAsFixed(2)} L'),
                        if (t.duration != null) ...[
                          const SizedBox(width: 14),
                          _meta(Icons.schedule, _dur(t.duration!)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${t.litersPer100km.toStringAsFixed(1)}\nL/100km',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 11, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white38),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(color: Colors.white60, fontSize: 13)),
        ],
      );

  /// Green for thrifty, amber mid, red for thirsty — quick visual cue.
  static Color _economyColor(double kmPerLiter) {
    if (kmPerLiter <= 0) return Colors.white54;
    if (kmPerLiter >= 14) return Colors.greenAccent;
    if (kmPerLiter >= 9) return Colors.amberAccent;
    return Colors.redAccent;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  String _date(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)}  ${_two(d.hour)}:${_two(d.minute)}';

  String _dur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
