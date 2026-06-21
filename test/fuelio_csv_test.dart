import 'dart:io';

import 'package:excar/fuelio/fuelio_csv.dart';
import 'package:excar/fuelio/fuelio_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the Fuelio CSV parser + writer against the real sample export
/// (sample/car1-20260621-222746.csv) and a synthetic round-trip.
void main() {
  group('parseFuelioCsv', () {
    late FuelioBackup backup;

    setUpAll(() {
      final file = File('sample/car1-20260621-222746.csv');
      backup = parseFuelioCsv(file.readAsStringSync());
    });

    test('parses every section of the sample export', () {
      expect(backup.vehicle, isNotNull);
      expect(backup.vehicle!.name, 'X-Trail');
      expect(backup.vehicle!.tank1Capacity, 65.0);
      expect(backup.vehicle!.consumptionUnit, 3); // km/L

      // 179 fuel log rows (UniqueId 1..180, minus the gap at 56/57 region).
      expect(backup.logs.length, 179);
      expect(backup.costCategories.length, 9);
      expect(backup.costs.length, greaterThan(60));
      expect(backup.categories.length, 2);
    });

    test('decodes a known fuel entry correctly', () {
      // First data row: 2026-06-20 07:55, 179915 km, 50 L, price 500000.
      final first = backup.logs.firstWhere((e) => e.odo == 179915.0);
      expect(first.fuel, 50.0);
      expect(first.price, 500000.0);
      expect(first.date, DateTime(2026, 6, 20, 7, 55));
      expect(first.fuelType, 105);
    });

    test('decodes cost categories and a cost row', () {
      expect(backup.costCategories.firstWhere((c) => c.id == 1).name, 'Service');
      final cost = backup.costs.firstWhere((c) => c.title == 'Aki GS Calcium');
      expect(cost.cost, 1641000.0);
      expect(cost.costTypeId, 1);
      expect(cost.date, DateTime(2026, 5, 12, 10, 40));
    });

    test('trip categories', () {
      expect(backup.categories.map((c) => c.name), containsAll(['Private', 'Work']));
    });
  });

  test('round-trips through writeFuelioCsv', () {
    final original = FuelioBackup(
      vehicle: FuelioVehicle(name: 'Test Car', make: 'Nissan', tank1Capacity: 60),
      logs: [
        FuelEntry(
          date: DateTime(2026, 1, 2, 8, 30),
          odo: 1000,
          fuel: 40.5,
          price: 400000,
          full: true,
          guid: 'g-1',
          uniqueId: 1,
        ),
      ],
      costCategories: [CostCategory(id: 1, name: 'Service')],
      costs: [
        CostEntry(
          title: 'Oil change',
          date: DateTime(2026, 1, 3, 9, 0),
          cost: 500000,
          costTypeId: 1,
          guid: 'c-1',
          uniqueId: 1,
        ),
      ],
      categories: [TripCategory(id: 1, name: 'Private')],
    );

    final reparsed = parseFuelioCsv(writeFuelioCsv(original));

    expect(reparsed.vehicle!.name, 'Test Car');
    expect(reparsed.vehicle!.tank1Capacity, 60);
    expect(reparsed.logs.single.fuel, 40.5);
    expect(reparsed.logs.single.full, isTrue);
    expect(reparsed.logs.single.guid, 'g-1');
    expect(reparsed.costs.single.title, 'Oil change');
    expect(reparsed.costs.single.cost, 500000);
    expect(reparsed.categories.single.name, 'Private');
  });

  test('parseCsvLine handles quoted commas and escaped quotes', () {
    final cells = parseCsvLine('"a","b, still b","he said ""hi"""');
    expect(cells, ['a', 'b, still b', 'he said "hi"']);
  });
}
