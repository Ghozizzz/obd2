import 'dart:async';

import 'obd_service.dart';
import 'trip.dart';
import 'trip_store.dart';

/// Records one journey by integrating the live [ObdData] stream into running
/// distance + fuel totals, then persisting them.
///
/// Power strategy: this adds *no* polling — it rides the snapshots the HUD is
/// already receiving. Totals live in memory; SQLite is written only on a slow
/// checkpoint timer (and once at [stop]), so a crash loses at most one
/// checkpoint interval, not the whole drive.
class TripRecorder {
  TripRecorder(this._store);

  final TripStore _store;

  /// Discard samples spaced further apart than this — a big gap means the app
  /// was backgrounded or the link dropped, and integrating across it would
  /// invent phantom distance/fuel.
  static const _maxGap = Duration(seconds: 5);

  /// How often to flush the running totals to disk (crash safety).
  static const _checkpointEvery = Duration(seconds: 20);

  /// Below these, a trip is treated as an accidental tap and not kept.
  static const _minDistanceKm = 0.1;
  static const _minFuelL = 0.01;

  StreamSubscription<ObdData>? _sub;
  Timer? _checkpoint;

  int? _id;
  DateTime? _startedAt;
  DateTime? _lastTick;
  double _distanceKm = 0;
  double _fuelLiters = 0;
  bool _dirty = false;

  /// Begin a new trip. [stream] is the live service stream.
  Future<void> start(Stream<ObdData> stream) async {
    if (_id != null) return; // already recording
    _startedAt = DateTime.now();
    _distanceKm = 0;
    _fuelLiters = 0;
    _lastTick = null;
    _dirty = false;
    _id = await _store.insert(Trip(startedAt: _startedAt!));
    _sub = stream.listen(_onData);
    _checkpoint = Timer.periodic(_checkpointEvery, (_) => _flush());
  }

  void _onData(ObdData d) {
    final now = DateTime.now();
    final last = _lastTick;
    // Only integrate while connected and across a sane time step.
    if (last != null && d.connected) {
      final dt = now.difference(last);
      if (dt > Duration.zero && dt < _maxGap) {
        final hours = dt.inMilliseconds / 3600000.0;
        _fuelLiters += d.litersPerHour * hours; // L/h × h = L
        _distanceKm += d.speed * hours; // km/h × h = km
        _dirty = true;
      }
    }
    _lastTick = now;
  }

  /// Write the current totals if anything changed since the last write.
  Future<void> _flush({DateTime? endedAt}) async {
    final id = _id;
    if (id == null || (!_dirty && endedAt == null)) return;
    _dirty = false;
    await _store.update(Trip(
      id: id,
      startedAt: _startedAt!,
      endedAt: endedAt,
      distanceKm: _distanceKm,
      fuelLiters: _fuelLiters,
    ));
  }

  /// End the trip: stop listening, write final totals, and drop the row if the
  /// journey was too short to be meaningful. Returns the saved [Trip], or null
  /// if it was discarded / never started.
  Future<Trip?> stop() async {
    final id = _id;
    if (id == null) return null;
    await _sub?.cancel();
    _checkpoint?.cancel();
    _sub = null;
    _checkpoint = null;

    if (_distanceKm < _minDistanceKm && _fuelLiters < _minFuelL) {
      await _store.delete(id);
      _id = null;
      return null;
    }

    final trip = Trip(
      id: id,
      startedAt: _startedAt!,
      endedAt: DateTime.now(),
      distanceKm: _distanceKm,
      fuelLiters: _fuelLiters,
    );
    await _store.update(trip);
    _id = null;
    return trip;
  }
}
