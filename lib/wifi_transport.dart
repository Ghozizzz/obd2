import 'dart:async';
import 'dart:io';

import 'obd_transport.dart';

/// ELM327 over TCP (WiFi adapter).
///
/// Default adapter AP: SSID `WiFi_OBDII`, host `192.168.0.10`, port `35000`.
/// The phone must be joined to the adapter's WiFi network. Note this kills the
/// phone's internet, since the adapter has no uplink.
class WifiObdTransport extends Elm327Transport {
  WifiObdTransport({
    this.host = '192.168.0.10',
    this.port = 35000,
    super.timeout,
  });

  final String host;
  final int port;
  Socket? _socket;

  @override
  bool get channelOpen => _socket != null;

  @override
  Future<void> openChannel() async {
    _socket = await Socket.connect(host, port, timeout: timeout);
    _socket!.listen(
      onBytes,
      onError: failPending,
      onDone: () => failPending('socket closed'),
      cancelOnError: true,
    );
  }

  @override
  void writeRaw(String data) => _socket!.write(data);

  @override
  Future<void> closeChannel() async {
    await _socket?.close();
    _socket?.destroy();
    _socket = null;
  }
}
