// NMEA-0183 `$GPGGA` / `$GNGGA` 语句解析与模拟生成工具（纯 Dart）。

/// 解析后的 NMEA GGA 定位报文。
class NmeaGpgga {
  const NmeaGpgga({
    required this.utcTime,
    required this.latDeg,
    required this.lonDeg,
    required this.fixQuality,
    required this.satellites,
    required this.hdop,
    required this.altitudeM,
    this.geoidSepM = 0.0,
  });

  /// UTC 时间（如 `120000.00`）。
  final String utcTime;

  /// 纬度（十进制度，北纬为正，南纬为负）。
  final double latDeg;

  /// 经度（十进制度，东经为正，西经为负）。
  final double lonDeg;

  /// 定位质量（0=无效，1=单点，2=差分，4=RTK固定解，5=RTK浮点解）。
  final int fixQuality;

  /// 参与解算的卫星数。
  final int satellites;

  /// 水平精度因子 HDOP。
  final double hdop;

  /// 天线大地高/海拔高程（m）。
  final double altitudeM;

  /// 大地水准面差距（m）。
  final double geoidSepM;
}

/// 计算 NMEA 语句中 `$` 与 `*` 之间内容的异或校验和（两位大写十六进制）。
String _computeNmeaChecksum(String body) {
  var xor = 0;
  for (final code in body.codeUnits) {
    xor ^= code;
  }
  return xor.toRadixString(16).toUpperCase().padLeft(2, '0');
}

double? _parseDmToDeg(String raw, String hemi, bool isLat) {
  if (raw.isEmpty || hemi.isEmpty) return null;
  final dm = double.tryParse(raw);
  if (dm == null || !dm.isFinite || dm < 0) return null;
  final degPart = (dm / 100.0).floor();
  final minPart = dm - degPart * 100.0;
  if (minPart < 0 || minPart >= 60.0) return null;
  final absDeg = degPart + minPart / 60.0;
  final upper = hemi.toUpperCase();
  if (isLat) {
    if (absDeg > 90.0) return null;
    if (upper == 'N') return absDeg;
    if (upper == 'S') return -absDeg;
    return null;
  } else {
    if (absDeg > 180.0) return null;
    if (upper == 'E') return absDeg;
    if (upper == 'W') return -absDeg;
    return null;
  }
}

String _formatDegToDm(double deg, {required bool isLat}) {
  const scale = 1000000;
  final microMinutes = (deg.abs() * 60 * scale).round();
  final wholeMinutes = microMinutes ~/ scale;
  final degrees = (wholeMinutes ~/ 60).toString().padLeft(isLat ? 2 : 3, '0');
  final minutes = (wholeMinutes % 60).toString().padLeft(2, '0');
  final fraction = (microMinutes % scale).toString().padLeft(6, '0');
  return '$degrees$minutes.$fraction';
}

/// 解析 `$GPGGA` 或 `$GNGGA` 语句。
///
/// 若包含 `*XX` 校验和，则严格校验异或和；支持 `ddmm.mmmm` / `dddmm.mmmm`
/// 与 `N/S/E/W` 转换为带符号十进制度。格式非法或校验失败时返回 `null`。
NmeaGpgga? parseGpgga(String sentence) {
  final trimmed = sentence.trim();
  if (!trimmed.startsWith(r'$')) return null;

  String core;
  final starIdx = trimmed.indexOf('*');
  if (starIdx >= 0) {
    final hex = trimmed.substring(starIdx + 1).trim();
    if (hex.length != 2) return null;
    final expected = int.tryParse(hex, radix: 16);
    if (expected == null) return null;
    final body = trimmed.substring(1, starIdx);
    var xor = 0;
    for (final code in body.codeUnits) {
      xor ^= code;
    }
    if (xor != expected) return null;
    core = body;
  } else {
    core = trimmed.substring(1);
  }

  final fields = core.split(',');
  if (fields.length < 11) return null;
  final tag = fields[0].trim().toUpperCase();
  if (tag != 'GPGGA' && tag != 'GNGGA') return null;

  final utcTime = fields[1].trim();
  final latDeg = _parseDmToDeg(fields[2].trim(), fields[3].trim(), true);
  final lonDeg = _parseDmToDeg(fields[4].trim(), fields[5].trim(), false);
  if (latDeg == null || lonDeg == null) return null;

  final fixQuality = int.tryParse(fields[6].trim());
  if (fixQuality == null) return null;

  final satellites = int.tryParse(fields[7].trim()) ?? 0;
  final hdop = double.tryParse(fields[8].trim()) ?? 0.0;
  final altitudeM = double.tryParse(fields[9].trim());
  if (altitudeM == null || !altitudeM.isFinite) return null;

  final geoidSepM =
      fields.length > 11 ? (double.tryParse(fields[11].trim()) ?? 0.0) : 0.0;

  return NmeaGpgga(
    utcTime: utcTime,
    latDeg: latDeg,
    lonDeg: lonDeg,
    fixQuality: fixQuality,
    satellites: satellites,
    hdop: hdop,
    altitudeM: altitudeM,
    geoidSepM: geoidSepM,
  );
}

/// 构造一条带合法 `*XX` 校验和的模拟 `$GPGGA` 语句，用于无蓝牙外设时的演示与测试。
String buildSimulatedGpgga({
  double latDeg = 31.230416,
  double lonDeg = 121.473701,
  double altitudeM = 12.35,
  int satellites = 11,
  double hdop = 0.8,
}) {
  final latDm = _formatDegToDm(latDeg, isLat: true);
  final latHemi = latDeg >= 0 ? 'N' : 'S';
  final lonDm = _formatDegToDm(lonDeg, isLat: false);
  final lonHemi = lonDeg >= 0 ? 'E' : 'W';
  final body = 'GPGGA,120000.00,$latDm,$latHemi,$lonDm,$lonHemi,4,'
      '${satellites.toString().padLeft(2, '0')},'
      '${hdop.toStringAsFixed(1)},${altitudeM.toStringAsFixed(2)},M,0.00,M,,';
  final checksum = _computeNmeaChecksum(body);
  return '\$$body*$checksum';
}
