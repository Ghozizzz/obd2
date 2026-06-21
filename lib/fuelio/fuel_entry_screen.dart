import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fuelio_models.dart';

/// Add or edit a single fuel fill-up. Returns the saved [FuelEntry] via
/// Navigator.pop, or null if cancelled.
class FuelEntryScreen extends StatefulWidget {
  const FuelEntryScreen({super.key, this.entry});

  /// The entry to edit, or null to create a new one.
  final FuelEntry? entry;

  @override
  State<FuelEntryScreen> createState() => _FuelEntryScreenState();
}

class _FuelEntryScreenState extends State<FuelEntryScreen> {
  final _form = GlobalKey<FormState>();
  late DateTime _date;
  late TextEditingController _odo;
  late TextEditingController _fuel;
  late TextEditingController _price;
  late TextEditingController _city;
  late TextEditingController _notes;
  late bool _full;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _date = e?.date ?? DateTime.now();
    _odo = TextEditingController(text: e == null ? '' : _num(e.odo));
    _fuel = TextEditingController(text: e == null ? '' : _num(e.fuel));
    _price = TextEditingController(text: e == null ? '' : _num(e.price));
    _city = TextEditingController(text: e?.city ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _full = e?.full ?? true;
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  @override
  void dispose() {
    _odo.dispose();
    _fuel.dispose();
    _price.dispose();
    _city.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    if (!mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    setState(() => _date = DateTime(
        d.year, d.month, d.day, t?.hour ?? _date.hour, t?.minute ?? _date.minute));
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final fuel = double.tryParse(_fuel.text.trim()) ?? 0;
    final price = double.tryParse(_price.text.trim()) ?? 0;
    final base = widget.entry ?? FuelEntry(date: _date);
    final saved = base.copyWith(
      date: _date,
      odo: double.tryParse(_odo.text.trim()) ?? 0,
      fuel: fuel,
      price: price,
      full: _full,
      city: _city.text.trim(),
      notes: _notes.text.trim(),
      volumePrice: fuel > 0 ? price / fuel : 0,
    );
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.entry != null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(editing ? 'Edit Fill-up' : 'Add Fill-up'),
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
            _dateTile(),
            const SizedBox(height: 16),
            _field(_odo, 'Odometer (km)', number: true),
            const SizedBox(height: 16),
            _field(_fuel, 'Fuel (litres)', number: true, required: true),
            const SizedBox(height: 16),
            _field(_price, 'Total price', number: true),
            const SizedBox(height: 16),
            _field(_city, 'City (optional)'),
            const SizedBox(height: 16),
            _field(_notes, 'Notes (optional)', maxLines: 3),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: Colors.cyan,
              value: _full,
              onChanged: (v) => setState(() => _full = v),
              title: const Text('Full tank',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Filled all the way up',
                  style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateTile() => Material(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: const Icon(Icons.event, color: Colors.cyan),
          title: Text(fmtFuelioDate(_date),
              style: const TextStyle(color: Colors.white)),
          subtitle: const Text('Date & time',
              style: TextStyle(color: Colors.white54)),
          trailing: const Icon(Icons.edit, color: Colors.white38, size: 18),
          onTap: _pickDate,
        ),
      );

  Widget _field(
    TextEditingController c,
    String label, {
    bool number = false,
    bool required = false,
    int maxLines = 1,
  }) =>
      TextFormField(
        controller: c,
        style: const TextStyle(color: Colors.white),
        maxLines: maxLines,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
            : null,
        validator: (v) {
          if (required && (v == null || v.trim().isEmpty)) return 'Required';
          if (number && v != null && v.trim().isNotEmpty) {
            if (double.tryParse(v.trim()) == null) return 'Enter a number';
          }
          return null;
        },
        decoration: InputDecoration(
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
        ),
      );
}
