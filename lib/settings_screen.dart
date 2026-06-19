import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import 'obd_settings.dart';

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

  List<BluetoothDevice> _bonded = [];
  bool _loadingDevices = false;
  String? _btError;

  @override
  void initState() {
    super.initState();
    _type = widget.settings.type;
    _host = TextEditingController(text: widget.settings.wifiHost);
    _port = TextEditingController(text: '${widget.settings.wifiPort}');
    _btAddress = widget.settings.btAddress;
    _btName = widget.settings.btName;
    if (_type == ConnectionType.bluetooth) _loadBondedDevices();
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
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

  void _save() {
    final result = ObdSettings(
      type: _type,
      wifiHost: _host.text.trim().isEmpty ? '192.168.0.10' : _host.text.trim(),
      wifiPort: int.tryParse(_port.text.trim()) ?? 35000,
      btAddress: _btAddress,
      btName: _btName,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        ],
      ),
    );
  }

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
