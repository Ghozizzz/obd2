import 'dart:async';

import 'package:flutter/material.dart';

import 'obd_service.dart';

/// CAN-bus sniffer / steering-wheel-button tester.
///
/// Puts the ELM327 into "monitor all" (`ATMA`) mode and lists every CAN frame
/// ID seen on the bus together with its data bytes. When a frame's bytes
/// change, its row flashes and a per-ID change counter increments — so pressing
/// a steering-wheel button (volume, cruise control, …) is easy to spot: watch
/// for the row that reacts.
///
/// Caveat: many cars expose only the powertrain CAN bus on the OBD-II port,
/// while wheel buttons live on a separate body/comfort bus. If nothing reacts
/// to a button, those messages simply aren't reachable from this port.
class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key, required this.service});

  final ObdService service;

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  /// ELM327 ATSP protocol codes worth trying for passive monitoring.
  static const _protocols = <String, String>{
    '6': 'CAN 11-bit / 500 kbps',
    '7': 'CAN 29-bit / 500 kbps',
    '8': 'CAN 11-bit / 250 kbps',
    '9': 'CAN 29-bit / 250 kbps',
    '0': 'Auto-detect',
  };

  String _protocol = '6';
  bool _monitoring = false;
  bool _busy = false;
  bool _showRaw = false;
  String? _status; // adapter status lines (STOPPED, BUFFER FULL, errors…)

  final Map<String, _Frame> _frames = {};
  final List<String> _rawLog = [];
  StreamSubscription<String>? _sub;
  Timer? _refresh;

  static final _hexId = RegExp(r'^[0-9A-Fa-f]{1,8}$');

  @override
  void dispose() {
    _refresh?.cancel();
    _sub?.cancel();
    if (_monitoring) {
      // Restore polling; fire-and-forget since we're tearing down.
      unawaited(widget.service.stopMonitor());
    }
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final stream = await widget.service.startMonitor(protocol: _protocol);
      _sub = stream.listen(_onLine);
      // Repaint a few times a second to update flashes and re-sort, without
      // rebuilding on every single frame (a busy bus emits hundreds/sec).
      _refresh = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => setState(() {}),
      );
      setState(() {
        _monitoring = true;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _status = 'Failed to start monitor: $e';
      });
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    _refresh?.cancel();
    _refresh = null;
    await _sub?.cancel();
    _sub = null;
    await widget.service.stopMonitor();
    if (!mounted) return;
    setState(() {
      _monitoring = false;
      _busy = false;
    });
  }

  void _clear() {
    setState(() {
      _frames.clear();
      _rawLog.clear();
      _status = null;
    });
  }

  void _onLine(String line) {
    // Keep a capped raw log for the optional raw view.
    _rawLog.add(line);
    if (_rawLog.length > 300) _rawLog.removeRange(0, _rawLog.length - 300);

    final tokens = line.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    // A frame is "<id> <byte> <byte> …"; anything else is a status message.
    if (tokens.length < 2 || !_hexId.hasMatch(tokens.first)) {
      _status = line;
      return;
    }
    final id = tokens.first.toUpperCase();
    final data = tokens.sublist(1).join(' ').toUpperCase();
    final now = DateTime.now();
    final f = _frames[id];
    if (f == null) {
      _frames[id] = _Frame(id: id, data: data, lastChange: now, lastSeen: now);
    } else {
      f.count++;
      f.lastSeen = now;
      if (f.data != data) {
        f.data = data;
        f.changes++;
        f.lastChange = now;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('CAN Bus / Button Tester'),
        actions: [
          IconButton(
            tooltip: _showRaw ? 'Show frame table' : 'Show raw log',
            icon: Icon(_showRaw ? Icons.table_rows : Icons.notes),
            onPressed: () => setState(() => _showRaw = !_showRaw),
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: _clear,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _controls(),
            _tip(),
            if (_status != null) _statusLine(_status!),
            const Divider(height: 1, color: Colors.white12),
            Expanded(child: _showRaw ? _rawView() : _tableView()),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Text('Protocol', style: TextStyle(color: Colors.white70)),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: _protocol,
            dropdownColor: const Color(0xFF1A1A1A),
            style: const TextStyle(color: Colors.white),
            underline: const SizedBox.shrink(),
            onChanged: _monitoring || _busy
                ? null
                : (v) => setState(() => _protocol = v ?? _protocol),
            items: [
              for (final e in _protocols.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
          ),
          const Spacer(),
          Text(
            '${_frames.length} IDs',
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: _busy ? null : (_monitoring ? _stop : _start),
            icon: Icon(_monitoring ? Icons.stop : Icons.play_arrow),
            label: Text(_monitoring ? 'Stop' : 'Start'),
            style: FilledButton.styleFrom(
              backgroundColor: _monitoring ? Colors.redAccent : Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        _monitoring
            ? 'Press a wheel button (volume / cruise) and watch for a row that '
                'flashes or whose change-count jumps. Tip: do it with the engine '
                'OFF (ignition on) so fewer frames move on their own.'
            : 'Start monitoring, then press your steering-wheel buttons. If no '
                'row reacts, those buttons are likely on a separate bus not '
                'wired to the OBD-II port.',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
    );
  }

  Widget _statusLine(String s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14, color: Colors.amberAccent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              s,
              style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableView() {
    if (_frames.isEmpty) {
      return const Center(
        child: Text(
          'No frames yet.\nStart monitoring to see CAN traffic.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38),
        ),
      );
    }
    // Most-recently-changed first, so a button-press frame bubbles to the top.
    final rows = _frames.values.toList()
      ..sort((a, b) => b.lastChange.compareTo(a.lastChange));
    final now = DateTime.now();
    return ListView.builder(
      itemCount: rows.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _header();
        final f = rows[i - 1];
        final sinceChange = now.difference(f.lastChange).inMilliseconds;
        final flash = sinceChange < 1200;
        return Container(
          color: flash ? Colors.green.withOpacity(0.22) : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  f.id,
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  f.data,
                  style: TextStyle(
                    color: flash ? Colors.greenAccent : Colors.white,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  '${f.changes}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: f.changes > 0 ? Colors.orangeAccent : Colors.white38,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header() {
    return Container(
      color: Colors.white10,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: const Row(
        children: [
          SizedBox(
            width: 90,
            child: Text('CAN ID',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(
            child: Text('Data bytes',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          SizedBox(
            width: 70,
            child: Text('Changes',
                textAlign: TextAlign.right,
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _rawView() {
    if (_rawLog.isEmpty) {
      return const Center(
        child: Text('No raw lines yet.',
            style: TextStyle(color: Colors.white38)),
      );
    }
    // Newest at the bottom; show the tail.
    final lines = _rawLog.reversed.toList();
    return ListView.builder(
      reverse: true,
      itemCount: lines.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Text(
          lines[i],
          style: const TextStyle(
            color: Colors.white70,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// Tracked state for a single CAN ID seen on the bus.
class _Frame {
  _Frame({
    required this.id,
    required this.data,
    required this.lastChange,
    required this.lastSeen,
  });

  final String id;
  String data;
  int count = 1;
  int changes = 0;
  DateTime lastChange;
  DateTime lastSeen;
}
