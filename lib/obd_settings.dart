import 'package:shared_preferences/shared_preferences.dart';

import 'bluetooth_transport.dart';
import 'obd_transport.dart';
import 'wifi_transport.dart';

enum ConnectionType { wifi, bluetooth }

/// User connection preferences, persisted across launches via
/// shared_preferences.
class ObdSettings {
  ObdSettings({
    this.type = ConnectionType.wifi,
    this.wifiHost = '192.168.0.10',
    this.wifiPort = 35000,
    this.btAddress,
    this.btName,
  });

  ConnectionType type;
  String wifiHost;
  int wifiPort;

  /// MAC address of the chosen Bluetooth adapter (null until picked).
  String? btAddress;

  /// Human-readable name of the chosen Bluetooth adapter (for display).
  String? btName;

  static const _kType = 'conn_type';
  static const _kHost = 'wifi_host';
  static const _kPort = 'wifi_port';
  static const _kBtAddr = 'bt_address';
  static const _kBtName = 'bt_name';

  static Future<ObdSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return ObdSettings(
      type: p.getString(_kType) == 'bluetooth'
          ? ConnectionType.bluetooth
          : ConnectionType.wifi,
      wifiHost: p.getString(_kHost) ?? '192.168.0.10',
      wifiPort: p.getInt(_kPort) ?? 35000,
      btAddress: p.getString(_kBtAddr),
      btName: p.getString(_kBtName),
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kType, type == ConnectionType.bluetooth ? 'bluetooth' : 'wifi');
    await p.setString(_kHost, wifiHost);
    await p.setInt(_kPort, wifiPort);
    await p.setString(_kBtAddr, btAddress ?? '');
    await p.setString(_kBtName, btName ?? '');
  }

  /// Build the transport described by these settings.
  ObdTransport buildTransport() {
    switch (type) {
      case ConnectionType.bluetooth:
        return BluetoothObdTransport(address: btAddress ?? '');
      case ConnectionType.wifi:
        return WifiObdTransport(host: wifiHost, port: wifiPort);
    }
  }

  /// Whether the current settings are usable (BT needs a chosen device).
  bool get isComplete =>
      type == ConnectionType.wifi ||
      (btAddress != null && btAddress!.isNotEmpty);
}
