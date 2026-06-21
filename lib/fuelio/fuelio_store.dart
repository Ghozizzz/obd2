import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'fuelio_csv.dart';
import 'fuelio_models.dart';

/// Outcome of importing a [FuelioBackup]: how many rows were newly inserted vs
/// skipped as already-present duplicates, per section.
class ImportResult {
  ImportResult();

  int logsAdded = 0, logsSkipped = 0;
  int costsAdded = 0, costsSkipped = 0;
  int categoriesAdded = 0;
  int costCategoriesAdded = 0;

  int get totalAdded =>
      logsAdded + costsAdded + categoriesAdded + costCategoriesAdded;
}

/// SQLite store for the Fuelio logbook: fuel fill-ups, costs, cost categories
/// and trip categories. Independent of [TripStore] (separate database file).
class FuelioStore {
  FuelioStore._(this._db);

  final Database _db;

  static const _dbName = 'fuelio.db';

  static Future<FuelioStore> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, _dbName),
      // v2 added the `vehicle` table — _createTables is idempotent so
      // onUpgrade simply runs it to add anything missing on older installs.
      version: 2,
      onCreate: (db, _) => _createTables(db),
      onUpgrade: (db, _, __) => _createTables(db),
    );
    final store = FuelioStore._(db);
    await store._seedDefaultCategories();
    return store;
  }

  /// Create every table if absent. Safe to run on a fresh or existing database.
  static Future<void> _createTables(Database db) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS fuel_log(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date INTEGER NOT NULL,
            odo REAL NOT NULL DEFAULT 0,
            fuel REAL NOT NULL DEFAULT 0,
            full INTEGER NOT NULL DEFAULT 0,
            price REAL NOT NULL DEFAULT 0,
            city TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            tank_number INTEGER NOT NULL DEFAULT 1,
            fuel_type INTEGER NOT NULL DEFAULT 0,
            volume_price REAL NOT NULL DEFAULT 0,
            missed INTEGER NOT NULL DEFAULT 0,
            guid TEXT,
            unique_id INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS cost_categories(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            priority INTEGER NOT NULL DEFAULT 0,
            color TEXT NOT NULL DEFAULT '',
            guid TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS costs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            date INTEGER NOT NULL,
            odo REAL NOT NULL DEFAULT 0,
            cost_type_id INTEGER NOT NULL DEFAULT 1,
            notes TEXT NOT NULL DEFAULT '',
            cost REAL NOT NULL DEFAULT 0,
            is_income INTEGER NOT NULL DEFAULT 0,
            guid TEXT,
            unique_id INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS trip_categories(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            guid TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS vehicle(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL DEFAULT '',
            description TEXT NOT NULL DEFAULT '',
            dist_unit INTEGER NOT NULL DEFAULT 0,
            fuel_unit INTEGER NOT NULL DEFAULT 0,
            consumption_unit INTEGER NOT NULL DEFAULT 3,
            import_date_format TEXT NOT NULL DEFAULT 'yyyy-MM-dd',
            vin TEXT NOT NULL DEFAULT '',
            insurance TEXT NOT NULL DEFAULT '',
            plate TEXT NOT NULL DEFAULT '',
            make TEXT NOT NULL DEFAULT '',
            model TEXT NOT NULL DEFAULT '',
            year TEXT NOT NULL DEFAULT '',
            tank_count INTEGER NOT NULL DEFAULT 1,
            tank1_type INTEGER NOT NULL DEFAULT 100,
            tank2_type INTEGER NOT NULL DEFAULT 0,
            active INTEGER NOT NULL DEFAULT 1,
            tank1_capacity REAL NOT NULL DEFAULT 0,
            tank2_capacity REAL NOT NULL DEFAULT 0,
            fuel_unit_tank2 INTEGER NOT NULL DEFAULT 0,
            fuel_consumption_tank2 INTEGER NOT NULL DEFAULT 0,
            guid TEXT
          )
        ''');
  }

  /// Ensure there is always at least one cost category and the Private/Work
  /// trip categories, so the CRUD screens work before any import.
  Future<void> _seedDefaultCategories() async {
    if (await _count('cost_categories') == 0) {
      const defaults = {
        1: 'Service',
        2: 'Maintenance',
        4: 'Registration',
        5: 'Parking',
        6: 'Wash',
        7: 'Tolls',
        8: 'Tickets/Fines',
        9: 'Tuning',
        31: 'Insurance',
      };
      for (final e in defaults.entries) {
        await _db.insert('cost_categories',
            CostCategory(id: e.key, name: e.value).toMap());
      }
    }
    if (await _count('trip_categories') == 0) {
      await _db.insert(
          'trip_categories', TripCategory(id: 1, name: 'Private').toMap());
      await _db.insert(
          'trip_categories', TripCategory(id: 2, name: 'Work').toMap());
    }
  }

  Future<int> _count(String table) async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS n FROM $table');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  // ── Fuel log ───────────────────────────────────────────────────────────────

  Future<List<FuelEntry>> fuelLog() async {
    final rows = await _db.query('fuel_log', orderBy: 'date DESC');
    return rows.map(FuelEntry.fromMap).toList();
  }

  Future<int> insertFuel(FuelEntry e) => _db.insert('fuel_log', e.toMap());

  Future<void> updateFuel(FuelEntry e) => _db
      .update('fuel_log', e.toMap(), where: 'id = ?', whereArgs: [e.id]);

  Future<void> deleteFuel(int id) =>
      _db.delete('fuel_log', where: 'id = ?', whereArgs: [id]);

  // ── Costs ────────────────────────────────────────────────────────────────

  Future<List<CostEntry>> costs() async {
    final rows = await _db.query('costs', orderBy: 'date DESC');
    return rows.map(CostEntry.fromMap).toList();
  }

  Future<int> insertCost(CostEntry e) => _db.insert('costs', e.toMap());

  Future<void> updateCost(CostEntry e) =>
      _db.update('costs', e.toMap(), where: 'id = ?', whereArgs: [e.id]);

  Future<void> deleteCost(int id) =>
      _db.delete('costs', where: 'id = ?', whereArgs: [id]);

  // ── Cost categories ────────────────────────────────────────────────────────

  Future<List<CostCategory>> costCategories() async {
    final rows = await _db.query('cost_categories', orderBy: 'name');
    return rows.map(CostCategory.fromMap).toList();
  }

  /// Insert a category, auto-assigning the next free id.
  Future<int> insertCostCategory(String name,
      {int priority = 0, String color = ''}) async {
    final rows =
        await _db.rawQuery('SELECT COALESCE(MAX(id), 0) + 1 AS next FROM cost_categories');
    final id = Sqflite.firstIntValue(rows) ?? 1;
    await _db.insert('cost_categories',
        CostCategory(id: id, name: name, priority: priority, color: color).toMap());
    return id;
  }

  Future<void> updateCostCategory(CostCategory c) => _db.update(
      'cost_categories', c.toMap(),
      where: 'id = ?', whereArgs: [c.id]);

  /// Delete a category. Costs that referenced it fall back to category 1.
  Future<void> deleteCostCategory(int id) async {
    await _db.update('costs', {'cost_type_id': 1},
        where: 'cost_type_id = ?', whereArgs: [id]);
    await _db.delete('cost_categories', where: 'id = ?', whereArgs: [id]);
  }

  // ── Vehicle ────────────────────────────────────────────────────────────────

  /// The stored vehicle (single row, id 1), or null if none yet.
  Future<FuelioVehicle?> vehicle() async {
    final rows = await _db.query('vehicle', where: 'id = 1', limit: 1);
    return rows.isEmpty ? null : FuelioVehicle.fromMap(rows.first);
  }

  /// Insert or replace the single vehicle row.
  Future<void> saveVehicle(FuelioVehicle v) => _db.insert('vehicle', v.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace);

  // ── Trip categories ────────────────────────────────────────────────────────

  Future<List<TripCategory>> tripCategories() async {
    final rows = await _db.query('trip_categories', orderBy: 'id');
    return rows.map(TripCategory.fromMap).toList();
  }

  // ── Export ───────────────────────────────────────────────────────────────

  /// Snapshot the whole logbook as a [FuelioBackup] (for CSV export).
  Future<FuelioBackup> snapshot() async => FuelioBackup(
        vehicle: await vehicle(),
        logs: await fuelLog(),
        costCategories: await costCategories(),
        costs: await costs(),
        categories: await tripCategories(),
      );

  // ── Import ───────────────────────────────────────────────────────────────

  /// Merge a parsed backup into the store. Fuel/cost rows already present
  /// (matched by guid, else unique_id) are skipped; cost & trip categories are
  /// upserted by id so references stay valid.
  Future<ImportResult> import(FuelioBackup b) async {
    final res = ImportResult();

    await _db.transaction((txn) async {
      // Vehicle: adopt the file's vehicle only if we don't have one yet, so an
      // import never clobbers details the user has already edited.
      if (b.vehicle != null) {
        final existing = await txn.query('vehicle', where: 'id = 1', limit: 1);
        if (existing.isEmpty) {
          await txn.insert('vehicle', b.vehicle!.toMap());
        }
      }

      // Categories first so cost rows can reference them.
      for (final c in b.costCategories) {
        await txn.insert('cost_categories', c.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
        res.costCategoriesAdded++;
      }
      for (final c in b.categories) {
        await txn.insert('trip_categories', c.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
        res.categoriesAdded++;
      }

      // Existing keys, to skip duplicates.
      final existingFuel = await _keys(txn, 'fuel_log');
      for (final e in b.logs) {
        if (_isDup(e.guid, e.uniqueId, existingFuel)) {
          res.logsSkipped++;
          continue;
        }
        await txn.insert('fuel_log', e.toMap());
        _remember(e.guid, e.uniqueId, existingFuel);
        res.logsAdded++;
      }

      final existingCosts = await _keys(txn, 'costs');
      for (final e in b.costs) {
        if (_isDup(e.guid, e.uniqueId, existingCosts)) {
          res.costsSkipped++;
          continue;
        }
        await txn.insert('costs', e.toMap());
        _remember(e.guid, e.uniqueId, existingCosts);
        res.costsAdded++;
      }
    });

    return res;
  }

  static Future<Set<String>> _keys(DatabaseExecutor txn, String table) async {
    final rows = await txn.query(table, columns: ['guid', 'unique_id']);
    final keys = <String>{};
    for (final r in rows) {
      _remember(r['guid'] as String?, r['unique_id'] as int?, keys);
    }
    return keys;
  }

  static bool _isDup(String? guid, int? uniqueId, Set<String> keys) {
    if (guid != null && guid.isNotEmpty && keys.contains('g:$guid')) return true;
    if (uniqueId != null && keys.contains('u:$uniqueId')) return true;
    return false;
  }

  static void _remember(String? guid, int? uniqueId, Set<String> keys) {
    if (guid != null && guid.isNotEmpty) keys.add('g:$guid');
    if (uniqueId != null) keys.add('u:$uniqueId');
  }

  Future<void> close() => _db.close();
}
