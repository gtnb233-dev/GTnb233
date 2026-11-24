import 'dart:math' as math;

/// 角度输入解释方式。
///
/// 国内测量习惯把 `123°45'30"` 写成 `123.4530`（度.分秒紧凑写法 GG.MMSS：
/// 小数部分前两位是「分」，其余是「秒」），而计算器/编程习惯用十进制度
/// `123.758333`。两者仅凭一个数字无法区分，因此由调用方（设置项）明确指定。
enum AngleInputMode {
  /// 度.分秒紧凑写法：`123.4530` → 123°45′30″。
  dmsCompact,

  /// 十进制度：`123.758333`。
  decimalDegrees,
}

/// 弧度/度换算常数。
const double deg2rad = math.pi / 180.0;
const double rad2deg = 180.0 / math.pi;

double degToRad(double deg) => deg * deg2rad;
double radToDeg(double rad) => rad * rad2deg;

/// 归一化到 `[0, 360)` 的度（同时把 `-0.0` 归成 `0.0`）。
double wrapDeg(double deg) {
  if (!deg.isFinite) return deg;
  var v = deg % 360.0;
  if (v < 0) v += 360.0;
  if (v >= 360.0) v -= 360.0;
  // `-0.0 % 360` 仍是 `-0.0`，统一成 +0，避免显示成 `-0°00′00″`。
  if (v == 0) return 0.0;
  return v;
}

/// 归一化到 `[0, 2π)` 的弧度。
double wrapRad(double rad) {
  if (!rad.isFinite) return rad;
  const full = 2 * math.pi;
  var v = rad % full;
  if (v < 0) v += full;
  if (v >= full) v -= full;
  if (v == 0) return 0.0;
  return v;
}

/// 度分秒值。
class Dms {
  const Dms(this.degree, this.minute, this.second, {this.negative = false});

  /// 度（通常带符号；`degree == 0` 时符号由 [negative] 表达）。
  final int degree;
  final int minute;
  final double second;

  /// 符号位：`0°30′` 这类「度为零的负角」靠它保留负号。
  final bool negative;

  /// 是否为负角（[negative] 或 [degree] 为负）。
  bool get isNegative => negative || degree < 0;

  /// 十进制度。
  double get decimal =>
      (isNegative ? -1.0 : 1.0) *
      (degree.abs() + minute / 60.0 + second / 3600.0);

  @override
  String toString() =>
      '${isNegative ? '-' : ''}${degree.abs()}°$minute′'
      '${second.toStringAsFixed(2)}″';
}

/// 度 → 度分秒，秒按 [secDigits] 四舍五入并处理 60 进位。
Dms degToDms(double deg, {int secDigits = 2}) {
  final neg = deg < 0;
  final a = deg.abs();
  var d = a.floor();
  final rem = (a - d) * 60.0;
  var m = rem.floor();
  var s = (rem - m) * 60.0;
  final p = math.pow(10, secDigits).toDouble();
  s = (s * p).round() / p;
  if (s >= 60.0) {
    s -= 60.0;
    m += 1;
  }
  if (m >= 60) {
    m -= 60;
    d += 1;
  }
  return Dms(neg ? -d : d, m, s, negative: neg);
}

/// 度分秒 → 度。
double dmsToDeg(num degree, [num minute = 0, num second = 0]) {
  final neg = degree < 0 ||
      (degree == 0 && minute < 0) ||
      (degree == 0 && minute == 0 && second < 0);
  final sign = neg ? -1.0 : 1.0;
  final d = degree.abs().toDouble();
  final m = minute.abs().toDouble();
  final s = second.abs().toDouble();
  return sign * (d + m / 60.0 + s / 3600.0);
}

