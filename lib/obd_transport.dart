import 'dart:async';

/// Transport-agnostic ELM327 link.
///
/// WiFi and Bluetooth adapters speak the exact same ELM327 ASCII protocol —
/// only the underlying byte channel differs. [Elm327Transport] holds the shared
/// init handshake and `>`-prompt reply framing; subclasses provide the channel.
abstract class ObdTransport {
  Future<void> connect();
  Future<String> send(String cmd);
  Future<void> close();
  bool get isConnected;
}

/// Shared ELM327 protocol on top of an abstract byte channel.
abstract class Elm327Transport implements ObdTransport {
  Elm327Transport({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;
  final StringBuffer _rx = StringBuffer();
  Completer<String>? _pending;

  // --- Channel hooks implemented by subclasses ---

  /// Open the underlying channel (socket / Bluetooth). Throws on failure.
  Future<void> openChannel();

  /// Write raw text to the channel.
  void writeRaw(String data);

  /// Tear down the underlying channel.
  Future<void> closeChannel();

  /// Whether the underlying channel is currently open.
  bool get channelOpen;

  // --- Callbacks subclasses invoke from their byte stream ---

  /// Feed incoming bytes. ELM327 is ASCII; a reply ends at the '>' prompt.
  void onBytes(List<int> data) {
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

  /// Fail the in-flight command (channel error or close).
  void failPending(Object error) {
    final p = _pending;
    _pending = null;
    p?.completeError(error);
  }

  // --- ObdTransport ---

  @override
  bool get isConnected => channelOpen;

  @override
  Future<void> connect() async {
    await openChannel();
    await _init();
  }

  /// ELM327 init handshake. Each command terminated by CR.
  Future<void> _init() async {
    await send('ATZ'); // reset
    await send('ATE0'); // echo off
    await send('ATL0'); // linefeeds off
    await send('ATH0'); // headers off
    await send('ATSP0'); // auto protocol
  }

  @override
  Future<String> send(String cmd) {
    if (!channelOpen) {
      return Future.error('not connected');
    }
    if (_pending != null) {
      return Future.error('command already in flight');
    }
    final completer = Completer<String>();
    _pending = completer;
    writeRaw('$cmd\r');
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending = null;
        throw TimeoutException('no reply to "$cmd"');
      },
    );
  }

  @override
  Future<void> close() => closeChannel();
}
