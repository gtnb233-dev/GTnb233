import 'dart:math' as math;

import 'package:flutter/material.dart';

final _measure = RegExp(r'^[+\-−±]?\s*(?:1/)?\d[\d.,°′″"/:%\s]*$');
final _plainDecimal = RegExp(r'^[+\-−±]?\d+(?:\.(\d+))?$');

bool isMeasureColumn(Iterable<String> values) {
  var hasNumbers = false;
  for (final value in values) {
    final text = value.trim();
    if (text.isEmpty || text == '—' || text == '-') continue;
    if (!_measure.hasMatch(text)) return false;
    hasNumbers = true;
  }
  return hasNumbers;
}

int measurementPrecision(Iterable<String> values) {
  var precision = 0;
  for (final value in values) {
    final text = value.trim();
    if (text.isEmpty || text == '—' || text == '-') continue;
    final number = _plainDecimal.firstMatch(text);
    if (number == null) return 0;
    precision = math.max(precision, number.group(1)?.length ?? 0);
  }
  return precision;
}

double measurementDecimalInset(
  BuildContext context,
  String value,
  int precision,
  double fontSize,
) {
  if (precision == 0) return 0;
  final match = _plainDecimal.firstMatch(value.trim());
  if (match == null) return 0;
  final fractional = match.group(1);
  // JetBrains Mono fixes the advance of each digit and decimal point at .6 em.
  final emptySlots =
      fractional == null ? precision + 1 : precision - fractional.length;
  return emptySlots * MediaQuery.textScalerOf(context).scale(fontSize) * .6;
}