/// 解析角度文本。
///
/// 支持：`123°45'56.7"`、`123 45 56.7`、`123:45:56.7`、`123.45.56.7`（多点度分秒）、
/// `123度45分56.7秒`、`123°45.5′`，以及单值（按 [mode] 解释）。
/// 空串或格式非法时抛 [FormatException]。
double parseAngle(
  String text, {
  AngleInputMode mode = AngleInputMode.dmsCompact,
}) {
  var t = text
      .trim()
      .replaceAll('。', '.')
      .replaceAll('．', '.')
      .replaceAll('－', '-')
      .replaceAll('−', '-')
      .replaceAll('—', '-')
      .replaceAll('\u3000', ' ')
      .replaceAll('°', ' ')
      .replaceAll('º', ' ')
      .replaceAll('˚', ' ')
      .replaceAll('′', ' ')
      .replaceAll('’', ' ')
      .replaceAll("'", ' ')
      .replaceAll('″', ' ')
      .replaceAll('”', ' ')
      .replaceAll('"', ' ')
      .replaceAll('度', ' ')
      .replaceAll('分', ' ')
      .replaceAll('秒', ' ')
      .replaceAll(':', ' ')
      .replaceAll('：', ' ')
      .replaceAll('，', ' ')
      .replaceAll(',', ' ')
      .replaceAll('\t', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (t.isEmpty) {
    throw const FormatException('角度为空');
  }
  var negative = false;
  if (t.startsWith('-')) {
    negative = true;
    t = t.substring(1).trim();
  } else if (t.startsWith('+')) {
    t = t.substring(1).trim();
  }
  final parts = t.split(' ').where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) {
    throw const FormatException('角度为空');
  }
  if (parts.length > 3) {
    throw FormatException('角度格式不正确：“$text”（度分秒最多三段）');
  }
  double value;
  if (parts.length == 3) {
    value = dmsToDeg(
      _num(parts[0], text),
      _num(parts[1], text),
      _num(parts[2], text),
    );
  } else if (parts.length == 2) {
    final p0 = parts[0];
    if (p0.contains('.')) {
      if (p0.contains('..') || p0.startsWith('.')) {
        throw FormatException('角度格式不正确：“$text”');
      }
      if (p0.endsWith('.')) {
        value = dmsToDeg(
          _num(p0.substring(0, p0.length - 1), text),
          _num(parts[1], text),
          0,
        );
      } else {
        final dParts = p0.split('.');
        if (dParts.length == 2) {
          value = dmsToDeg(
            _num(dParts[0], text),
            _num(dParts[1], text),
            _num(parts[1], text),
          );
        } else {
          throw FormatException('角度格式不正确：“$text”（度分秒最多三段）');
        }
      }
    } else {
      value = dmsToDeg(_num(p0, text), _num(parts[1], text), 0);
    }
  } else {
    final s = parts[0];
    if (s.split('.').length >= 3) {
      if (s.contains('..') || s.startsWith('.')) {
        throw FormatException('角度格式不正确：“$text”');
      }
      final clean = s.endsWith('.') ? s.substring(0, s.length - 1) : s;
      final dotParts = clean.split('.');
      if (dotParts.length == 2) {
        value = dmsToDeg(_num(dotParts[0], text), _num(dotParts[1], text), 0);
      } else if (dotParts.length == 3) {
        value = dmsToDeg(
          _num(dotParts[0], text),
          _num(dotParts[1], text),
          _num(dotParts[2], text),
        );
      } else if (dotParts.length == 4) {
        value = dmsToDeg(
          _num(dotParts[0], text),
          _num(dotParts[1], text),
          _num('${dotParts[2]}.${dotParts[3]}', text),
        );
      } else {
        throw FormatException('角度格式不正确：“$text”（度分秒最多三段）');
      }
    } else {
      final single = _num(s, text);
      switch (mode) {
        case AngleInputMode.decimalDegrees:
          value = single.abs();
        case AngleInputMode.dmsCompact:
          value = _compactToDeg(single);
      }
    }
  }
  return negative ? -value.abs() : value;
}

