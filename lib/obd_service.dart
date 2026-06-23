import 'dart:async';

import 'fuel_calc.dart';
import 'obd_transport.dart';
import 'pids.dart';

/// Snapshot of the latest decoded values for the UI.
class ObdData {
  const ObdData({
    this.kmPerLiter = 0,
    this.avgKmPerLiter = 0,
    this.litersPerHour = 0,
    this.throttle = 0,
    this.speed = 0,
    this.rpm = 0,
    this.mafSupported = true,
    this.connected = false,
    this.error,
  });

  final double kmPerLiter;
  /// Running session average km/L (distance-weighted: Σ speed / Σ L·h).
  final double avgKmPerLiter;
  final double litersPerHour;
  final double throttle; // %
  final int speed;       // km/h
  final int rpm;
  final bool mafSupported;
  final bool connected;
  final String? error;

  ObdData copyWith({
    double? kmPerLiter,
    double? avgKmPerLiter,
    double? litersPerHour,
    double? throttle,
    int? speed,
    int? rpm,
    bool? mafSupported,
    bool? connected,
    String? error,
  }) =>
      ObdData(
        kmPerLiter: kmPerLiter ?? this.kmPerLiter,
        avgKmPerLiter: avgKmPerLiter ?? this.avgKmPerLiter,
        litersPerHour: litersPerHour ?? this.litersPerHour,
        throttle: throttle ?? this.throttle,
        speed: speed ?? this.speed,
        rpm: rpm ?? this.rpm,
        mafSupported: mafSupported ?? this.mafSupported,
        connected: connected ?? this.connected,
        error: error,
      );
}

/// Connects to the adapter and polls the fuel-relevant PIDs in a loop,
/// emitting [ObdData] snapshots on [stream].
class ObdService {
  ObdService(this._transport);

  ObdTransport _transport;
  final _controller = StreamController<ObdData>.broadcast();
  ObdData _state = const ObdData();
  bool _running = false;
  Future<void>? _loopDone;

  // Accumulators for the distance-weighted session average km/L.
  double _sumSpeed = 0;
  double _sumLh = 0;

  Stream<ObdData> get stream => _controller.stream;
  ObdData get current => _state;

  /// Swap to a new transport (e.g. WiFi → Bluetooth) and reconnect.
  Future<void> restart(ObdTransport transport) async {
    await stop();
    _transport = transport;
    await start();
  }

  /// Stop the poll loop without disconnecting, waiting for any in-flight
  /// command to drain. Used before entering raw monitor mode so the adapter
  /// isn't being polled at the same time.
  Future<void> pausePolling() async {
    if (!_running) return;
    _running = false;
    await _loopDone;
    _loopDone = null;
  }

  /// Resume the poll loop after [pausePolling] (re-connecting if needed).
  Future<void> resumePolling() async {
    if (_running) return;
    if (!_transport.isConnected) {
      await start();
      return;
    }
    _running = true;
    _loopDone = _loop();
  }

  /// Pause polling, switch the adapter into raw CAN-sniffing mode, and return a
  /// stream of raw frame lines (e.g. `7E8 03 41 0C 1A F8`). Call [stopMonitor]
  /// to leave monitor mode and resume normal polling.
  ///
  /// [protocol] is the ELM327 `ATSP` code; passive monitoring needs the bus
  /// protocol set explicitly. Default `6` = ISO 15765-4 CAN, 11-bit / 500 kbps
  /// (the most common on modern cars).
  Future<Stream<String>> startMonitor({String protocol = '6'}) async {
    await pausePolling();
    // Best-effort setup; some adapters reject a command or two — keep going.
    for (final cmd in ['ATSP$protocol', 'ATH1', 'ATCAF0']) {
      try {
        await _transport.send(cmd);
      } catch (_) {/* ignore and try the next */}
    }
    final stream = _transport.beginMonitor();
    _transport.sendRaw('ATMA'); // monitor all frames — streams until stopped
    return stream;
  }

  /// Leave raw monitor mode and resume normal polling.
  Future<void> stopMonitor() async {
    await _transport.endMonitor();
    try {
      await _transport.send('ATCAF1'); // restore CAN auto-formatting
      await _transport.send('ATH0'); // headers back off for PID parsing
    } catch (_) {/* ignore — resumePolling re-reads what it needs */}
    await resumePolling();
  }

