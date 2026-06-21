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
      appBar: AppBar(title: const Text('Trip History')),
      body: FutureBuilder<List<Trip>>(
        future: _trips,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final trips = snap.data!;
          if (trips.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No trips yet.\nOpen Live Fuel Consumption and drive — '
                  'each session is saved here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: trips.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _tile(trips[i]),
          );
        },
      ),
    );
  }

  Widget _tile(Trip t) {
    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade900,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _delete(t),
      child: ListTile(
        title: Text(
          '${t.avgKmPerLiter.toStringAsFixed(1)} km/L',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        subtitle: Text(
          '${_date(t.startedAt)}  ·  '
          '${t.distanceKm.toStringAsFixed(1)} km  ·  '
          '${t.fuelLiters.toStringAsFixed(2)} L'
          '${t.duration == null ? '' : '  ·  ${_dur(t.duration!)}'}',
        ),
        trailing: Text(
          '${t.litersPer100km.toStringAsFixed(1)}\nL/100km',
          textAlign: TextAlign.right,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  String _date(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

  String _dur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
