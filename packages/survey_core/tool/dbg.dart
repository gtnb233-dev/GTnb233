import 'dart:math' as math;
import 'package:survey_core/survey_core.dart';

void main() {
  final alpha = degToRad(45.0);
  final beta = degToRad(45.0);
  final cotA = 1 / math.tan(alpha);
  final cotB = 1 / math.tan(beta);
  print('degToRad(45)=$alpha cotA=$cotA cotB=$cotB');
  const a = Point2(0, 0);
  const b = Point2(100, 0);
  final denom = cotA + cotB;
  print('denom=$denom xnum=${a.x * cotB + b.x * cotA + (b.y - a.y)} ynum=${a.y * cotB + b.y * cotA + (a.x - b.x)}');
  final r = forwardIntersection(a: a, b: b, alphaDeg: 45, betaDeg: 45)!;
  print('P=${r.point.x},${r.point.y}');
}
