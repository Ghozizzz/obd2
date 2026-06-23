import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'backup.dart';
import 'fuelio/fuelio_store.dart';
import 'obd_settings.dart';
import 'preview_screen.dart';
import 'trip_store.dart';

/// Connection settings: choose WiFi or Bluetooth and configure each. Returns
/// the updated [ObdSettings] via Navigator.pop, or null if cancelled.
///
/// Also hosts "Export All" / "Restore" — a full backup of trip history and the
/// fuel & cost logbook to a single JSON file, for moving to another phone.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    this.tripStore,
    this.fuelioStore,
  });

  final ObdSettings settings;
  final TripStore? tripStore;
  final FuelioStore? fuelioStore;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ConnectionType _type;
  late TextEditingController _host;
  late TextEditingController _port;
  String? _btAddress;
  String? _btName;
  late bool _mirror;
  late HudTemplate _template;

  /// Currently chosen HUD colour and the hex text field driving it.
  late int _hudColor;
  late TextEditingController _hex;
  String? _hexError;

  List<BluetoothDevice> _bonded = [];
  bool _loadingDevices = false;
  String? _btError;

  /// True while an export/restore is running (disables the buttons).
  bool _backupBusy = false;

  /// A handful of high-contrast presets for the swatch picker.
  static const _swatches = <int>[
    0xFFFFEB3B, // yellow (default)
    0xFF18FFFF, // cyan
    0xFFFFFFFF, // white
    0xFFFFC107, // amber
    0xFF4CAF50, // green
    0xFFF44336, // red
    0xFF2196F3, // blue
    0xFF9C27B0, // purple
    0xFFFF9800, // orange
    0xFFE91E63, // pink
    0xFFCDDC39, // lime
  ];

  /// "#RRGGBB" (or "#AARRGGBB") → ARGB int, or null if not a valid hex colour.
  static int? _parseHex(String input) {
    var s = input.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(s)) return null;
    if (s.length == 6) s = 'FF$s'; // assume fully opaque
    if (s.length != 8) return null;
    return int.parse(s, radix: 16);
  }

  /// ARGB int → "#RRGGBB" for display (alpha dropped).
  static String _toHex(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  void initState() {
    super.initState();
    _type = widget.settings.type;
    _host = TextEditingController(text: widget.settings.wifiHost);
    _port = TextEditingController(text: '${widget.settings.wifiPort}');
    _btAddress = widget.settings.btAddress;
    _btName = widget.settings.btName;
    _mirror = widget.settings.mirror;
    _template = widget.settings.template;
    _hudColor = widget.settings.hudColor;
    _hex = TextEditingController(text: _toHex(_hudColor));
    if (_type == ConnectionType.bluetooth) _loadBondedDevices();
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _hex.dispose();
    super.dispose();
  }

  /// Apply a hex string from the text field: update the colour if valid,
  /// otherwise show a warning and keep the previous colour.
  void _onHexChanged(String value) {
    final parsed = _parseHex(value);
    setState(() {
      if (parsed == null) {
        _hexError = 'Invalid hex colour — use #RRGGBB (e.g. #FFEB3B)';
      } else {
        _hexError = null;
        _hudColor = parsed;
      }
    });
  }

  /// Pick a swatch: update the colour and sync the hex field.
  void _pickSwatch(int argb) {
    setState(() {
      _hudColor = argb;
      _hexError = null;
      _hex.text = _toHex(argb);
    });
  }

  /// Request the runtime permissions Bluetooth Classic needs (Android 12+
  /// requires BLUETOOTH_CONNECT/SCAN; older needs location for discovery).
  Future<bool> _ensureBtPermissions() async {
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();
    // On older Android the new BT perms report as granted/n-a; treat connect
    // or scan being granted as good enough to proceed.
    final connect = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    final scan = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    return connect || scan;
  }

  Future<void> _loadBondedDevices() async {
    setState(() {
      _loadingDevices = true;
      _btError = null;
    });
    try {
      await _ensureBtPermissions();
      final bt = FlutterBluetoothSerial.instance;
      // Make sure the radio is on.
      final enabled = await bt.isEnabled ?? false;
      if (!enabled) {
        await bt.requestEnable();
      }
      final devices = await bt.getBondedDevices();
      if (!mounted) return;
      setState(() => _bonded = devices);
    } catch (e) {
      if (!mounted) return;
      setState(() => _btError = '$e');
    } finally {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  void _preview() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PreviewScreen(
            template: _template, mirror: _mirror, color: Color(_hudColor)),
      ),
    );
  }

  void _save() {
    final result = ObdSettings(
      type: _type,
      wifiHost: _host.text.trim().isEmpty ? '192.168.0.10' : _host.text.trim(),
      wifiPort: int.tryParse(_port.text.trim()) ?? 35000,
      btAddress: _btAddress,
      btName: _btName,
      mirror: _mirror,
      template: _template,
      hudColor: _hudColor,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // Intercept the back arrow / system back so leaving the screen still
      // returns the chosen settings (template/mirror/colour) instead of null.
      // _save() does the actual pop with the result, so we return false here.
      onWillPop: () async {
        _save();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Settings'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.cyan,
                  foregroundColor: Colors.black,
                ),
                child: const Text('SAVE'),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _section(
              icon: Icons.settings_input_antenna,
              title: 'Connection',
              children: [
                _connectionTypeSelector(),
                const SizedBox(height: 8),
                if (_type == ConnectionType.wifi)
                  ..._wifiFields()
                else
                  ..._btFields(),
              ],
            ),
            _section(
              icon: Icons.palette,
              title: 'HUD Colour',
              children: _colorFields(),
            ),
            _section(
              icon: Icons.dashboard_customize,
              title: 'HUD Template',
              children: _templateFields(),
            ),
            _section(
              icon: Icons.flip,
              title: 'Display',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: Colors.cyan,
                  title: const Text('Mirror display',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                    'Flip horizontally for windshield-reflected HUD viewing',
                    style: TextStyle(color: Colors.white54),
                  ),
                  value: _mirror,
                  onChanged: (v) => setState(() => _mirror = v),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Preview (10s test, no connection)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.cyan,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _preview,
                  ),
                ),
              ],
            ),
            _section(
              icon: Icons.backup,
              title: 'Backup & Restore',
              children: _backupFields(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Backup / restore ───────────────────────────────────────────────────────

  List<Widget> _backupFields() => [
        const Text(
          'Save all trip history and the fuel & cost logbook to a single file, '
          'then restore it on another phone.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: _backupBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.file_download_outlined),
            label: const Text('Export All'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.cyan,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _backupBusy ? null : _exportAll,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('Restore from file'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.cyan,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _backupBusy ? null : _restoreAll,
          ),
        ),
      ];

  Future<void> _exportAll() async {
    setState(() => _backupBusy = true);
    try {
      final now = DateTime.now();
      final json = await BackupService.exportAll(
        trips: widget.tripStore,
        fuelio: widget.fuelioStore,
        now: now,
      );

      Directory dir;
      try {
        dir = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
      } catch (_) {
        dir = await getApplicationDocumentsDirectory();
      }
      final path = p.join(dir.path, BackupService.fileName(now));
      await File(path).writeAsString(json);
      if (!mounted) return;
      _showInfoDialog('Exported', path, selectable: true);
    } catch (e) {
      _toast('Export failed: $e');
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _restoreAll() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'txt'],
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

      setState(() => _backupBusy = true);
      final summary = await BackupService.importAll(
        content,
        trips: widget.tripStore,
        fuelio: widget.fuelioStore,
      );
      if (!mounted) return;

      final f = summary.fuelio;
      final lines = <String>[
        '${summary.tripsAdded} trips added'
            '${summary.tripsSkipped > 0 ? ' (${summary.tripsSkipped} duplicates skipped)' : ''}',
        if (f != null)
          '${f.logsAdded} fuel fill-ups added'
              '${f.logsSkipped > 0 ? ' (${f.logsSkipped} skipped)' : ''}',
        if (f != null)
          '${f.costsAdded} costs added'
              '${f.costsSkipped > 0 ? ' (${f.costsSkipped} skipped)' : ''}',
      ];
      _showInfoDialog('Restore complete', lines.join('\n'));
    } catch (e) {
      _toast('Restore failed: $e');
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  void _showInfoDialog(String title, String body, {bool selectable = false}) =>
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: selectable
              ? SelectableText(body,
                  style: const TextStyle(color: Colors.white70, fontSize: 13))
              : Text(body,
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
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

  /// A titled card grouping related settings — the building block of the page.
  Widget _section({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.cyan),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  /// WiFi / Bluetooth chooser as a pair of pill-style segmented buttons.
  Widget _connectionTypeSelector() {
    Widget pill(ConnectionType type, IconData icon, String label) {
      final selected = _type == type;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            setState(() => _type = type);
            if (type == ConnectionType.bluetooth && _bonded.isEmpty) {
              _loadBondedDevices();
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: selected ? Colors.cyan.withOpacity(0.18) : Colors.white10,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? Colors.cyan : Colors.white12,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(icon,
                    color: selected ? Colors.cyan : Colors.white54, size: 26),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white54,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        pill(ConnectionType.wifi, Icons.wifi, 'WiFi'),
        const SizedBox(width: 12),
        pill(ConnectionType.bluetooth, Icons.bluetooth, 'Bluetooth'),
      ],
    );
  }

  List<Widget> _templateFields() => [
        _templateOption(
          template: HudTemplate.number,
          title: 'Big km/L number',
          subtitle: 'Large readout with throttle, speed, L/h & RPM',
        ),
        const SizedBox(height: 10),
        _templateOption(
          template: HudTemplate.bar,
          title: '0–50 km/L bar',
          subtitle: 'Bar graph + number only, no other stats',
        ),
      ];

  Widget _templateOption({
    required HudTemplate template,
    required String title,
    required String subtitle,
  }) {
    final selected = _template == template;
    return GestureDetector(
      onTap: () => setState(() => _template = template),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.cyan.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.cyan : Colors.white12,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? Colors.cyan : Colors.white38,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dark-theme decoration shared by the text inputs on this page.
  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    Widget? prefixIcon,
    String? errorText,
  }) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon,
        errorText: errorText,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24),
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

  List<Widget> _colorFields() => [
        // Live preview of the current colour next to a short hint.
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color(_hudColor),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
            ),
            const SizedBox(width: 12),
            const Text('Tap a swatch or enter a hex code',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 14),
        // Swatch picker.
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _swatches.map((argb) {
            final selected = (argb & 0xFFFFFF) == (_hudColor & 0xFFFFFF);
            return GestureDetector(
              onTap: () => _pickSwatch(argb),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Color(argb),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? Colors.white : Colors.white24,
                    width: selected ? 3 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        // Manual hex entry with validation.
        TextField(
          controller: _hex,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration(
            label: 'Hex colour',
            hint: '#FFEB3B',
            prefixIcon: const Icon(Icons.tag, color: Colors.white38),
            errorText: _hexError,
          ),
          autocorrect: false,
          onChanged: _onHexChanged,
        ),
      ];

  List<Widget> _wifiFields() => [
        const Text('Join the adapter\'s WiFi network first',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 14),
        TextField(
          controller: _host,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration(label: 'Host / IP', hint: '192.168.0.10'),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _port,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration(label: 'Port', hint: '35000'),
          keyboardType: TextInputType.number,
        ),
      ];

  List<Widget> _btFields() => [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Paired devices',
                style: TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.w500)),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.cyan),
              onPressed: _loadingDevices ? null : _loadBondedDevices,
            ),
          ],
        ),
        if (_loadingDevices)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_btError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_btError!,
                style: const TextStyle(color: Colors.redAccent)),
          ),
        if (!_loadingDevices && _bonded.isEmpty && _btError == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No paired devices found. Pair your ELM327 in Android '
              'Bluetooth settings (PIN is usually 1234 or 0000), then tap '
              'refresh.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ..._bonded.map((d) {
          final selected = _btAddress == d.address;
          return GestureDetector(
            onTap: () => setState(() {
              _btAddress = d.address;
              _btName = d.name;
            }),
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color:
                    selected ? Colors.cyan.withOpacity(0.12) : Colors.black26,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? Colors.cyan : Colors.white12,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected ? Colors.cyan : Colors.white38,
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name ?? d.address,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(d.address,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ];
}
