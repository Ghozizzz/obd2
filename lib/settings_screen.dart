import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import 'obd_settings.dart';
import 'preview_screen.dart';

/// Connection settings: choose WiFi or Bluetooth and configure each. Returns
/// the updated [ObdSettings] via Navigator.pop, or null if cancelled.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings});

  final ObdSettings settings;

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
        appBar: AppBar(
          title: const Text('Connection'),
          actions: [
            TextButton(
              onPressed: _save,
              child: const Text('SAVE'),
            ),
          ],
        ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RadioListTile<ConnectionType>(
            title: const Text('WiFi (ELM327 WiFi adapter)'),
            subtitle: const Text('Join the adapter\'s WiFi network first'),
            value: ConnectionType.wifi,
            groupValue: _type,
            onChanged: (v) => setState(() => _type = v!),
          ),
          RadioListTile<ConnectionType>(
            title: const Text('Bluetooth (ELM327 BT adapter)'),
            subtitle: const Text('Pair the adapter in Android settings first'),
            value: ConnectionType.bluetooth,
            groupValue: _type,
            onChanged: (v) {
              setState(() => _type = v!);
              if (_bonded.isEmpty) _loadBondedDevices();
            },
          ),
          const Divider(height: 32),
          if (_type == ConnectionType.wifi) ..._wifiFields() else ..._btFields(),
          const Divider(height: 32),
          SwitchListTile(
            title: const Text('Mirror display'),
            subtitle: const Text(
                'Flip horizontally for windshield-reflected HUD viewing'),
            value: _mirror,
            onChanged: (v) => setState(() => _mirror = v),
          ),
          const Divider(height: 32),
          const Text('HUD template',
              style: TextStyle(fontWeight: FontWeight.bold)),
          RadioListTile<HudTemplate>(
            title: const Text('Template 1 — big km/L number'),
            value: HudTemplate.number,
            groupValue: _template,
            onChanged: (v) => setState(() => _template = v!),
          ),
          RadioListTile<HudTemplate>(
            title: const Text('Template 2 — 0–50 km/L bar'),
            subtitle: const Text('Bar graph + number only, no other stats'),
            value: HudTemplate.bar,
            groupValue: _template,
            onChanged: (v) => setState(() => _template = v!),
          ),
          const Divider(height: 32),
          ..._colorFields(),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Preview (10s test, no connection)'),
            onPressed: _preview,
          ),
        ],
      ),
      ),
    );
  }

  List<Widget> _colorFields() => [
        Row(
          children: [
            const Text('HUD colour',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            // Live preview of the current colour.
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color(_hudColor),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
          decoration: InputDecoration(
            labelText: 'Hex colour',
            hintText: '#FFEB3B',
            prefixIcon: const Icon(Icons.tag),
            errorText: _hexError,
          ),
          autocorrect: false,
          onChanged: _onHexChanged,
        ),
      ];

  List<Widget> _wifiFields() => [
        TextField(
          controller: _host,
          decoration: const InputDecoration(
            labelText: 'Host / IP',
            hintText: '192.168.0.10',
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _port,
          decoration: const InputDecoration(
            labelText: 'Port',
            hintText: '35000',
          ),
          keyboardType: TextInputType.number,
        ),
      ];

  List<Widget> _btFields() => [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Paired devices',
                style: TextStyle(fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.refresh),
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
            padding: EdgeInsets.all(8),
            child: Text(
                'No paired devices found. Pair your ELM327 in Android '
                'Bluetooth settings (PIN is usually 1234 or 0000), then tap '
                'refresh.'),
          ),
        ..._bonded.map((d) => RadioListTile<String>(
              title: Text(d.name ?? d.address),
              subtitle: Text(d.address),
              value: d.address,
              groupValue: _btAddress,
              onChanged: (v) => setState(() {
                _btAddress = v;
                _btName = d.name;
              }),
            )),
      ];
}
