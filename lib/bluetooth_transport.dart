import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

import 'obd_transport.dart';

/// ELM327 over Bluetooth Classic (SPP) — the variant used by most ELM327
/// clones. The adapter must already be paired (bonded) in Android settings;
/// [address] is its MAC address.
class BluetoothObdTransport extends Elm327Transport {
  BluetoothObdTransport({required this.address, super.timeout});

  final String address;
  BluetoothConnection? _conn;
  StreamSubscription<Uint8List>? _sub;

  @override
  bool get channelOpen => _conn?.isConnected ?? false;

  @override
  Future<void> openChannel() async {
    final conn = await BluetoothConnection.toAddress(address).timeout(timeout);
    _conn = conn;
    _sub = conn.input?.listen(
      onBytes,
      onError: failPending,
      onDone: () => failPending('bluetooth closed'),
      cancelOnError: true,
    );
  }

  @override
  void writeRaw(String data) {
    _conn!.output.add(Uint8List.fromList(ascii.encode(data)));
  }

  @override
  Future<void> closeChannel() async {
    await _sub?.cancel();
    _sub = null;
    await _conn?.close();
    _conn?.dispose();
    _conn = null;
  }
}
