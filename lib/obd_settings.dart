import 'package:shared_preferences/shared_preferences.dart';

import 'bluetooth_transport.dart';
import 'obd_transport.dart';
import 'wifi_transport.dart';

enum ConnectionType { wifi, bluetooth }

/// Which HUD layout to render.
/// [number] = big km/L digits with throttle/speed/rpm (Template 1).
/// [bar] = 0–50 km/L bar + number only (Template 2).
enum HudTemplate { number, bar }

/// User connection preferences, persisted across launches via
/// shared_preferences.
class ObdSettings {
  ObdSettings({
    this.type = ConnectionType.wifi,
    this.wifiHost = '192.168.0.10',
    this.wifiPort = 35000,
    this.btAddress,
    this.btName,
    this.mirror = false,
    this.template = HudTemplate.number,
    this.hudColor = defaultHudColor,
  });

  /// Default HUD accent (cyan) when the user hasn't picked one.
  static const int defaultHudColor = 0xFF18FFFF; // Colors.cyanAccent

  ConnectionType type;
  String wifiHost;
  int wifiPort;

  /// Which HUD layout to show (Template 1 = number, Template 2 = bar graph).
  HudTemplate template;

  /// ARGB value of the HUD readout colour the user chose.
  int hudColor;

  /// Horizontally flip the HUD so it reads correctly when reflected off the
  /// windshield.
  bool mirror;

  /// MAC address of the chosen Bluetooth adapter (null until picked).
  String? btAddress;

  /// Human-readable name of the chosen Bluetooth adapter (for display).
  String? btName;

  static const _kType = 'conn_type';
  static const _kHost = 'wifi_host';
  static const _kPort = 'wifi_port';
  static const _kBtAddr = 'bt_address';
  static const _kBtName = 'bt_name';
  static const _kMirror = 'mirror';
  static const _kTemplate = 'template';
  static const _kColor = 'hud_color';

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
      mirror: p.getBool(_kMirror) ?? false,
      template: p.getInt(_kTemplate) == 1
          ? HudTemplate.bar
          : HudTemplate.number,
      hudColor: p.getInt(_kColor) ?? defaultHudColor,
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
    await p.setBool(_kMirror, mirror);
    await p.setInt(_kTemplate, template == HudTemplate.bar ? 1 : 0);
    await p.setInt(_kColor, hudColor);
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
