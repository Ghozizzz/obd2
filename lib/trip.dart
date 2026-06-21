/// One recorded journey: a single "Live Fuel Consumption" session.
///
/// Only running totals are stored (distance + fuel). Average economy is derived
/// on read, so there is nothing to keep in sync. Times are stored as epoch
/// milliseconds in SQLite and exposed here as [DateTime].
class Trip {
  Trip({
    this.id,
    required this.startedAt,
    this.endedAt,
    this.distanceKm = 0,
    this.fuelLiters = 0,
  });

  /// Row id (null until inserted).
  final int? id;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// Distance travelled this trip, integrated from speed (km).
  final double distanceKm;

  /// Fuel burned this trip, integrated from L/h (litres).
  final double fuelLiters;

  /// Whole-trip economy. 0 when no fuel has been counted yet (avoids ∞).
  double get avgKmPerLiter => fuelLiters > 0 ? distanceKm / fuelLiters : 0;

  /// L/100km — the more intuitive figure for city driving.
  double get litersPer100km => distanceKm > 0 ? fuelLiters / distanceKm * 100 : 0;

  Duration? get duration =>
      endedAt == null ? null : endedAt!.difference(startedAt);

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt?.millisecondsSinceEpoch,
        'distance_km': distanceKm,
        'fuel_liters': fuelLiters,
      };

  static Trip fromMap(Map<String, Object?> m) => Trip(
        id: m['id'] as int?,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
        endedAt: m['ended_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['ended_at'] as int),
        distanceKm: (m['distance_km'] as num).toDouble(),
        fuelLiters: (m['fuel_liters'] as num).toDouble(),
      );
}
