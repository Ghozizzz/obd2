/// Data models mirroring the sections of a Fuelio CSV backup
/// (`## Vehicle`, `## Log`, `## CostCategories`, `## Costs`, `## Category`).
///
/// Each model knows how to (de)serialise to a SQLite row map and to a list of
/// Fuelio CSV cell values, so the same objects drive storage, CRUD and
/// import/export without a second mapping layer.
library;

/// Format a [DateTime] the way Fuelio writes it: `yyyy-MM-dd HH:mm`.
String fmtFuelioDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}';
}

/// Parse the date forms Fuelio emits: `yyyy-MM-dd HH:mm`, `yyyy-MM-dd HH:mm:ss`
/// or a bare `yyyy-MM-dd`. Returns null if it cannot be understood.
DateTime? parseFuelioDate(String? raw) {
  final s = raw?.trim() ?? '';
  if (s.isEmpty) return null;
  final m = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?$',
  ).firstMatch(s);
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4) ?? '0'),
    int.parse(m.group(5) ?? '0'),
    int.parse(m.group(6) ?? '0'),
  );
}

double _d(Object? v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v'.trim()) ?? 0);
int _i(Object? v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v'.trim()) ?? 0);
String _s(Object? v) => v == null ? '' : '$v';

// ─────────────────────────────────────────────────────────────────────────────
// Fuel log
// ─────────────────────────────────────────────────────────────────────────────

/// One fuel fill-up — the `## Log` section.
class FuelEntry {
  FuelEntry({
    this.id,
    required this.date,
    this.odo = 0,
    this.fuel = 0,
    this.full = false,
    this.price = 0,
    this.city = '',
    this.notes = '',
    this.tankNumber = 1,
    this.fuelType = 0,
    this.volumePrice = 0,
    this.missed = false,
    this.guid,
    this.uniqueId,
  });

  final int? id;
  final DateTime date;

  /// Odometer reading at the fill (km).
  final double odo;

  /// Volume filled (litres).
  final double fuel;

  /// Whether the tank was filled to full (drives Fuelio's economy calc).
  final bool full;

  /// Total price paid for this fill.
  final double price;

  final String city;
  final String notes;
  final int tankNumber;
  final int fuelType;

  /// Price per litre.
  final double volumePrice;

  /// Whether a previous fill was missed (breaks the distance chain).
  final bool missed;

  /// Fuelio's stable identifiers — preserved for dedupe + round-trip export.
  final String? guid;
  final int? uniqueId;

  FuelEntry copyWith({
    DateTime? date,
    double? odo,
    double? fuel,
    bool? full,
    double? price,
    String? city,
    String? notes,
    int? tankNumber,
    int? fuelType,
    double? volumePrice,
    bool? missed,
  }) =>
      FuelEntry(
        id: id,
        date: date ?? this.date,
        odo: odo ?? this.odo,
        fuel: fuel ?? this.fuel,
        full: full ?? this.full,
        price: price ?? this.price,
        city: city ?? this.city,
        notes: notes ?? this.notes,
        tankNumber: tankNumber ?? this.tankNumber,
        fuelType: fuelType ?? this.fuelType,
        volumePrice: volumePrice ?? this.volumePrice,
        missed: missed ?? this.missed,
        guid: guid,
        uniqueId: uniqueId,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'date': date.millisecondsSinceEpoch,
        'odo': odo,
        'fuel': fuel,
        'full': full ? 1 : 0,
        'price': price,
        'city': city,
        'notes': notes,
        'tank_number': tankNumber,
        'fuel_type': fuelType,
        'volume_price': volumePrice,
        'missed': missed ? 1 : 0,
        'guid': guid,
        'unique_id': uniqueId,
      };

  static FuelEntry fromMap(Map<String, Object?> m) => FuelEntry(
        id: m['id'] as int?,
        date: DateTime.fromMillisecondsSinceEpoch(_i(m['date'])),
        odo: _d(m['odo']),
        fuel: _d(m['fuel']),
        full: _i(m['full']) == 1,
        price: _d(m['price']),
        city: _s(m['city']),
        notes: _s(m['notes']),
        tankNumber: _i(m['tank_number']),
        fuelType: _i(m['fuel_type']),
        volumePrice: _d(m['volume_price']),
        missed: _i(m['missed']) == 1,
        guid: m['guid'] as String?,
        uniqueId: m['unique_id'] as int?,
      );

  /// Build from a Fuelio `## Log` row keyed by column name.
  static FuelEntry fromCsv(Map<String, String> r) => FuelEntry(
        date: parseFuelioDate(r['Data']) ?? DateTime(1970),
        odo: _d(r['Odo (km)']),
        fuel: _d(r['Fuel (litres)']),
        full: _i(r['Full']) == 1,
        price: _d(r['Price (optional)']),
        city: _s(r['City (optional)']),
        notes: _s(r['Notes (optional)']),
        tankNumber: _i(r['TankNumber']),
        fuelType: _i(r['FuelType']),
        volumePrice: _d(r['VolumePrice']),
        missed: _i(r['Missed']) == 1,
        guid: (r['guid'] ?? '').isEmpty ? null : r['guid'],
        uniqueId: int.tryParse((r['UniqueId'] ?? '').trim()),
      );

  static const csvHeader = [
    'Data',
    'Odo (km)',
    'Fuel (litres)',
    'Full',
    'Price (optional)',
    'km/l (optional)',
    'latitude (optional)',
    'longitude (optional)',
    'City (optional)',
    'Notes (optional)',
    'Missed',
    'TankNumber',
    'FuelType',
    'VolumePrice',
    'StationID (optional)',
    'ExcludeDistance',
    'UniqueId',
    'TankCalc',
    'Weather',
    'guid',
    'lastupdated',
  ];

  List<String> toCsvRow() => [
        fmtFuelioDate(date),
        odo.toString(),
        fuel.toString(),
        full ? '1' : '0',
        price.toString(),
        '', // km/l — derived by Fuelio
        '0.0', '0.0', // lat/lon
        city,
        notes,
        missed ? '1' : '0',
        '$tankNumber',
        '$fuelType',
        volumePrice.toString(),
        '0', // StationID
        '0.0', // ExcludeDistance
        uniqueId?.toString() ?? '',
        '0.0', // TankCalc
        '', // Weather
        guid ?? '',
        '0', // lastupdated
      ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Cost categories
// ─────────────────────────────────────────────────────────────────────────────

/// A cost category — the `## CostCategories` section. [id] is Fuelio's
/// `CostTypeID`, kept stable so [CostEntry.costTypeId] keeps pointing at it.
class CostCategory {
  CostCategory({
    required this.id,
    required this.name,
    this.priority = 0,
    this.color = '',
    this.guid,
  });

  final int id;
  final String name;
  final int priority;
  final String color;
  final String? guid;

  CostCategory copyWith({String? name, int? priority, String? color}) =>
      CostCategory(
        id: id,
        name: name ?? this.name,
        priority: priority ?? this.priority,
        color: color ?? this.color,
        guid: guid,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'priority': priority,
        'color': color,
        'guid': guid,
      };

  static CostCategory fromMap(Map<String, Object?> m) => CostCategory(
        id: _i(m['id']),
        name: _s(m['name']),
        priority: _i(m['priority']),
        color: _s(m['color']),
        guid: m['guid'] as String?,
      );

  static CostCategory fromCsv(Map<String, String> r) => CostCategory(
        id: _i(r['CostTypeID']),
        name: _s(r['Name']),
        priority: _i(r['priority']),
        color: _s(r['color']),
        guid: (r['guid'] ?? '').isEmpty ? null : r['guid'],
      );

  static const csvHeader = [
    'CostTypeID',
    'Name',
    'priority',
    'color',
    'guid',
    'lastupdated',
  ];

  List<String> toCsvRow() =>
      ['$id', name, '$priority', color, guid ?? '', '0'];
}

// ─────────────────────────────────────────────────────────────────────────────
// Costs
// ─────────────────────────────────────────────────────────────────────────────

/// A one-off cost or income entry — the `## Costs` section.
class CostEntry {
  CostEntry({
    this.id,
    required this.title,
    required this.date,
    this.odo = 0,
    this.costTypeId = 1,
    this.notes = '',
    this.cost = 0,
    this.isIncome = false,
    this.guid,
    this.uniqueId,
  });

  final int? id;
  final String title;
  final DateTime date;
  final double odo;
  final int costTypeId;
  final String notes;
  final double cost;
  final bool isIncome;
  final String? guid;
  final int? uniqueId;

  CostEntry copyWith({
    String? title,
    DateTime? date,
    double? odo,
    int? costTypeId,
    String? notes,
    double? cost,
    bool? isIncome,
  }) =>
      CostEntry(
        id: id,
        title: title ?? this.title,
        date: date ?? this.date,
        odo: odo ?? this.odo,
        costTypeId: costTypeId ?? this.costTypeId,
        notes: notes ?? this.notes,
        cost: cost ?? this.cost,
        isIncome: isIncome ?? this.isIncome,
        guid: guid,
        uniqueId: uniqueId,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'date': date.millisecondsSinceEpoch,
        'odo': odo,
        'cost_type_id': costTypeId,
        'notes': notes,
        'cost': cost,
        'is_income': isIncome ? 1 : 0,
        'guid': guid,
        'unique_id': uniqueId,
      };

  static CostEntry fromMap(Map<String, Object?> m) => CostEntry(
        id: m['id'] as int?,
        title: _s(m['title']),
        date: DateTime.fromMillisecondsSinceEpoch(_i(m['date'])),
        odo: _d(m['odo']),
        costTypeId: _i(m['cost_type_id']),
        notes: _s(m['notes']),
        cost: _d(m['cost']),
        isIncome: _i(m['is_income']) == 1,
        guid: m['guid'] as String?,
        uniqueId: m['unique_id'] as int?,
      );

  static CostEntry fromCsv(Map<String, String> r) => CostEntry(
        title: _s(r['CostTitle']),
        date: parseFuelioDate(r['Date']) ?? DateTime(1970),
        odo: _d(r['Odo']),
        costTypeId: _i(r['CostTypeID']),
        notes: _s(r['Notes']),
        cost: _d(r['Cost']),
        isIncome: _i(r['isIncome']) == 1,
        guid: (r['guid'] ?? '').isEmpty ? null : r['guid'],
        uniqueId: int.tryParse((r['UniqueId'] ?? '').trim()),
      );

  static const csvHeader = [
    'CostTitle',
    'Date',
    'Odo',
    'CostTypeID',
    'Notes',
    'Cost',
    'flag',
    'idR',
    'read',
    'RemindOdo',
    'RemindDate',
    'isTemplate',
    'RepeatOdo',
    'RepeatMonths',
    'isIncome',
    'UniqueId',
    'guid',
    'lastupdated',
  ];

  List<String> toCsvRow() => [
        title,
        fmtFuelioDate(date),
        odo.toStringAsFixed(0),
        '$costTypeId',
        notes,
        cost.toString(),
        '0', // flag
        '0', // idR
        '1', // read
        '0', // RemindOdo
        '2011-01-01', // RemindDate
        '0', // isTemplate
        '0', // RepeatOdo
        '0', // RepeatMonths
        isIncome ? '1' : '0',
        uniqueId?.toString() ?? '',
        guid ?? '',
        '0', // lastupdated
      ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Vehicle
// ─────────────────────────────────────────────────────────────────────────────

/// The vehicle a backup describes — the `## Vehicle` section. Fuelio files are
/// per-vehicle, so the app keeps a single one (row id fixed at 1). Less common
/// fields are stored verbatim so export round-trips.
class FuelioVehicle {
  FuelioVehicle({
    this.name = '',
    this.description = '',
    this.distUnit = 0,
    this.fuelUnit = 0,
    this.consumptionUnit = 3,
    this.importDateFormat = 'yyyy-MM-dd',
    this.vin = '',
    this.insurance = '',
    this.plate = '',
    this.make = '',
    this.model = '',
    this.year = '',
    this.tankCount = 1,
    this.tank1Type = 100,
    this.tank2Type = 0,
    this.active = 1,
    this.tank1Capacity = 0,
    this.tank2Capacity = 0,
    this.fuelUnitTank2 = 0,
    this.fuelConsumptionTank2 = 0,
    this.guid,
  });

  final String name;
  final String description;
  final int distUnit; // 0 = km, 1 = miles
  final int fuelUnit; // 0 = litres, 1 = gal(US), 2 = gal(UK)
  final int consumptionUnit; // 0 = L/100km, 1 = mpg(US), 2 = mpg(UK), 3 = km/L
  final String importDateFormat;
  final String vin;
  final String insurance;
  final String plate;
  final String make;
  final String model;
  final String year;
  final int tankCount;
  final int tank1Type;
  final int tank2Type;
  final int active;
  final double tank1Capacity;
  final double tank2Capacity;
  final int fuelUnitTank2;
  final int fuelConsumptionTank2;
  final String? guid;

  /// Human label for [distUnit].
  String get distUnitLabel => distUnit == 1 ? 'miles' : 'km';

  /// Human label for [consumptionUnit].
  String get consumptionUnitLabel => switch (consumptionUnit) {
        0 => 'L/100km',
        1 => 'mpg (US)',
        2 => 'mpg (UK)',
        _ => 'km/L',
      };

  FuelioVehicle copyWith({
    String? name,
    String? description,
    int? distUnit,
    int? fuelUnit,
    int? consumptionUnit,
    String? vin,
    String? insurance,
    String? plate,
    String? make,
    String? model,
    String? year,
    double? tank1Capacity,
  }) =>
      FuelioVehicle(
        name: name ?? this.name,
        description: description ?? this.description,
        distUnit: distUnit ?? this.distUnit,
        fuelUnit: fuelUnit ?? this.fuelUnit,
        consumptionUnit: consumptionUnit ?? this.consumptionUnit,
        importDateFormat: importDateFormat,
        vin: vin ?? this.vin,
        insurance: insurance ?? this.insurance,
        plate: plate ?? this.plate,
        make: make ?? this.make,
        model: model ?? this.model,
        year: year ?? this.year,
        tankCount: tankCount,
        tank1Type: tank1Type,
        tank2Type: tank2Type,
        active: active,
        tank1Capacity: tank1Capacity ?? this.tank1Capacity,
        tank2Capacity: tank2Capacity,
        fuelUnitTank2: fuelUnitTank2,
        fuelConsumptionTank2: fuelConsumptionTank2,
        guid: guid,
      );

  Map<String, Object?> toMap() => {
        'id': 1,
        'name': name,
        'description': description,
        'dist_unit': distUnit,
        'fuel_unit': fuelUnit,
        'consumption_unit': consumptionUnit,
        'import_date_format': importDateFormat,
        'vin': vin,
        'insurance': insurance,
        'plate': plate,
        'make': make,
        'model': model,
        'year': year,
        'tank_count': tankCount,
        'tank1_type': tank1Type,
        'tank2_type': tank2Type,
        'active': active,
        'tank1_capacity': tank1Capacity,
        'tank2_capacity': tank2Capacity,
        'fuel_unit_tank2': fuelUnitTank2,
        'fuel_consumption_tank2': fuelConsumptionTank2,
        'guid': guid,
      };

  static FuelioVehicle fromMap(Map<String, Object?> m) => FuelioVehicle(
        name: _s(m['name']),
        description: _s(m['description']),
        distUnit: _i(m['dist_unit']),
        fuelUnit: _i(m['fuel_unit']),
        consumptionUnit: _i(m['consumption_unit']),
        importDateFormat: _s(m['import_date_format']),
        vin: _s(m['vin']),
        insurance: _s(m['insurance']),
        plate: _s(m['plate']),
        make: _s(m['make']),
        model: _s(m['model']),
        year: _s(m['year']),
        tankCount: _i(m['tank_count']),
        tank1Type: _i(m['tank1_type']),
        tank2Type: _i(m['tank2_type']),
        active: _i(m['active']),
        tank1Capacity: _d(m['tank1_capacity']),
        tank2Capacity: _d(m['tank2_capacity']),
        fuelUnitTank2: _i(m['fuel_unit_tank2']),
        fuelConsumptionTank2: _i(m['fuel_consumption_tank2']),
        guid: m['guid'] as String?,
      );

  static FuelioVehicle fromCsv(Map<String, String> r) => FuelioVehicle(
        name: _s(r['Name']).trim(),
        description: _s(r['Description']),
        distUnit: _i(r['DistUnit']),
        fuelUnit: _i(r['FuelUnit']),
        consumptionUnit: _i(r['ConsumptionUnit']),
        importDateFormat: _s(r['ImportCSVDateFormat']),
        vin: _s(r['VIN']),
        insurance: _s(r['Insurance']),
        plate: _s(r['Plate']),
        make: _s(r['Make']),
        model: _s(r['Model']),
        year: _s(r['Year']),
        tankCount: _i(r['TankCount']),
        tank1Type: _i(r['Tank1Type']),
        tank2Type: _i(r['Tank2Type']),
        active: _i(r['Active']),
        tank1Capacity: _d(r['Tank1Capacity']),
        tank2Capacity: _d(r['Tank2Capacity']),
        fuelUnitTank2: _i(r['FuelUnitTank2']),
        fuelConsumptionTank2: _i(r['FuelConsumptionTank2']),
        guid: (r['guid'] ?? '').isEmpty ? null : r['guid'],
      );

  static const csvHeader = [
    'Name',
    'Description',
    'DistUnit',
    'FuelUnit',
    'ConsumptionUnit',
    'ImportCSVDateFormat',
    'VIN',
    'Insurance',
    'Plate',
    'Make',
    'Model',
    'Year',
    'TankCount',
    'Tank1Type',
    'Tank2Type',
    'Active',
    'Tank1Capacity',
    'Tank2Capacity',
    'FuelUnitTank2',
    'FuelConsumptionTank2',
    'guid',
    'lastupdated',
  ];

  List<String> toCsvRow() => [
        name,
        description,
        '$distUnit',
        '$fuelUnit',
        '$consumptionUnit',
        importDateFormat,
        vin,
        insurance,
        plate,
        make,
        model,
        year,
        '$tankCount',
        '$tank1Type',
        '$tank2Type',
        '$active',
        tank1Capacity.toString(),
        tank2Capacity.toString(),
        '$fuelUnitTank2',
        '$fuelConsumptionTank2',
        guid ?? '',
        '0',
      ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Trip categories (Private / Work …)
// ─────────────────────────────────────────────────────────────────────────────

/// A trip category — the `## Category` section.
class TripCategory {
  TripCategory({required this.id, required this.name, this.guid});

  final int id;
  final String name;
  final String? guid;

  Map<String, Object?> toMap() => {'id': id, 'name': name, 'guid': guid};

  static TripCategory fromMap(Map<String, Object?> m) =>
      TripCategory(id: _i(m['id']), name: _s(m['name']), guid: m['guid'] as String?);

  static TripCategory fromCsv(Map<String, String> r) => TripCategory(
        id: _i(r['IdCategory']),
        name: _s(r['Name']),
        guid: (r['guid'] ?? '').isEmpty ? null : r['guid'],
      );

  static const csvHeader = ['IdCategory', 'Name', 'guid', 'lastupdated'];

  List<String> toCsvRow() => ['$id', name, guid ?? '', '0'];
}
