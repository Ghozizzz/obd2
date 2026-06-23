import 'dart:convert';

import 'fuelio/fuelio_csv.dart';
import 'fuelio/fuelio_models.dart';
import 'fuelio/fuelio_store.dart';
import 'trip.dart';
import 'trip_store.dart';

/// A single "Export All" backup bundles everything the app stores into one JSON
/// file: trip history ([TripStore]) and the fuel & cost logbook ([FuelioStore]).
///
/// The file is self-describing ([_formatTag] + [_formatVersion]) so [importAll]
/// can reject anything that isn't one of ours, and it restores onto a fresh
/// install of the app on another phone.
class BackupService {
  BackupService._();

  static const _formatTag = 'excar-backup';
  static const _formatVersion = 1;

  /// Counts of what a restore added vs skipped, for a "what happened" summary.
  static String _formatStamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}_'
        '${two(t.hour)}-${two(t.minute)}-${two(t.second)}';
  }

  /// Suggested filename for an export taken at [now].
  static String fileName(DateTime now) => 'excar-backup-${_formatStamp(now)}.json';

  /// Snapshot every store into one pretty-printed JSON document.
  static Future<String> exportAll({
    required TripStore? trips,
    required FuelioStore? fuelio,
    required DateTime now,
  }) async {
    final tripList = trips == null ? const <Trip>[] : await trips.all();
    final fb = fuelio == null ? null : await fuelio.snapshot();

    final map = <String, Object?>{
      'app': 'ExCar',
      'format': _formatTag,
      'version': _formatVersion,
      'exportedAt': now.toIso8601String(),
      'trips': tripList.map((t) => t.toMap()).toList(),
      'fuelio': fb == null
          ? null
          : <String, Object?>{
              'vehicle': fb.vehicle?.toMap(),
              'logs': fb.logs.map((e) => e.toMap()).toList(),
              'costCategories': fb.costCategories.map((e) => e.toMap()).toList(),
              'costs': fb.costs.map((e) => e.toMap()).toList(),
              'categories': fb.categories.map((e) => e.toMap()).toList(),
            },
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Merge a backup file's [content] into the stores, skipping anything already
  /// present so a restore is safe to run more than once.
  static Future<RestoreSummary> importAll(
    String content, {
    required TripStore? trips,
    required FuelioStore? fuelio,
  }) async {
    final Object? data;
    try {
      data = jsonDecode(content);
    } catch (_) {
      throw const FormatException('Not a valid backup file');
    }
    if (data is! Map || data['format'] != _formatTag) {
      throw const FormatException('Not an ExCar backup file');
    }

    final summary = RestoreSummary();

    // ── Trips ── deduped by start time (trips carry no stable id of their own).
    if (trips != null && data['trips'] is List) {
      final existing = await trips.all();
      final seen = existing
          .map((t) => t.startedAt.millisecondsSinceEpoch)
          .toSet();
      for (final raw in data['trips'] as List) {
        if (raw is! Map) continue;
        final m = Map<String, Object?>.from(raw);
        m.remove('id'); // let SQLite assign a fresh row id
        final t = Trip.fromMap(m);
        final key = t.startedAt.millisecondsSinceEpoch;
        if (!seen.add(key)) {
          summary.tripsSkipped++;
          continue;
        }
        await trips.insert(t);
        summary.tripsAdded++;
      }
    }

    // ── Fuelio logbook ── reuse the store's own guid/unique-id merge logic.
    if (fuelio != null && data['fuelio'] is Map) {
      final f = data['fuelio'] as Map;
      final v = f['vehicle'];
      final backup = FuelioBackup(
        vehicle: v is Map
            ? FuelioVehicle.fromMap(Map<String, Object?>.from(v))
            : null,
        // Drop ids on fuel/cost rows so they get fresh auto-increment ids,
        // matching the CSV import path and avoiding primary-key clashes.
        logs: _rows(f['logs'], FuelEntry.fromMap, stripId: true),
        costs: _rows(f['costs'], CostEntry.fromMap, stripId: true),
        // Category ids are referenced by cost rows, so they are kept.
        costCategories: _rows(f['costCategories'], CostCategory.fromMap),
        categories: _rows(f['categories'], TripCategory.fromMap),
      );
      summary.fuelio = await fuelio.import(backup);
    }

    return summary;
  }

  static List<T> _rows<T>(
    Object? raw,
    T Function(Map<String, Object?>) fromMap, {
    bool stripId = false,
  }) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) {
      final m = Map<String, Object?>.from(e);
      if (stripId) m.remove('id');
      return fromMap(m);
    }).toList();
  }
}

/// Outcome of [BackupService.importAll].
class RestoreSummary {
  int tripsAdded = 0;
  int tripsSkipped = 0;
  ImportResult? fuelio;

  int get totalAdded => tripsAdded + (fuelio?.totalAdded ?? 0);
}
