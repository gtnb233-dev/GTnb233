import 'package:survey_core/survey_core.dart';

/// 「判定：内角和 (n−2)·180°」这类文案（闭合导线专用）。
///
/// 口径由 core 的 [TraverseResult.angleConvention] 给出：顺时针导线量右角时
/// 右角就是内角，逆时针时才是外角，所以不能按左角/右角写死。
String traverseJudgementText(
  TraverseResult result, {
  String Function(String source, [Map<String, Object> arguments])? tr,
}) {
  final convention = result.angleConvention;
  if (convention == null) {
    const fallback = '附合导线：按方位角条件检核，无内角和/外角和判定';
    return tr?.call(fallback) ?? fallback;
  }
  final label = tr?.call(convention.label) ?? convention.label;
  final raw = '判定：$label ${convention.formulaLabel}';
  return tr?.call(raw) ?? raw;
}

/// 角度闭合差的界面写法（带符号，默认秒位 1 位）。
String misclosureText(double seconds, {int digits = 1}) =>
    '${fmt(seconds, digits)}″';

/// 观测角（度）→ 度分秒文本。
String angleDegText(double deg, int secDigits) =>
    fmtAngle(deg, secDigits: secDigits);
