import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fuelio_models.dart';

/// Add or edit a single cost / income entry. Returns the saved [CostEntry] via
/// Navigator.pop, or null if cancelled.
class CostEntryScreen extends StatefulWidget {
  const CostEntryScreen({super.key, this.entry, required this.categories});

  final CostEntry? entry;
  final List<CostCategory> categories;

  @override
  State<CostEntryScreen> createState() => _CostEntryScreenState();
}

class _CostEntryScreenState extends State<CostEntryScreen> {
  final _form = GlobalKey<FormState>();
  late DateTime _date;
  late TextEditingController _title;
  late TextEditingController _odo;
  late TextEditingController _cost;
  late TextEditingController _notes;
  late int _categoryId;
  late bool _isIncome;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _date = e?.date ?? DateTime.now();
    _title = TextEditingController(text: e?.title ?? '');
    _odo = TextEditingController(
        text: e == null || e.odo == 0 ? '' : e.odo.toStringAsFixed(0));
    _cost = TextEditingController(
        text: e == null ? '' : _num(e.cost));
    _notes = TextEditingController(text: e?.notes ?? '');
    _isIncome = e?.isIncome ?? false;
    final ids = widget.categories.map((c) => c.id).toSet();
    _categoryId = e != null && ids.contains(e.costTypeId)
        ? e.costTypeId
        : (widget.categories.isNotEmpty ? widget.categories.first.id : 1);
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  @override
  void dispose() {
    _title.dispose();
    _odo.dispose();
    _cost.dispose();
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
    setState(() => _date = DateTime(d.year, d.month, d.day, t?.hour ?? _date.hour,
        t?.minute ?? _date.minute));
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final base = widget.entry ?? CostEntry(title: '', date: _date);
    final saved = base.copyWith(
      title: _title.text.trim(),
      date: _date,
      odo: double.tryParse(_odo.text.trim()) ?? 0,
      costTypeId: _categoryId,
      notes: _notes.text.trim(),
      cost: double.tryParse(_cost.text.trim()) ?? 0,
      isIncome: _isIncome,
    );
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.entry != null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(editing ? 'Edit Cost' : 'Add Cost'),
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
            _field(_title, 'Title', required: true),
            const SizedBox(height: 16),
            _dateTile(),
            const SizedBox(height: 16),
            _categoryDropdown(),
            const SizedBox(height: 16),
            _field(_cost, 'Amount', number: true, required: true),
            const SizedBox(height: 16),
            _field(_odo, 'Odometer (km, optional)', number: true),
            const SizedBox(height: 16),
            _field(_notes, 'Notes (optional)', maxLines: 3),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: Colors.cyan,
              value: _isIncome,
              onChanged: (v) => setState(() => _isIncome = v),
              title: const Text('Income',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Money received rather than spent',
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

  Widget _categoryDropdown() => DropdownButtonFormField<int>(
        value: _categoryId,
        dropdownColor: const Color(0xFF1A1A1A),
        style: const TextStyle(color: Colors.white),
        iconEnabledColor: Colors.white54,
        decoration: _decoration('Category'),
        items: [
          for (final c in widget.categories)
            DropdownMenuItem(value: c.id, child: Text(c.name)),
        ],
        onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
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
