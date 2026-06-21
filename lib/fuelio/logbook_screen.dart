import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cost_entry_screen.dart';
import 'fuel_entry_screen.dart';
import 'fuelio_csv.dart';
import 'fuelio_models.dart';
import 'fuelio_store.dart';
import 'vehicle_screen.dart';

/// The Fuelio logbook: fuel fill-ups, costs and cost categories in tabs, with
/// import-from / export-to Fuelio CSV. Backed by [FuelioStore].
class LogbookScreen extends StatefulWidget {
  const LogbookScreen({super.key, required this.store});

  final FuelioStore store;

  @override
  State<LogbookScreen> createState() => _LogbookScreenState();
}

class _LogbookScreenState extends State<LogbookScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  List<FuelEntry> _fuel = [];
  List<CostEntry> _costs = [];
  List<CostCategory> _categories = [];
  FuelioVehicle? _vehicle;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)
      ..addListener(() => setState(() {})); // refresh FAB per tab
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final fuel = await widget.store.fuelLog();
    final costs = await widget.store.costs();
    final cats = await widget.store.costCategories();
    final vehicle = await widget.store.vehicle();
    if (!mounted) return;
    setState(() {
      _fuel = fuel;
      _costs = costs;
      _categories = cats;
      _vehicle = vehicle;
      _loading = false;
    });
  }

  Future<void> _editVehicle() async {
    final saved = await Navigator.of(context).push<FuelioVehicle>(
      MaterialPageRoute(builder: (_) => VehicleScreen(vehicle: _vehicle)),
    );
    if (saved == null) return;
    await widget.store.saveVehicle(saved);
    await _reload();
  }

  String _categoryName(int id) => _categories
      .firstWhere((c) => c.id == id,
          orElse: () => CostCategory(id: id, name: 'Other'))
      .name;

  // ── Fuel CRUD ──────────────────────────────────────────────────────────────

  Future<void> _editFuel([FuelEntry? e]) async {
    final saved = await Navigator.of(context).push<FuelEntry>(
      MaterialPageRoute(builder: (_) => FuelEntryScreen(entry: e)),
    );
    if (saved == null) return;
    if (saved.id == null) {
      await widget.store.insertFuel(saved);
    } else {
      await widget.store.updateFuel(saved);
    }
    await _reload();
  }

  Future<void> _editCost([CostEntry? e]) async {
    if (_categories.isEmpty) return;
    final saved = await Navigator.of(context).push<CostEntry>(
      MaterialPageRoute(
          builder: (_) =>
              CostEntryScreen(entry: e, categories: _categories)),
    );
    if (saved == null) return;
    if (saved.id == null) {
      await widget.store.insertCost(saved);
    } else {
      await widget.store.updateCost(saved);
    }
    await _reload();
  }

  // ── Import / export ──────────────────────────────────────────────────────

  Future<void> _import() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'txt'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      final content = file.bytes != null
          ? utf8.decode(file.bytes!, allowMalformed: true)
          : (file.path != null ? await File(file.path!).readAsString() : null);
      if (content == null) {
        _toast('Could not read the file');
        return;
      }

      final backup = parseFuelioCsv(content);
      if (backup.isEmpty) {
        _toast('No Fuelio data found in that file');
        return;
      }
      if (!mounted) return;
      final go = await _confirmImport(backup);
      if (go != true) return;

      setState(() => _busy = true);
      final res = await widget.store.import(backup);
      await _reload();
      if (!mounted) return;
      _toast('Imported ${res.totalAdded} new '
          '(${res.logsSkipped + res.costsSkipped} duplicates skipped)');
    } catch (e) {
      _toast('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmImport(FuelioBackup b) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Import Fuelio backup',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Found in this file:',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              if (b.vehicle != null)
                _previewRow(Icons.directions_car,
                    'Vehicle: ${b.vehicle!.name.isEmpty ? 'unnamed' : b.vehicle!.name}'),
              _previewRow(Icons.local_gas_station, '${b.logs.length} fuel fill-ups'),
              _previewRow(Icons.receipt_long, '${b.costs.length} costs'),
              _previewRow(Icons.category, '${b.costCategories.length} cost categories'),
              _previewRow(Icons.label, '${b.categories.length} trip categories'),
              const SizedBox(height: 12),
              const Text('Existing entries (matched by id) are kept; '
                  'duplicates are skipped.',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL',
                  style: TextStyle(color: Colors.white54)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.cyan, foregroundColor: Colors.black),
              child: const Text('IMPORT'),
            ),
          ],
        ),
      );

  Widget _previewRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(icon, color: Colors.cyan, size: 18),
            const SizedBox(width: 10),
            Text(text, style: const TextStyle(color: Colors.white)),
          ],
        ),
      );

  Future<void> _export() async {
    try {
      setState(() => _busy = true);
      final backup = await widget.store.snapshot();
      final csv = writeFuelioCsv(backup);

      Directory dir;
      try {
        dir = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
      } catch (_) {
        dir = await getApplicationDocumentsDirectory();
      }
      final stamp = fmtFuelioDate(DateTime.now())
          .replaceAll(RegExp(r'[ :]'), '-');
      final path = p.join(dir.path, 'fuelio-export-$stamp.csv');
      await File(path).writeAsString(csv);
      if (!mounted) return;
      _showExportDone(path);
    } catch (e) {
      _toast('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showExportDone(String path) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Exported', style: TextStyle(color: Colors.white)),
          content: SelectableText(
            path,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.cyan, foregroundColor: Colors.black),
              child: const Text('OK'),
            ),
          ],
        ),
      );

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Logbook'),
        actions: [
          IconButton(
            tooltip: 'Vehicle details',
            icon: const Icon(Icons.directions_car_outlined),
            onPressed: _busy ? null : _editVehicle,
          ),
          IconButton(
            tooltip: 'Import Fuelio CSV',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _busy ? null : _import,
          ),
          IconButton(
            tooltip: 'Export Fuelio CSV',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _busy ? null : _export,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.cyan,
          labelColor: Colors.cyan,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'FUEL'),
            Tab(text: 'COSTS'),
            Tab(text: 'CATEGORIES'),
          ],
        ),
      ),
      floatingActionButton: _fab(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                TabBarView(
                  controller: _tabs,
                  children: [
                    _fuelTab(),
                    _costsTab(),
                    _categoriesTab(),
                  ],
                ),
                if (_busy)
                  Container(
                    color: Colors.black54,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }

  Widget? _fab() {
    if (_loading) return null;
    switch (_tabs.index) {
      case 0:
        return FloatingActionButton.extended(
          backgroundColor: Colors.cyan,
          foregroundColor: Colors.black,
          onPressed: () => _editFuel(),
          icon: const Icon(Icons.add),
          label: const Text('Fill-up'),
        );
      case 1:
        return FloatingActionButton.extended(
          backgroundColor: Colors.cyan,
          foregroundColor: Colors.black,
          onPressed: () => _editCost(),
          icon: const Icon(Icons.add),
          label: const Text('Cost'),
        );
      default:
        return FloatingActionButton.extended(
          backgroundColor: Colors.cyan,
          foregroundColor: Colors.black,
          onPressed: _addCategory,
          icon: const Icon(Icons.add),
          label: const Text('Category'),
        );
    }
  }

  // ── Fuel tab ───────────────────────────────────────────────────────────────

  Widget _fuelTab() {
    if (_fuel.isEmpty) {
      return _empty(Icons.local_gas_station, 'No fuel fill-ups',
          'Tap + to add one, or import a Fuelio CSV.');
    }
    final totalFuel = _fuel.fold<double>(0, (s, e) => s + e.fuel);
    final totalPrice = _fuel.fold<double>(0, (s, e) => s + e.price);
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (_vehicle != null) ...[
            _vehicleHeader(_vehicle!),
            const SizedBox(height: 16),
          ],
          _summaryCard([
            _stat('${_fuel.length}', 'fills'),
            _stat('${totalFuel.toStringAsFixed(0)} L', 'fuel'),
            _stat(_money(totalPrice), 'spent'),
          ]),
          const SizedBox(height: 16),
          for (final e in _fuel) _fuelCard(e),
        ],
      ),
    );
  }

  Widget _vehicleHeader(FuelioVehicle v) {
    final subtitle = [
      [v.make, v.model].where((s) => s.isNotEmpty).join(' '),
      v.year,
      v.plate,
    ].where((s) => s.isNotEmpty).join('  ·  ');
    return Material(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _editVehicle,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.cyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.directions_car, color: Colors.cyan),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.name.isEmpty ? 'Vehicle' : v.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.edit, color: Colors.white38, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fuelCard(FuelEntry e) => _dismissibleCard(
        key: 'fuel-${e.id}',
        onDelete: () async {
          await widget.store.deleteFuel(e.id!);
          await _reload();
        },
        onTap: () => _editFuel(e),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.cyan.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                e.full ? Icons.local_gas_station : Icons.local_gas_station_outlined,
                color: Colors.cyan,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${e.fuel.toStringAsFixed(2)} L'
                      '${e.full ? ' · full' : ''}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    '${_date(e.date)}'
                    '${e.odo > 0 ? '  ·  ${e.odo.toStringAsFixed(0)} km' : ''}'
                    '${e.city.isNotEmpty ? '  ·  ${e.city}' : ''}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (e.price > 0)
              Text(_money(e.price),
                  style: const TextStyle(
                      color: Colors.white70, fontWeight: FontWeight.w500)),
          ],
        ),
      );

  // ── Costs tab ──────────────────────────────────────────────────────────────

  Widget _costsTab() {
    if (_costs.isEmpty) {
      return _empty(Icons.receipt_long, 'No costs yet',
          'Tap + to add a cost, or import a Fuelio CSV.');
    }
    final spent = _costs
        .where((c) => !c.isIncome)
        .fold<double>(0, (s, e) => s + e.cost);
    final income = _costs
        .where((c) => c.isIncome)
        .fold<double>(0, (s, e) => s + e.cost);
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _summaryCard([
            _stat('${_costs.length}', 'entries'),
            _stat(_money(spent), 'spent'),
            if (income > 0) _stat(_money(income), 'income'),
          ]),
          if (spent > 0) ...[
            const SizedBox(height: 16),
            _categoryBreakdown(spent),
          ],
          const SizedBox(height: 16),
          for (final e in _costs) _costCard(e),
        ],
      ),
    );
  }

  Widget _costCard(CostEntry e) => _dismissibleCard(
        key: 'cost-${e.id}',
        onDelete: () async {
          await widget.store.deleteCost(e.id!);
          await _reload();
        },
        onTap: () => _editCost(e),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    '${_categoryName(e.costTypeId)}  ·  ${_date(e.date)}'
                    '${e.odo > 0 ? '  ·  ${e.odo.toStringAsFixed(0)} km' : ''}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${e.isIncome ? '+' : '-'}${_money(e.cost)}',
              style: TextStyle(
                color: e.isIncome ? Colors.greenAccent : Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  /// Spending-by-category bars, biggest first. [spent] is the grand total of
  /// non-income costs (used to scale the bars).
  Widget _categoryBreakdown(double spent) {
    final totals = <int, double>{};
    for (final c in _costs) {
      if (c.isIncome) continue;
      totals[c.costTypeId] = (totals[c.costTypeId] ?? 0) + c.cost;
    }
    final rows = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = rows.first.value;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Spending by category',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          for (final e in rows) _breakdownRow(e.key, e.value, maxVal, spent),
        ],
      ),
    );
  }

  Widget _breakdownRow(int catId, double value, double maxVal, double spent) {
    final pct = spent > 0 ? value / spent * 100 : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_categoryName(catId),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Text('${_money(value)}  ·  ${pct.toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: maxVal > 0 ? (value / maxVal).clamp(0.0, 1.0) : 0,
              minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(Colors.cyan),
            ),
          ),
        ],
      ),
    );
  }

  // ── Categories tab ───────────────────────────────────────────────────────

  Widget _categoriesTab() {
    if (_categories.isEmpty) {
      return _empty(Icons.category, 'No categories',
          'Tap + to create a cost category.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        for (final c in _categories) _categoryCard(c),
      ],
    );
  }

  Widget _categoryCard(CostCategory c) {
    final count = _costs.where((e) => e.costTypeId == c.id).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        leading: const Icon(Icons.label_outline, color: Colors.cyan),
        title: Text(c.name, style: const TextStyle(color: Colors.white)),
        subtitle: Text('$count ${count == 1 ? 'cost' : 'costs'}',
            style: const TextStyle(color: Colors.white54)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white38, size: 20),
              onPressed: () => _renameCategory(c),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.white38, size: 20),
              onPressed: () => _deleteCategory(c),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addCategory() async {
    final name = await _categoryNameDialog('New category');
    if (name == null || name.trim().isEmpty) return;
    await widget.store.insertCostCategory(name.trim());
    await _reload();
  }

  Future<void> _renameCategory(CostCategory c) async {
    final name = await _categoryNameDialog('Rename category', initial: c.name);
    if (name == null || name.trim().isEmpty) return;
    await widget.store.updateCostCategory(c.copyWith(name: name.trim()));
    await _reload();
  }

  Future<void> _deleteCategory(CostCategory c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete category',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "${c.name}"? Costs using it will move to the first category.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL',
                style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.deleteCostCategory(c.id);
    await _reload();
  }

  Future<String?> _categoryNameDialog(String title, {String initial = ''}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Category name',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL',
                style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.cyan, foregroundColor: Colors.black),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  // ── Shared widgets ───────────────────────────────────────────────────────

  Widget _dismissibleCard({
    required String key,
    required Future<void> Function() onDelete,
    required VoidCallback onTap,
    required Widget child,
  }) =>
      Dismissible(
        key: ValueKey(key),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: Colors.red.shade900,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        onDismissed: (_) => onDelete(),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: child,
              ),
            ),
          ),
        ),
      );

  Widget _summaryCard(List<Widget> stats) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.cyan.withOpacity(0.16), Colors.white10],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: stats,
        ),
      );

  Widget _stat(String value, String label) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      );

  Widget _empty(IconData icon, String title, String subtitle) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 72, color: Colors.white.withOpacity(0.18)),
              const SizedBox(height: 20),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 14, height: 1.4)),
            ],
          ),
        ),
      );

  static String _two(int n) => n.toString().padLeft(2, '0');

  String _date(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)}';

  /// Group digits with thousands separators (e.g. 1500000 → "1,500,000").
  static String _money(double v) {
    final n = v.round();
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}$buf';
  }
}
