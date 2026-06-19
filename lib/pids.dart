/// OBD-II mode 01 PID parsing for the values the HUD needs.
///
/// Each reply (headers off) looks like `41 0D 3C` — the `41` echoes mode 01,
/// then the PID byte, then data bytes. We strip spaces and parse hex.

class PidReply {
  PidReply(this.bytes);

  /// Data bytes after the `41 <pid>` prefix.
  final List<int> bytes;

  int get a => bytes.isNotEmpty ? bytes[0] : 0;
  int get b => bytes.length > 1 ? bytes[1] : 0;

  /// Parse a raw ELM327 text reply for an expected PID (e.g. 0x0D).
  /// Returns null if the reply is an error ("NO DATA", "SEARCHING...", etc.)
  /// or does not match the expected mode/pid.
  static PidReply? parse(String raw, int expectedPid) {
    final cleaned = raw
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toUpperCase();

    if (cleaned.isEmpty ||
        cleaned.contains('NO DATA') ||
        cleaned.contains('UNABLE') ||
        cleaned.contains('SEARCHING') ||
        cleaned.contains('ERROR') ||
        cleaned == '?') {
      return null;
    }

    final tokens = cleaned.split(' ').where((t) => t.isNotEmpty).toList();
    // Find the "41" response marker, then verify the PID byte.
    for (var i = 0; i + 1 < tokens.length; i++) {
      if (tokens[i] == '41' &&
          int.tryParse(tokens[i + 1], radix: 16) == expectedPid) {
        final data = tokens
            .sublist(i + 2)
            .map((t) => int.tryParse(t, radix: 16))
            .where((v) => v != null)
            .cast<int>()
            .toList();
        return PidReply(data);
      }
    }
    return null;
  }
}

/// PID command strings (mode 01) and their decoders.
class Pids {
  static const maf = '0110';      // mass air flow, g/s
  static const speed = '010D';    // vehicle speed, km/h
  static const throttle = '0111'; // throttle position, %
  static const rpm = '010C';      // engine RPM
  static const map = '010B';      // intake manifold abs pressure, kPa
  static const iat = '010F';      // intake air temp, °C
  static const supported = '0100';// bitmask of supported PIDs 01-20

  static double decodeMaf(PidReply r) => (256 * r.a + r.b) / 100.0; // g/s
  static int decodeSpeed(PidReply r) => r.a;                        // km/h
  static double decodeThrottle(PidReply r) => r.a * 100.0 / 255.0;  // %
  static int decodeRpm(PidReply r) => (256 * r.a + r.b) ~/ 4;       // rpm
  static int decodeMap(PidReply r) => r.a;                          // kPa
  static int decodeIat(PidReply r) => r.a - 40;                     // °C
}
