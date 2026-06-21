import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'trip.dart';

/// SQLite-backed store for recorded [Trip]s.
///
/// Writes are deliberately rare: the recorder integrates totals in memory and
/// only checkpoints this table every so often (and once at trip end), so the
/// database is touched a handful of times per drive — not per poll.
class TripStore {
  TripStore._(this._db);

  final Database _db;

  static const _dbName = 'trips.db';
  static const _table = 'trips';

  /// Open (creating on first run) the trips database.
  static Future<TripStore> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, _dbName),
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE $_table(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          started_at INTEGER NOT NULL,
          ended_at INTEGER,
          distance_km REAL NOT NULL DEFAULT 0,
          fuel_liters REAL NOT NULL DEFAULT 0
        )
      '''),
    );
    return TripStore._(db);
  }

  /// Insert a new trip and return its assigned id.
  Future<int> insert(Trip trip) => _db.insert(_table, trip.toMap());

  /// Overwrite an existing trip row (used for checkpoints + finalising).
  Future<void> update(Trip trip) => _db.update(
        _table,
        trip.toMap(),
        where: 'id = ?',
        whereArgs: [trip.id],
      );

  Future<void> delete(int id) =>
      _db.delete(_table, where: 'id = ?', whereArgs: [id]);

  /// All trips, newest first.
  Future<List<Trip>> all() async {
    final rows = await _db.query(_table, orderBy: 'started_at DESC');
    return rows.map(Trip.fromMap).toList();
  }

  /// Number of trips currently stored.
  Future<int> count() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS n FROM $_table');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// Populate the table with a handful of demo trips so the history screen can
  /// be previewed without a live OBD session. No-op if any trips already exist,
  /// so it never clobbers real recordings. Anchored to [now] so the dates read
  /// as "recent" whenever it runs.
  Future<void> seedSampleData({DateTime? now}) async {
    if (await count() > 0) return;
    final base = now ?? DateTime.now();
    DateTime at(int daysAgo, int h, int m) =>
        DateTime(base.year, base.month, base.day - daysAgo, h, m);

    final samples = <Trip>[
      Trip(
        startedAt: at(0, 8, 12),
        endedAt: at(0, 8, 47),
        distanceKm: 23.4,
        fuelLiters: 1.62, // ~14.4 km/L — green
      ),
      Trip(
        startedAt: at(1, 18, 5),
        endedAt: at(1, 18, 52),
        distanceKm: 41.8,
        fuelLiters: 3.95, // ~10.6 km/L — amber
      ),
      Trip(
        startedAt: at(1, 7, 30),
        endedAt: at(1, 9, 6),
        distanceKm: 88.2,
        fuelLiters: 5.10, // ~17.3 km/L — green, 1h 36m
      ),
      Trip(
        startedAt: at(2, 12, 0),
        endedAt: at(2, 12, 22),
        distanceKm: 6.3,
        fuelLiters: 0.84, // ~7.5 km/L — red, short city hop
      ),
    ];
    for (final t in samples) {
      await insert(t);
    }
  }

  Future<void> close() => _db.close();
}
