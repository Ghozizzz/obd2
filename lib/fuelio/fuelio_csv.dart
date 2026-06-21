/// Parser + writer for the Fuelio CSV backup format.
///
/// A Fuelio export is several CSV tables stitched into one file, each introduced
/// by a `"## SectionName"` marker line, followed by a header row and then data
/// rows. Sections we care about: `## Log`, `## CostCategories`, `## Costs`,
/// `## Category`. Anything else (e.g. `## Vehicle`) is skipped gracefully.
library;

import 'fuelio_models.dart';

/// The decoded contents of a Fuelio backup.
class FuelioBackup {
  FuelioBackup({
    this.vehicle,
    this.logs = const [],
    this.costCategories = const [],
    this.costs = const [],
    this.categories = const [],
  });

  final FuelioVehicle? vehicle;
  final List<FuelEntry> logs;
  final List<CostCategory> costCategories;
  final List<CostEntry> costs;
  final List<TripCategory> categories;

  bool get isEmpty =>
      vehicle == null &&
      logs.isEmpty &&
      costCategories.isEmpty &&
      costs.isEmpty &&
      categories.isEmpty;
}

/// Parse one CSV line into cells, honouring `"`-quoted fields and `""` escapes.
List<String> parseCsvLine(String line) {
  final out = <String>[];
  final sb = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        sb.write(c);
      }
    } else {
      if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        out.add(sb.toString());
        sb.clear();
      } else {
        sb.write(c);
      }
    }
  }
  out.add(sb.toString());
  return out;
}

/// Quote a single cell for output (always quoted, matching Fuelio).
String _quote(String cell) => '"${cell.replaceAll('"', '""')}"';

/// Serialise a row of cells to a Fuelio CSV line.
String _csvLine(List<String> cells) => cells.map(_quote).join(',');

/// True if [line] is a `## Section` marker; returns the bare section name.
String? _sectionName(String line) {
  final cells = parseCsvLine(line);
  if (cells.isEmpty) return null;
  final first = cells.first.trim();
  if (first.startsWith('##')) return first.substring(2).trim();
  return null;
}

/// Parse a full Fuelio backup file into a [FuelioBackup].
FuelioBackup parseFuelioCsv(String content) {
  final lines = content.split(RegExp(r'\r?\n'));
  FuelioVehicle? vehicle;
  final logs = <FuelEntry>[];
  final costCats = <CostCategory>[];
  final costs = <CostEntry>[];
  final cats = <TripCategory>[];

  String? section;
  List<String>? header;

  for (final raw in lines) {
    if (raw.trim().isEmpty) continue;

    final name = _sectionName(raw);
    if (name != null) {
      section = name;
      header = null; // next non-empty line is this section's header
      continue;
    }
    if (section == null) continue;

    final cells = parseCsvLine(raw);
    if (header == null) {
      header = cells.map((c) => c.trim()).toList();
      continue;
    }

    // Map this data row to {columnName: value}.
    final row = <String, String>{};
    for (var i = 0; i < header.length; i++) {
      row[header[i]] = i < cells.length ? cells[i] : '';
    }

    switch (section) {
      case 'Vehicle':
        vehicle ??= FuelioVehicle.fromCsv(row); // first row only
        break;
      case 'Log':
        logs.add(FuelEntry.fromCsv(row));
        break;
      case 'CostCategories':
        costCats.add(CostCategory.fromCsv(row));
        break;
      case 'Costs':
        costs.add(CostEntry.fromCsv(row));
        break;
      case 'Category':
        cats.add(TripCategory.fromCsv(row));
        break;
      default:
        break; // Vehicle and any unknown sections are ignored.
    }
  }

  return FuelioBackup(
    vehicle: vehicle,
    logs: logs,
    costCategories: costCats,
    costs: costs,
    categories: cats,
  );
}

/// Write a [FuelioBackup] back out in Fuelio's CSV layout. Round-trips the
/// sections this app manages; re-importable into Fuelio.
String writeFuelioCsv(FuelioBackup b) {
  final sb = StringBuffer();

  void section(String name, List<String> header, Iterable<List<String>> rows) {
    sb.writeln(_quote('## $name'));
    sb.writeln(_csvLine(header));
    for (final r in rows) {
      sb.writeln(_csvLine(r));
    }
  }

  if (b.vehicle != null) {
    section('Vehicle', FuelioVehicle.csvHeader, [b.vehicle!.toCsvRow()]);
  }
  section('Log', FuelEntry.csvHeader, b.logs.map((e) => e.toCsvRow()));
  section('CostCategories', CostCategory.csvHeader,
      b.costCategories.map((e) => e.toCsvRow()));
  section('Costs', CostEntry.csvHeader, b.costs.map((e) => e.toCsvRow()));
  section('Category', TripCategory.csvHeader,
      b.categories.map((e) => e.toCsvRow()));

  return sb.toString();
}
