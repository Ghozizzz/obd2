import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fuelio_models.dart';

/// View / edit the vehicle described by the logbook (the `## Vehicle` section).
/// Returns the saved [FuelioVehicle] via Navigator.pop, or null if cancelled.
class VehicleScreen extends StatefulWidget {
  const VehicleScreen({super.key, this.vehicle});

  final FuelioVehicle? vehicle;

  @override
  State<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends State<VehicleScreen> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _name;
  late TextEditingController _make;
  late TextEditingController _model;
  late TextEditingController _year;
  late TextEditingController _plate;
  late TextEditingController _vin;
  late TextEditingController _insurance;
  late TextEditingController _tank;
  late int _distUnit;
  late int _consumptionUnit;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle ?? FuelioVehicle();
    _name = TextEditingController(text: v.name);
    _make = TextEditingController(text: v.make);
    _model = TextEditingController(text: v.model);
    _year = TextEditingController(text: v.year);
    _plate = TextEditingController(text: v.plate);
    _vin = TextEditingController(text: v.vin);
    _insurance = TextEditingController(text: v.insurance);
    _tank = TextEditingController(
        text: v.tank1Capacity == 0 ? '' : _num(v.tank1Capacity));
    _distUnit = v.distUnit;
    _consumptionUnit = v.consumptionUnit;
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  @override
  void dispose() {
    _name.dispose();
    _make.dispose();
    _model.dispose();
    _year.dispose();
    _plate.dispose();
    _vin.dispose();
    _insurance.dispose();
    _tank.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final base = widget.vehicle ?? FuelioVehicle();
    final saved = base.copyWith(
      name: _name.text.trim(),
      make: _make.text.trim(),
      model: _model.text.trim(),
      year: _year.text.trim(),
      plate: _plate.text.trim(),
      vin: _vin.text.trim(),
      insurance: _insurance.text.trim(),
      tank1Capacity: double.tryParse(_tank.text.trim()) ?? 0,
      distUnit: _distUnit,
      consumptionUnit: _consumptionUnit,
    );
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Vehicle'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.cyan, foregroundColor: Colors.black),
              child: const Text('SAVE'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _field(_name, 'Name', required: true),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _field(_make, 'Make')),
                const SizedBox(width: 12),
                Expanded(child: _field(_model, 'Model')),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                    child: _field(_year, 'Year', number: true)),
                const SizedBox(width: 12),
                Expanded(child: _field(_plate, 'Plate')),
              ],
            ),
            const SizedBox(height: 16),
            _field(_vin, 'VIN'),
            const SizedBox(height: 16),
            _field(_insurance, 'Insurance'),
            const SizedBox(height: 16),
            _field(_tank, 'Tank capacity (litres)', number: true),
            const SizedBox(height: 16),
            _dropdown<int>(
              label: 'Distance unit',
              value: _distUnit,
              items: const {0: 'Kilometres', 1: 'Miles'},
              onChanged: (v) => setState(() => _distUnit = v),
            ),
            const SizedBox(height: 16),
            _dropdown<int>(
              label: 'Consumption unit',
              value: _consumptionUnit,
              items: const {
                0: 'L/100km',
                1: 'mpg (US)',
                2: 'mpg (UK)',
                3: 'km/L',
              },
              onChanged: (v) => setState(() => _consumptionUnit = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) =>
      DropdownButtonFormField<T>(
        value: value,
        dropdownColor: const Color(0xFF1A1A1A),
        style: const TextStyle(color: Colors.white),
        iconEnabledColor: Colors.white54,
        decoration: _decoration(label),
        items: [
          for (final e in items.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) => onChanged(v as T),
      );

  Widget _field(
    TextEditingController c,
    String label, {
    bool number = false,
    bool required = false,
  }) =>
      TextFormField(
        controller: c,
        style: const TextStyle(color: Colors.white),
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
            : null,
        validator: (v) {
          if (required && (v == null || v.trim().isEmpty)) return 'Required';
          return null;
        },
        decoration: _decoration(label),
      );

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.black26,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.cyan),
        ),
      );
}
