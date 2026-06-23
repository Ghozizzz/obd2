import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'app_info.dart';
import 'fuelio/fuelio_store.dart';
import 'fuelio/logbook_screen.dart';
import 'hud_screen.dart';
import 'monitor_screen.dart';
import 'obd_service.dart';
import 'obd_settings.dart';
import 'settings_screen.dart';
import 'trip_store.dart';
import 'trips_screen.dart';

/// App home. Owns the connection lifecycle (loads settings, builds the
/// [ObdService], connects) and — once the adapter is reachable — presents a
/// simple menu: open the live fuel-consumption HUD, or edit settings.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ObdSettings? _settings;
  ObdService? _service;
  TripStore? _tripStore;
  FuelioStore? _fuelioStore;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final settings = await ObdSettings.load();
    final service = ObdService(settings.buildTransport());
    // Trip history is best-effort: if the DB fails to open, the HUD still runs.
    TripStore? store;
    try {
      store = await TripStore.open();
      // In debug builds, seed demo trips so the history screen has something to
      // show without a live drive. No-op once real trips exist.
      if (kDebugMode) await store.seedSampleData();
    } catch (_) {
      store = null;
    }
    // Fuelio logbook store is likewise best-effort.
    FuelioStore? fuelio;
    try {
      fuelio = await FuelioStore.open();
    } catch (_) {
      fuelio = null;
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _service = service;
      _tripStore = store;
      _fuelioStore = fuelio;
    });
    service.start();
  }

  @override
  void dispose() {
    _service?.dispose();
    _tripStore?.close();
    _fuelioStore?.close();
    super.dispose();
  }

  Future<void> _openSettings() async {
    final current = _settings;
    final service = _service;
    if (current == null || service == null) return;
    final updated = await Navigator.of(context).push<ObdSettings>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          settings: current,
          tripStore: _tripStore,
          fuelioStore: _fuelioStore,
        ),
      ),
    );
    if (updated == null) return;
    await updated.save();
    if (!mounted) return;
    setState(() => _settings = updated);
    // Reconnect with the newly chosen transport.
    await service.restart(updated.buildTransport());
  }

  void _openHud() {
    final service = _service;
    final settings = _settings;
    if (service == null || settings == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HudScreen(
          service: service,
          settings: settings,
          tripStore: _tripStore,
        ),
      ),
    );
  }

  void _openMonitor() {
    final service = _service;
    if (service == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MonitorScreen(service: service)),
    );
  }

  void _openTrips() {
    final store = _tripStore;
    if (store == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TripsScreen(store: store)),
    );
  }

  void _openLogbook() {
    final store = _fuelioStore;
    if (store == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LogbookScreen(store: store)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (service == null)
              const Center(child: CircularProgressIndicator())
            else
              StreamBuilder<ObdData>(
                stream: service.stream,
                initialData: service.current,
                builder: (context, snap) {
                  final d = snap.data ?? const ObdData();
                  return _menu(d);
                },
              ),
            const Positioned(
              left: 16,
              bottom: 12,
              child: Text(
                'v$kAppVersion',
                style: TextStyle(color: Colors.white24, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu(ObdData d) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            const Text(
              'ExCar',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            _status(d),
            const SizedBox(height: 28),
            _menuTile(
              icon: Icons.local_gas_station,
              label: 'Live Fuel Consumption',
              subtitle: d.connected
                  ? 'Open the km/L HUD'
                  : 'Waiting for the adapter…',
              enabled: d.connected,
              onTap: _openHud,
            ),
            const SizedBox(height: 16),
            _menuTile(
              icon: Icons.cable,
              label: 'CAN Bus / Button Tester',
              subtitle: d.connected
                  ? 'Sniff frames — test wheel/cruise buttons'
                  : 'Waiting for the adapter…',
              enabled: d.connected,
              onTap: _openMonitor,
            ),
            const SizedBox(height: 16),
            _menuTile(
              icon: Icons.history,
              label: 'Trip History',
              subtitle: _tripStore == null
                  ? 'Unavailable on this device'
                  : 'Past journeys — distance, fuel & avg km/L',
              enabled: _tripStore != null,
              onTap: _openTrips,
            ),
            const SizedBox(height: 16),
            _menuTile(
              icon: Icons.menu_book,
              label: 'Fuel & Cost Logbook',
              subtitle: _fuelioStore == null
                  ? 'Unavailable on this device'
                  : 'Import Fuelio CSV, log fill-ups & costs',
              enabled: _fuelioStore != null,
              onTap: _openLogbook,
            ),
            const SizedBox(height: 16),
            _menuTile(
              icon: Icons.settings,
              label: 'Settings',
              subtitle: 'Connection, template & colour',
              enabled: true,
              onTap: _openSettings,
            ),
          ],
        ),
      ),
    );
  }

  /// Connection status line: connected, connecting, or the last error.
  Widget _status(ObdData d) {
    final Color color;
    final String text;
    if (d.connected) {
      color = Colors.greenAccent;
      text = 'Connected';
    } else if (d.error != null) {
      color = Colors.redAccent;
      text = d.error!;
    } else {
      color = Colors.amberAccent;
      text = 'Connecting to ELM327…';
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!d.connected && d.error == null)
          const Padding(
            padding: EdgeInsets.only(right: 10),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              d.connected ? Icons.check_circle : Icons.error_outline,
              size: 16,
              color: color,
            ),
          ),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final fg = enabled ? Colors.white : Colors.white24;
    return Material(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Icon(icon, color: fg, size: 32),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: fg,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: enabled ? Colors.white54 : Colors.white24,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