double _num(String s, String whole) {
  final v = double.tryParse(s);
  if (v == null) {
    throw FormatException('角度格式不正确：“$whole”');
  }
  return v;
}

/// GG.MMSS 紧凑写法 → 度。
///
/// 按字符串解析，避免 `frac * 100` 的二进制误差：小数部分前两位是分，
/// 其余位（含小数）是秒的整数部分与小数部分：
/// `123.4530` → 45′30″；`123.45567` → 45′56.7″；`123.5` → 50′00″。
/// 秒 ≥ 60 进位到分，分 ≥ 60 进位到度（`123.5960` → 124）。
double _compactToDeg(double compact) {
  final text = compact.abs().toString();
  final dot = text.indexOf('.');
  final intText = dot < 0 ? text : text.substring(0, dot);
  final frac = dot < 0 ? '' : text.substring(dot + 1);
  var d = intText.isEmpty ? 0 : int.parse(intText);
  // 分秒至少补足 4 位：两位分 + 两位秒。
  final padded = frac.padRight(4, '0');
  var m = int.parse(padded.substring(0, 2));
  final secInt = int.parse(padded.substring(2));
  final secScale = math.pow(10, padded.length - 4).toDouble();
  var s = secInt / secScale;
  while (s >= 60.0) {
    s -= 60.0;
    m += 1;
  }
  while (m >= 60) {
    m -= 60;
    d += 1;
  }
  return d + m / 60.0 + s / 3600.0;
}

