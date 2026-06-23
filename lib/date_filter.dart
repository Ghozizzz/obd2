import 'package:flutter/material.dart';

/// Preset windows offered by the date filter. [thisYear] is the default —
/// 1 Jan of the current year through today.
enum DateRangePreset { thisYear, last3Months, last6Months, last12Months, custom }

/// A date-range filter shared by the logbook and trip history. Holds the
/// selected [preset] plus an explicit [customStart]/[customEnd] pair used only
/// when [preset] is [DateRangePreset.custom].
///
/// [start]/[end] resolve the preset against "now" each time they are read, so a
/// filter created yesterday still means "this year" today.
class DateFilter {
  const DateFilter({
    this.preset = DateRangePreset.thisYear,
    this.customStart,
    this.customEnd,
  });

  final DateRangePreset preset;
  final DateTime? customStart;
  final DateTime? customEnd;

  /// Inclusive start of the window (midnight).
  DateTime get start {
    final now = DateTime.now();
    switch (preset) {
      case DateRangePreset.thisYear:
        return DateTime(now.year, 1, 1);
      case DateRangePreset.last3Months:
        return DateTime(now.year, now.month - 3, now.day);
      case DateRangePreset.last6Months:
        return DateTime(now.year, now.month - 6, now.day);
      case DateRangePreset.last12Months:
        return DateTime(now.year, now.month - 12, now.day);
      case DateRangePreset.custom:
        final s = customStart ?? DateTime(now.year, 1, 1);
        return DateTime(s.year, s.month, s.day);
    }
  }

  /// Inclusive end of the window (end of day). Presets always run up to today.
  DateTime get end {
    final now = DateTime.now();
    if (preset == DateRangePreset.custom && customEnd != null) {
      final e = customEnd!;
      return DateTime(e.year, e.month, e.day, 23, 59, 59, 999);
    }
    return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  }

  /// Whether [d] falls inside the inclusive [start]..[end] window.
  bool contains(DateTime d) => !d.isBefore(start) && !d.isAfter(end);

  /// Short label for the active window, shown on the filter bar.
  String get label {
    switch (preset) {
      case DateRangePreset.thisYear:
        return 'This year';
      case DateRangePreset.last3Months:
        return 'Last 3 months';
      case DateRangePreset.last6Months:
        return 'Last 6 months';
      case DateRangePreset.last12Months:
        return 'Last 12 months';
      case DateRangePreset.custom:
        return '${_fmt(start)} → ${_fmt(end)}';
    }
  }

  DateFilter copyWith({
    DateRangePreset? preset,
    DateTime? customStart,
    DateTime? customEnd,
  }) =>
      DateFilter(
        preset: preset ?? this.preset,
        customStart: customStart ?? this.customStart,
        customEnd: customEnd ?? this.customEnd,
      );

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _fmt(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
}

/// A tappable pill showing the active [filter]'s window. Tapping opens a sheet
/// to pick a preset or a custom start/end range; the chosen filter is reported
/// through [onChanged].
class DateFilterBar extends StatelessWidget {
  const DateFilterBar({
    super.key,
    required this.filter,
    required this.onChanged,
  });

  final DateFilter filter;
  final ValueChanged<DateFilter> onChanged;

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<DateFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _FilterSheet(filter: filter),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event, color: Colors.cyan, size: 18),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  filter.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.expand_more, color: Colors.white54, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterSheet extends StatelessWidget {
  const _FilterSheet({required this.filter});

  final DateFilter filter;

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final initial = filter.preset == DateRangePreset.custom &&
            filter.customStart != null &&
            filter.customEnd != null
        ? DateTimeRange(start: filter.customStart!, end: filter.customEnd!)
        : DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initial,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.cyan,
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A1A),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (range == null) return;
    if (!context.mounted) return;
    Navigator.pop(
      context,
      DateFilter(
        preset: DateRangePreset.custom,
        customStart: range.start,
        customEnd: range.end,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget tile(DateRangePreset preset, IconData icon, String text) {
      final selected = filter.preset == preset;
      return ListTile(
        leading: Icon(icon, color: selected ? Colors.cyan : Colors.white54),
        title: Text(text,
            style: TextStyle(
                color: selected ? Colors.cyan : Colors.white,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
        trailing: selected
            ? const Icon(Icons.check, color: Colors.cyan, size: 20)
            : null,
        onTap: () => Navigator.pop(context, DateFilter(preset: preset)),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Filter by date',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          tile(DateRangePreset.thisYear, Icons.today, 'This year'),
          tile(DateRangePreset.last3Months, Icons.calendar_view_month,
              'Last 3 months'),
          tile(DateRangePreset.last6Months, Icons.calendar_view_month,
              'Last 6 months'),
          tile(DateRangePreset.last12Months, Icons.calendar_today,
              'Last 12 months'),
          ListTile(
            leading: Icon(Icons.date_range,
                color: filter.preset == DateRangePreset.custom
                    ? Colors.cyan
                    : Colors.white54),
            title: Text(
              filter.preset == DateRangePreset.custom
                  ? 'Custom: ${filter.label}'
                  : 'Custom range…',
              style: TextStyle(
                  color: filter.preset == DateRangePreset.custom
                      ? Colors.cyan
                      : Colors.white,
                  fontWeight: filter.preset == DateRangePreset.custom
                      ? FontWeight.w600
                      : FontWeight.normal),
            ),
            onTap: () => _pickCustom(context),
          ),
          const SizedBox(height: 8),
        ],
        ),
      ),
    );
  }
}
