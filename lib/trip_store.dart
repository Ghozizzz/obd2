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

  Future<void> close() => _db.close();
}