  Future<void> start() async {
    if (_running) return;
    _sumSpeed = 0;
    _sumLh = 0;
    try {
      await _transport.connect();
      _state = _state.copyWith(connected: true, error: null);
      _emit();
      await _checkMafSupport();
      _running = true;
      _loopDone = _loop();
    } catch (e) {
      _state = _state.copyWith(connected: false, error: '$e');
      _emit();
    }
  }

  /// Query 0100 bitmask; bit for PID 0x10 (MAF) is bit 16 from the MSB.
  Future<void> _checkMafSupport() async {
    try {
      final raw = await _transport.send(Pids.supported);
      final r = PidReply.parse(raw, 0x00);
      if (r != null && r.bytes.length >= 4) {
        final mask = (r.bytes[0] << 24) |
            (r.bytes[1] << 16) |
            (r.bytes[2] << 8) |
            r.bytes[3];
        // PID 0x10 → bit position (32 - 0x10) = bit 16.
        final supported = (mask & (1 << (32 - 0x10))) != 0;
        _state = _state.copyWith(mafSupported: supported);
        _emit();
      }
    } catch (_) {
      // Leave mafSupported at its default; the loop will surface NO DATA.
    }
  }

  Future<void> _loop() async {
    while (_running && _transport.isConnected) {
      try {
        final speed = await _readSpeed();
        final throttle = await _readThrottle();
        final rpm = await _readRpm();

        // Use the MAF sensor when present; otherwise estimate airflow from
        // manifold pressure (speed-density) for QR25 trims without a MAF.
        double? maf;
        if (_state.mafSupported) {
          maf = await _readMaf();
        } else {
          final mapKpa = await _readMap();
          final iatC = await _readIat();
          if (mapKpa != null && rpm != null && iatC != null) {
            maf = FuelCalc.mafFromSpeedDensity(
              mapKpa: mapKpa,
              rpm: rpm,
              iatC: iatC,
            );
          }
        }

        final kmPerLiter = maf == null ? 0.0 : FuelCalc.kmPerLiter(maf, speed ?? 0);
        final litersPerHour = maf == null ? 0.0 : FuelCalc.litersPerHour(maf);

        // Distance-weighted running average: Σ speed / Σ L·h. Ticks are
        // ~uniform, so dt cancels and the ratio is a true km/L average.
        _sumSpeed += (speed ?? 0).toDouble();
        _sumLh += litersPerHour;
        final avgKmPerLiter = _sumLh > 0 ? _sumSpeed / _sumLh : 0.0;

        _state = _state.copyWith(
          kmPerLiter: kmPerLiter,
          avgKmPerLiter: avgKmPerLiter,
          litersPerHour: litersPerHour,
          speed: speed ?? _state.speed,
          throttle: throttle ?? _state.throttle,
          rpm: rpm ?? _state.rpm,
          error: null,
        );
        _emit();
      } catch (e) {
        _state = _state.copyWith(error: '$e');
        _emit();
      }
    }
  }

  Future<double?> _readMaf() async {
    final r = PidReply.parse(await _transport.send(Pids.maf), 0x10);
    return r == null ? null : Pids.decodeMaf(r);
  }

  Future<int?> _readSpeed() async {
    final r = PidReply.parse(await _transport.send(Pids.speed), 0x0D);
    return r == null ? null : Pids.decodeSpeed(r);
  }

  Future<double?> _readThrottle() async {
    final r = PidReply.parse(await _transport.send(Pids.throttle), 0x11);
    return r == null ? null : Pids.decodeThrottle(r);
  }

  Future<int?> _readRpm() async {
    final r = PidReply.parse(await _transport.send(Pids.rpm), 0x0C);
    return r == null ? null : Pids.decodeRpm(r);
  }

  Future<int?> _readMap() async {
    final r = PidReply.parse(await _transport.send(Pids.map), 0x0B);
    return r == null ? null : Pids.decodeMap(r);
  }

  Future<int?> _readIat() async {
    final r = PidReply.parse(await _transport.send(Pids.iat), 0x0F);
    return r == null ? null : Pids.decodeIat(r);
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_state);
  }

  Future<void> stop() async {
    _running = false;
    await _transport.close();
    _state = _state.copyWith(connected: false);
    _emit();
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
