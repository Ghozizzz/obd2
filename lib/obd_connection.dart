import 'dart:async';
import 'dart:io';

/// Low-level socket transport to an ELM327 WiFi adapter.
///
/// Default adapter AP: SSID `WiFi_OBDII`, host `192.168.0.10`, port `35000`.
/// The phone must be joined to the adapter's WiFi network. Note this kills the
/// phone's internet, since the adapter has no uplink.
class ObdConnection {
  ObdConnection({
    this.host = '192.168.0.10',
    this.port = 35000,
    this.timeout = const Duration(seconds: 5),
  });

  final String host;
  final int port;
  final Duration timeout;

  Socket? _socket;
  final StringBuffer _rx = StringBuffer();
  Completer<String>? _pending;

  bool get isConnected => _socket != null;

  Future<void> connect() async {
    _socket = await Socket.connect(host, port, timeout: timeout);
    _socket!.listen(
      _onData,
      onError: (e) => _failPending(e),
      onDone: () => _failPending('socket closed'),
      cancelOnError: true,
    );
    await _init();
  }

  /// ELM327 init handshake. Each command terminated by CR.
  Future<void> _init() async {
    await send('ATZ');   // reset
    await send('ATE0');  // echo off
    await send('ATL0');  // linefeeds off
    await send('ATH0');  // headers off
    await send('ATSP0'); // auto protocol
  }

  void _onData(List<int> data) {
    // ELM327 is ASCII. Accumulate until the '>' prompt marks end of reply.
    _rx.write(String.fromCharCodes(data));
    final s = _rx.toString();
    if (s.contains('>')) {
      final reply = s.replaceAll('>', '').trim();
      _rx.clear();
      final p = _pending;
      _pending = null;
      p?.complete(reply);
    }
  }

  void _failPending(Object error) {
    final p = _pending;
    _pending = null;
    p?.completeError(error);
  }

  /// Send a raw command (CR appended) and await the reply up to the prompt.
  Future<String> send(String cmd) {
    if (_socket == null) {
      return Future.error('not connected');
    }
    if (_pending != null) {
      return Future.error('command already in flight');
    }
    final completer = Completer<String>();
    _pending = completer;
    _socket!.write('$cmd\r');
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending = null;
        throw TimeoutException('no reply to "$cmd"');
      },
    );
  }

  Future<void> close() async {
    await _socket?.close();
    _socket?.destroy();
    _socket = null;
  }
}