/// 度 → 紧凑度分秒字符串，如 `123.4530`（秒保留 [secDigits] 位）。
///
/// 输出与 [parseAngle] 的 [AngleInputMode.dmsCompact] 互为逆运算。
String fmtDmsCompact(double deg, {int secDigits = 1}) {
  final dms = degToDms(deg, secDigits: secDigits);
  final sign = dms.isNegative ? '-' : '';
  final compact =
      dms.degree.abs() + dms.minute / 100.0 + dms.second / 10000.0;
  var text = compact.toStringAsFixed(4 + secDigits);
  // 去掉多余的尾零，但至少保留 4 位小数（分两位 + 秒两位）。
  final minLen = text.length - secDigits;
  while (secDigits > 0 && text.length > minLen && text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  return '$sign$text';
}

/// 度 → `123°45′56.7″`（度不补零，分补两位，秒补足整数两位）。
///
/// [wrap360] 为 true 时先归一到 `[0, 360)`，并在四舍五入进位到 360° 时
/// 回绕成 0°（例如 359°59′59.9″ 显示为 0°00′00.0″）。
String fmtAngle(double deg, {int secDigits = 1, bool wrap360 = false}) {
  final value = wrap360 ? wrapDeg(deg) : deg;
  var dms = degToDms(value, secDigits: secDigits);
  if (wrap360 && dms.degree.abs() >= 360) {
    dms = degToDms(0.0, secDigits: secDigits);
  }
  final sign = dms.isNegative ? '-' : '';
  final d = dms.degree.abs().toString();
  final m = dms.minute.toString().padLeft(2, '0');
  final secWidth = secDigits <= 0 ? 2 : 3 + secDigits;
  final s = dms.second.toStringAsFixed(secDigits).padLeft(secWidth, '0');
  return '$sign$d°$m′$s″';
}

/// 方位角格式化：`[0, 360)` 归一，359°59′59.9″ 回绕为 0°00′00.0″。
String fmtAzimuth(double azimuthDeg, {int secDigits = 1}) =>
    fmtAngle(azimuthDeg, secDigits: secDigits, wrap360: true);

/// 方位角（度）→ 象限角描述，如 `北偏东 45°12′30″`；落在坐标轴上时返回
/// `正北 / 正东 / 正南 / 正西`。
String azimuthToQuadrant(double azimuthDeg, {int secDigits = 1}) {
  final a = wrapDeg(azimuthDeg);
  // 先按秒位取整判断是否落在坐标轴上（359°59′59.9″ 视为正北）。
  final ra = _roundSec(a, secDigits);
  if (ra == 0 || ra == 360) return '正北';
  if (ra == 90) return '正东';
  if (ra == 180) return '正南';
  if (ra == 270) return '正西';
  if (a < 90) return '北偏东 ${fmtAngle(a, secDigits: secDigits)}';
  if (a < 180) return '南偏东 ${fmtAngle(180 - a, secDigits: secDigits)}';
  if (a < 270) return '南偏西 ${fmtAngle(a - 180, secDigits: secDigits)}';
  final quad = _roundSec(360 - a, secDigits);
  if (quad == 0 || quad == 360) return '正北';
  return '北偏西 ${fmtAngle(360 - a, secDigits: secDigits)}';
}

double _roundSec(double value, int secDigits) {
  if (!value.isFinite) return value;
  final p = math.pow(10, secDigits).toDouble();
  return (value * p).round() / p;
}

/// 象限（Ⅰ 北东 / Ⅱ 南东 / Ⅲ 南西 / Ⅳ 北西）。
enum Quadrant {
  northEast(1, '北东'),
  southEast(2, '南东'),
  southWest(3, '南西'),
  northWest(4, '北西');

  const Quadrant(this.number, this.label);

  /// 象限号 Ⅰ~Ⅳ。
  final int number;

  /// 象限文字：北东 / 南东 / 南西 / 北西。
  final String label;
}

/// 方位角对应的象限角。
class QuadrantBearing {
  const QuadrantBearing(this.quadrant, this.rDeg, this.azimuthDeg);

  final Quadrant quadrant;

  /// 象限角 R（0°~90° 锐角）。
  final double rDeg;

  /// 归一到 `[0, 360)` 的方位角 α。
  final double azimuthDeg;

  /// 象限号 Ⅰ~Ⅳ。
  int get number => quadrant.number;

  /// 象限文字：北东 / 南东 / 南西 / 北西。
  String get label => quadrant.label;

  /// 教材写法，如 `南东 56°15′00.0″`。
  String get text => [quadrant.label, fmtAngle(rDeg)].join(' ');

  @override
  String toString() => text;
}

/// 方位角 → 象限角（R 为自北端或南端起量的锐角）。
///
/// | 象限 | 关系 | 方位角范围 |
/// | --- | --- | --- |
/// | Ⅰ 北东 | R = α | 0°–90° |
/// | Ⅱ 南东 | R = 180° − α | 90°–180° |
/// | Ⅲ 南西 | R = α − 180° | 180°–270° |
/// | Ⅳ 北西 | R = 360° − α | 270°–360° |
QuadrantBearing quadrantFromAzimuth(double azimuthDeg) {
  final a = wrapDeg(azimuthDeg);
  if (a < 90.0) return QuadrantBearing(Quadrant.northEast, a, a);
  if (a < 180.0) return QuadrantBearing(Quadrant.southEast, 180.0 - a, a);
  if (a < 270.0) return QuadrantBearing(Quadrant.southWest, a - 180.0, a);
  return QuadrantBearing(Quadrant.northWest, 360.0 - a, a);
}

/// 象限角 → 方位角（R 取绝对值并折算到 0°~90°）。
double azimuthFromQuadrant(Quadrant quadrant, double rDeg) {
  var r = rDeg.abs() % 360.0;
  if (r > 90.0) {
    if (r > 270.0) {
      r = 360.0 - r;
    } else if (r > 180.0) {
      r = r - 180.0;
    } else {
      r = 180.0 - r;
    }
  }
  switch (quadrant) {
    case Quadrant.northEast:
      return wrapDeg(r);
    case Quadrant.southEast:
      return wrapDeg(180.0 - r);
    case Quadrant.southWest:
      return wrapDeg(180.0 + r);
    case Quadrant.northWest:
      return wrapDeg(360.0 - r);
  }
}