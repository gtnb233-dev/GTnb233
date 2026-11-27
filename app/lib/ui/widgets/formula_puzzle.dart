import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../l10n/survey_strings.dart';
import '../../theme/tokens.dart';
import 'foundation.dart';
import 'results.dart';

/// 公式计算器的三种交互模式。
enum FormulaInputMode {
  diagram,
  blocks,
  free,
}

// ============================================================================
// 1. 图解填槽 (Diagram Slots)
// ============================================================================

enum _DiagramKind {
  slopeToHoriz,
  coordIncrement,
  heightAndSlope,
  cosineSide,
  cosineAngle,
  sineSide,
}

class _DiagramSlotSpec {
  const _DiagramSlotSpec({
    required this.key,
    required this.symbol,
    required this.label,
    required this.unit,
    this.defaultValue,
  });

  final String key;
  final String symbol;
  final String label;
  final String unit;
  final double? defaultValue;
}

class _DiagramOutput {
  const _DiagramOutput({
    required this.label,
    required this.value,
    this.unit,
    this.note,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final String? unit;
  final String? note;
  final bool emphasis;
}

class _DiagramEvalResult {
  const _DiagramEvalResult({
    this.substituted = '',
    this.outputs = const [],
    this.error,
  });

  final String substituted;
  final List<_DiagramOutput> outputs;
  final String? error;
}

class _DiagramFormulaDef {
  const _DiagramFormulaDef({
    required this.kind,
    required this.title,
    required this.equation,
    required this.caption,
    required this.slots,
  });

  final _DiagramKind kind;
  final String title;
  final String equation;
  final String caption;
  final List<_DiagramSlotSpec> slots;
}

const List<_DiagramFormulaDef> _kDiagramFormulas = [
  _DiagramFormulaDef(
    kind: _DiagramKind.slopeToHoriz,
    title: '斜距改平距',
    equation: 'D = S · cos(α)',
    caption: '已知斜距 S 与竖直角 α，求水平距离 D',
    slots: [
      _DiagramSlotSpec(
        key: 'S',
        symbol: 'S',
        label: '斜距 S',
        unit: 'm',
        defaultValue: 100,
      ),
      _DiagramSlotSpec(
        key: 'alpha',
        symbol: 'α',
        label: '竖直角 α',
        unit: '°',
        defaultValue: 15,
      ),
    ],
  ),
  _DiagramFormulaDef(
    kind: _DiagramKind.coordIncrement,
    title: '坐标增量',
    equation: 'ΔX = D·cos(α), ΔY = D·sin(α)',
    caption: '已知平距 D 与方位角 α，求北/东坐标增量',
    slots: [
      _DiagramSlotSpec(
        key: 'D',
        symbol: 'D',
        label: '水平距离 D',
        unit: 'm',
        defaultValue: 120,
      ),
      _DiagramSlotSpec(
        key: 'alpha',
        symbol: 'α',
        label: '方位角 α',
        unit: '°',
        defaultValue: 35,
      ),
    ],
  ),
  _DiagramFormulaDef(
    kind: _DiagramKind.heightAndSlope,
    title: '高差与坡度',
    equation: 'Δh = S·sin(α), i = Δh / D',
    caption: '已知斜距 S 与竖直角 α，求高差 Δh 与坡度 i',
    slots: [
      _DiagramSlotSpec(
        key: 'S',
        symbol: 'S',
        label: '斜距 S',
        unit: 'm',
        defaultValue: 80,
      ),
      _DiagramSlotSpec(
        key: 'alpha',
        symbol: 'α',
        label: '竖直角 α',
        unit: '°',
        defaultValue: 8,
      ),
    ],
  ),
  _DiagramFormulaDef(
    kind: _DiagramKind.cosineSide,
    title: '余弦定理求边',
    equation: 'c = √(a² + b² - 2ab·cos(C))',
    caption: '已知两边 a、b 及夹角 C，求第三边 c',
    slots: [
      _DiagramSlotSpec(
        key: 'a',
        symbol: 'a',
        label: '边长 a',
        unit: 'm',
        defaultValue: 60,
      ),
      _DiagramSlotSpec(
        key: 'b',
        symbol: 'b',
        label: '边长 b',
        unit: 'm',
        defaultValue: 80,
      ),
      _DiagramSlotSpec(
        key: 'C',
        symbol: 'C',
        label: '夹角 C',
        unit: '°',
        defaultValue: 60,
      ),
    ],
  ),
  _DiagramFormulaDef(
    kind: _DiagramKind.cosineAngle,
    title: '余弦定理求角',
    equation: 'C = acos((a² + b² - c²) / 2ab)',
    caption: '已知三边 a、b、c，求边 c 所对内角 C',
    slots: [
      _DiagramSlotSpec(
        key: 'a',
        symbol: 'a',
        label: '邻边 a',
        unit: 'm',
        defaultValue: 30,
      ),
      _DiagramSlotSpec(
        key: 'b',
        symbol: 'b',
        label: '邻边 b',
        unit: 'm',
        defaultValue: 40,
      ),
      _DiagramSlotSpec(
        key: 'c',
        symbol: 'c',
        label: '对边 c',
        unit: 'm',
        defaultValue: 50,
      ),
    ],
  ),
  _DiagramFormulaDef(
    kind: _DiagramKind.sineSide,
    title: '正弦定理求边',
    equation: 'b = a · sin(B) / sin(A)',
    caption: '已知边 a 及两角 A、B，求对边 b',
    slots: [
      _DiagramSlotSpec(
        key: 'a',
        symbol: 'a',
        label: '已知边 a',
        unit: 'm',
        defaultValue: 100,
      ),
      _DiagramSlotSpec(
        key: 'A',
        symbol: 'A',
        label: '对角 A',
        unit: '°',
        defaultValue: 45,
      ),
      _DiagramSlotSpec(
        key: 'B',
        symbol: 'B',
        label: '对角 B',
        unit: '°',
        defaultValue: 60,
      ),
    ],
  ),
];

/// 图解填槽视图：内置测量高频几何公式，点击槽位直接填值并实时绘图/求值。
class FormulaDiagramSlotsView extends StatefulWidget {
  const FormulaDiagramSlotsView({super.key});

  @override
  State<FormulaDiagramSlotsView> createState() =>
      _FormulaDiagramSlotsViewState();
}

class _FormulaDiagramSlotsViewState extends State<FormulaDiagramSlotsView> {
  int _selectedIndex = 0;
  String? _activeSlotKey;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  _DiagramFormulaDef get _formula => _kDiagramFormulas[_selectedIndex];

  @override
  void initState() {
    super.initState();
    _syncControllersForFormula();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  String _formatDefault(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void _syncControllersForFormula() {
    final formula = _formula;
    final neededKeys = formula.slots.map((s) => s.key).toSet();
    final stale =
        _controllers.keys.where((k) => !neededKeys.contains(k)).toList();
    for (final k in stale) {
      _controllers.remove(k)?.dispose();
      _focusNodes.remove(k)?.dispose();
    }
    for (final slot in formula.slots) {
      if (!_controllers.containsKey(slot.key)) {
        _controllers[slot.key] = TextEditingController(
          text: slot.defaultValue == null
              ? ''
              : _formatDefault(slot.defaultValue!),
        );
      }
      if (!_focusNodes.containsKey(slot.key)) {
        final node = FocusNode();
        node.addListener(() {
          if (node.hasFocus && mounted) {
            setState(() => _activeSlotKey = slot.key);
          }
        });
        _focusNodes[slot.key] = node;
      }
    }
    _activeSlotKey = formula.slots.first.key;
  }

  Map<String, double?> _readValues() {
    final map = <String, double?>{};
    for (final slot in _formula.slots) {
      final raw = _controllers[slot.key]?.text.trim() ?? '';
      map[slot.key] = raw.isEmpty ? null : double.tryParse(raw);
    }
    return map;
  }

  _DiagramEvalResult _evaluate(Map<String, double?> values) {
    final f = _formula;
    for (final slot in f.slots) {
      if (values[slot.key] == null) {
        return const _DiagramEvalResult(error: '请填写全部槽位数值');
      }
    }
    String numStr(double v) => fmt(v, 4).replaceAll(RegExp(r'\.?0+$'), '');

    switch (f.kind) {
      case _DiagramKind.slopeToHoriz:
        final s = values['S']!;
        final a = values['alpha']!;
        final d = ExpressionEvaluator.evaluate(
          'S * cos(alpha)',
          variables: {'S': s, 'alpha': a},
          unit: TrigUnit.degrees,
        );
        return _DiagramEvalResult(
          substituted: 'D = ${numStr(s)} × cos(${numStr(a)}°)',
          outputs: [
            _DiagramOutput(
              label: '平距 D',
              value: fmt(d, 4),
              unit: 'm',
              emphasis: true,
            ),
          ],
        );
      case _DiagramKind.coordIncrement:
        final d = values['D']!;
        final a = values['alpha']!;
        final dx = ExpressionEvaluator.evaluate(
          'D * cos(alpha)',
          variables: {'D': d, 'alpha': a},
          unit: TrigUnit.degrees,
        );
        final dy = ExpressionEvaluator.evaluate(
          'D * sin(alpha)',
          variables: {'D': d, 'alpha': a},
          unit: TrigUnit.degrees,
        );
        return _DiagramEvalResult(
          substituted:
              'ΔX = ${numStr(d)}·cos(${numStr(a)}°), ΔY = ${numStr(d)}·sin(${numStr(a)}°)',
          outputs: [
            _DiagramOutput(
              label: '北增量 ΔX',
              value: fmt(dx, 4),
              unit: 'm',
              emphasis: true,
            ),
            _DiagramOutput(
              label: '东增量 ΔY',
              value: fmt(dy, 4),
              unit: 'm',
              emphasis: true,
            ),
          ],
        );
      case _DiagramKind.heightAndSlope:
        final s = values['S']!;
        final a = values['alpha']!;
        final dh = ExpressionEvaluator.evaluate(
          'S * sin(alpha)',
          variables: {'S': s, 'alpha': a},
          unit: TrigUnit.degrees,
        );
        final d = ExpressionEvaluator.evaluate(
          'S * cos(alpha)',
          variables: {'S': s, 'alpha': a},
          unit: TrigUnit.degrees,
        );
        if (d.abs() < 1e-12) {
          return _DiagramEvalResult(
            substituted: 'Δh = ${numStr(s)} × sin(${numStr(a)}°)',
            error: '平距 D 为 0，无法计算坡度',
          );
        }
        final slopePct = (dh / d) * 100.0;
        return _DiagramEvalResult(
          substituted:
              'Δh = ${numStr(s)}·sin(${numStr(a)}°), i = ${fmt(dh, 3)} / ${fmt(d, 3)}',
          outputs: [
            _DiagramOutput(
              label: '高差 Δh',
              value: fmt(dh, 4),
              unit: 'm',
              emphasis: true,
            ),
            _DiagramOutput(
              label: '坡度 i',
              value: fmt(slopePct, 3),
              unit: '%',
              note: 'D = ${fmt(d, 3)} m',
            ),
          ],
        );
      case _DiagramKind.cosineSide:
        final a = values['a']!;
        final b = values['b']!;
        final angleC = values['C']!;
        if (a <= 0 || b <= 0) {
          return const _DiagramEvalResult(error: '边长须大于 0');
        }
        try {
          final c = ExpressionEvaluator.evaluate(
            'sqrt(a^2 + b^2 - 2*a*b*cos(C))',
            variables: {'a': a, 'b': b, 'C': angleC},
            unit: TrigUnit.degrees,
          );
          return _DiagramEvalResult(
            substituted:
                'c = √(${numStr(a)}² + ${numStr(b)}² - 2·${numStr(a)}·${numStr(b)}·cos(${numStr(angleC)}°))',
            outputs: [
              _DiagramOutput(
                label: '对边 c',
                value: fmt(c, 4),
                unit: 'm',
                emphasis: true,
              ),
            ],
          );
        } on FormulaException catch (e) {
          return _DiagramEvalResult(error: e.message);
        }
      case _DiagramKind.cosineAngle:
        final a = values['a']!;
        final b = values['b']!;
        final c = values['c']!;
        if (a <= 0 || b <= 0 || c <= 0) {
          return const _DiagramEvalResult(error: '三边长须大于 0');
        }
        final cosVal = (a * a + b * b - c * c) / (2 * a * b);
        if (cosVal < -1.0 || cosVal > 1.0) {
          return const _DiagramEvalResult(error: '三边不满足三角形不等式');
        }
        final degC = ExpressionEvaluator.evaluate(
          'deg(acos((a^2 + b^2 - c^2) / (2*a*b)))',
          variables: {'a': a, 'b': b, 'c': c},
          unit: TrigUnit.degrees,
        );
        return _DiagramEvalResult(
          substituted:
              'C = acos((${numStr(a)}² + ${numStr(b)}² - ${numStr(c)}²) / (2·${numStr(a)}·${numStr(b)}))',
          outputs: [
            _DiagramOutput(
              label: '夹角 C',
              value: fmt(degC, 4),
              unit: '°',
              emphasis: true,
            ),
          ],
        );
      case _DiagramKind.sineSide:
        final a = values['a']!;
        final angA = values['A']!;
        final angB = values['B']!;
        if (a <= 0) {
          return const _DiagramEvalResult(error: '边长须大于 0');
        }
        final sinA = math.sin(angA * math.pi / 180.0);
        if (sinA.abs() < 1e-12) {
          return const _DiagramEvalResult(error: 'sin(A) 不能为 0');
        }
        final b = ExpressionEvaluator.evaluate(
          'a * sin(B) / sin(A)',
          variables: {'a': a, 'A': angA, 'B': angB},
          unit: TrigUnit.degrees,
        );
        return _DiagramEvalResult(
          substituted:
              'b = ${numStr(a)} · sin(${numStr(angB)}°) / sin(${numStr(angA)}°)',
          outputs: [
            _DiagramOutput(
              label: '未知边 b',
              value: fmt(b, 4),
              unit: 'm',
              emphasis: true,
            ),
          ],
        );
    }
  }

  void _focusSlot(String key) {
    setState(() => _activeSlotKey = key);
    _focusNodes[key]?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final values = _readValues();
    final eval = _evaluate(values);
    final formula = _formula;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Insets.s,
          runSpacing: Insets.s,
          children: [
            for (var i = 0; i < _kDiagramFormulas.length; i++)
              ChoiceChip(
                label: Text(context.tr(_kDiagramFormulas[i].title)),
                selected: i == _selectedIndex,
                onSelected: (_) {
                  setState(() {
                    _selectedIndex = i;
                    _syncControllersForFormula();
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: Insets.m),
        SurfaceCard(
          padding: const EdgeInsets.all(Insets.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LocalText(
                          formula.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        LocalText(
                          formula.caption,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Insets.s),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Insets.s,
                        vertical: Insets.xs,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(Radii.chip),
                      ),
                      child: Text(
                        formula.equation,
                        style: TextStyle(
                          fontFamily: kSurveyMono,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.m),
              Container(
                height: 170,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(Radii.field),
                  border: Border.all(
                    color: IosColors.separator(scheme.brightness),
                  ),
                ),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _GeometryDiagramPainter(
                      kind: formula.kind,
                      values: values,
                      activeSlotKey: _activeSlotKey,
                      brightness: scheme.brightness,
                      primary: scheme.primary,
                      onSurface: scheme.onSurface,
                      muted: scheme.onSurfaceVariant,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              const SizedBox(height: Insets.m),
              LocalText(
                '点击槽位填入参数',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Insets.s),
              Wrap(
                spacing: Insets.s,
                runSpacing: Insets.s,
                children: [
                  for (final slot in formula.slots)
                    _SlotChip(
                      slot: slot,
                      value: values[slot.key],
                      selected: _activeSlotKey == slot.key,
                      onTap: () => _focusSlot(slot.key),
                    ),
                ],
              ),
              const SizedBox(height: Insets.m),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 520;
                  final fields = [
                    for (final slot in formula.slots)
                      _SlotNumberField(
                        slot: slot,
                        controller: _controllers[slot.key]!,
                        focusNode: _focusNodes[slot.key]!,
                        highlighted: _activeSlotKey == slot.key,
                        onChanged: () => setState(() {}),
                      ),
                  ];
                  if (!wide) {
                    return Column(
                      children: [
                        for (var i = 0; i < fields.length; i++) ...[
                          fields[i],
                          if (i < fields.length - 1)
                            const SizedBox(height: Insets.s),
                        ],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < fields.length; i++) ...[
                        Expanded(child: fields[i]),
                        if (i < fields.length - 1)
                          const SizedBox(width: Insets.s),
                      ],
                    ],
                  );
                },
              ),
              if (eval.substituted.isNotEmpty) ...[
                const SizedBox(height: Insets.m),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.m,
                    vertical: Insets.s,
                  ),
                  decoration: BoxDecoration(
                    color:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(Radii.field),
                  ),
                  child: SelectableText(
                    eval.substituted,
                    style: TextStyle(
                      fontFamily: kSurveyMono,
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: Insets.m),
              if (eval.error != null)
                Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: scheme.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.tr(eval.error!),
                        style: TextStyle(fontSize: 12.5, color: scheme.error),
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    for (final out in eval.outputs)
                      ResultTile(
                        label: out.label,
                        value: out.value,
                        unit: out.unit,
                        note: out.note,
                        emphasis: out.emphasis,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.slot,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final _DiagramSlotSpec slot;
  final double? value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final valText = value == null
        ? '[ ${slot.symbol} ]'
        : '[ ${slot.symbol} = ${fmt(value!, 4).replaceAll(RegExp(r'\.?0+$'), '')} ${slot.unit} ]';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: AnimatedContainer(
        duration: Motion.quick,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.14)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(
            color: selected
                ? scheme.primary
                : IosColors.separator(scheme.brightness),
            width: selected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          valText,
          style: TextStyle(
            fontFamily: kSurveyMono,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? scheme.primary : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _SlotNumberField extends StatelessWidget {
  const _SlotNumberField({
    required this.slot,
    required this.controller,
    required this.focusNode,
    required this.highlighted,
    required this.onChanged,
  });

  final _DiagramSlotSpec slot;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool highlighted;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      style: TextStyle(
        fontFamily: kSurveyMono,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: highlighted ? scheme.primary : scheme.onSurface,
      ),
      decoration: InputDecoration(
        labelText: context.tr(slot.label),
        suffixText: slot.unit,
        isDense: true,
      ),
      onChanged: (_) => onChanged(),
    );
  }
}

class _GeometryDiagramPainter extends CustomPainter {
  const _GeometryDiagramPainter({
    required this.kind,
    required this.values,
    required this.activeSlotKey,
    required this.brightness,
    required this.primary,
    required this.onSurface,
    required this.muted,
  });

  final _DiagramKind kind;
  final Map<String, double?> values;
  final String? activeSlotKey;
  final Brightness brightness;
  final Color primary;
  final Color onSurface;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final baseStroke = Paint()
      ..color = onSurface.withValues(alpha: 0.72)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final accentStroke = Paint()
      ..color = primary
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dashedPaint = Paint()
      ..color = muted.withValues(alpha: 0.55)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    switch (kind) {
      case _DiagramKind.slopeToHoriz:
      case _DiagramKind.heightAndSlope:
        final pA = Offset(size.width * 0.18, size.height * 0.76);
        final pB = Offset(size.width * 0.80, size.height * 0.76);
        final pC = Offset(size.width * 0.80, size.height * 0.24);
        canvas.drawLine(pA, pB, baseStroke);
        canvas.drawLine(pB, pC, baseStroke);
        canvas.drawLine(pA, pC, accentStroke);
        // 直角标记
        const sq = 11.0;
        canvas.drawPath(
          Path()
            ..moveTo(pB.dx - sq, pB.dy)
            ..lineTo(pB.dx - sq, pB.dy - sq)
            ..lineTo(pB.dx, pB.dy - sq),
          dashedPaint,
        );
        // 倾角弧
        canvas.drawArc(
          Rect.fromCircle(center: pA, radius: 30),
          -math.atan2(pB.dy - pC.dy, pB.dx - pA.dx),
          math.atan2(pB.dy - pC.dy, pB.dx - pA.dx),
          false,
          accentStroke,
        );
        _drawLabel(
          canvas,
          'S',
          values['S'],
          'm',
          Offset((pA.dx + pC.dx) / 2 - 28, (pA.dy + pC.dy) / 2 - 14),
          activeSlotKey == 'S',
        );
        _drawLabel(
          canvas,
          'α',
          values['alpha'],
          '°',
          Offset(pA.dx + 46, pA.dy - 18),
          activeSlotKey == 'alpha',
        );
        _drawStaticTag(
          canvas,
          kind == _DiagramKind.slopeToHoriz ? 'D' : 'D',
          Offset((pA.dx + pB.dx) / 2, pB.dy + 13),
        );
        _drawStaticTag(
          canvas,
          'Δh',
          Offset(pB.dx + 16, (pB.dy + pC.dy) / 2),
        );
        break;

      case _DiagramKind.coordIncrement:
        final origin = Offset(size.width * 0.30, size.height * 0.76);
        final northEnd = Offset(origin.dx, size.height * 0.16);
        final target = Offset(size.width * 0.74, size.height * 0.28);
        final projN = Offset(origin.dx, target.dy);
        canvas.drawLine(origin, northEnd, dashedPaint);
        canvas.drawLine(origin, projN, baseStroke);
        canvas.drawLine(projN, target, baseStroke);
        canvas.drawLine(origin, target, accentStroke);
        canvas.drawArc(
          Rect.fromCircle(center: origin, radius: 28),
          -math.pi / 2,
          math.atan2(target.dx - origin.dx, origin.dy - target.dy),
          false,
          accentStroke,
        );
        _drawStaticTag(canvas, 'N', Offset(origin.dx - 12, northEnd.dy));
        _drawStaticTag(
          canvas,
          'ΔX',
          Offset(origin.dx - 18, (origin.dy + projN.dy) / 2),
        );
        _drawStaticTag(
          canvas,
          'ΔY',
          Offset((projN.dx + target.dx) / 2, target.dy - 14),
        );
        _drawLabel(
          canvas,
          'D',
          values['D'],
          'm',
          Offset((origin.dx + target.dx) / 2 + 12,
              (origin.dy + target.dy) / 2 + 12),
          activeSlotKey == 'D',
        );
        _drawLabel(
          canvas,
          'α',
          values['alpha'],
          '°',
          Offset(origin.dx + 32, origin.dy - 36),
          activeSlotKey == 'alpha',
        );
        break;

      case _DiagramKind.cosineSide:
      case _DiagramKind.cosineAngle:
      case _DiagramKind.sineSide:
        final pA = Offset(size.width * 0.18, size.height * 0.76);
        final pB = Offset(size.width * 0.80, size.height * 0.76);
        final pC = Offset(size.width * 0.44, size.height * 0.22);
        final tri = Path()
          ..moveTo(pA.dx, pA.dy)
          ..lineTo(pB.dx, pB.dy)
          ..lineTo(pC.dx, pC.dy)
          ..close();
        canvas.drawPath(tri, baseStroke);
        if (kind == _DiagramKind.cosineSide) {
          canvas.drawLine(pA, pB, accentStroke);
        } else if (kind == _DiagramKind.sineSide) {
          canvas.drawLine(pA, pC, accentStroke);
        } else {
          canvas.drawArc(
            Rect.fromCircle(center: pC, radius: 22),
            math.atan2(pA.dy - pC.dy, pA.dx - pC.dx),
            math.atan2(pB.dy - pC.dy, pB.dx - pC.dx) -
                math.atan2(pA.dy - pC.dy, pA.dx - pC.dx),
            false,
            accentStroke,
          );
        }
        _drawLabel(
          canvas,
          'a',
          values['a'],
          'm',
          Offset((pB.dx + pC.dx) / 2 + 18, (pB.dy + pC.dy) / 2 - 4),
          activeSlotKey == 'a',
        );
        _drawLabel(
          canvas,
          'b',
          values['b'],
          'm',
          Offset((pA.dx + pC.dx) / 2 - 22, (pA.dy + pC.dy) / 2 - 4),
          activeSlotKey == 'b',
        );
        if (kind == _DiagramKind.cosineAngle) {
          _drawLabel(
            canvas,
            'c',
            values['c'],
            'm',
            Offset((pA.dx + pB.dx) / 2, pA.dy + 13),
            activeSlotKey == 'c',
          );
          _drawStaticTag(canvas, 'C', Offset(pC.dx, pC.dy - 14));
        } else if (kind == _DiagramKind.cosineSide) {
          _drawStaticTag(canvas, 'c', Offset((pA.dx + pB.dx) / 2, pA.dy + 13));
          _drawLabel(
            canvas,
            'C',
            values['C'],
            '°',
            Offset(pC.dx, pC.dy - 14),
            activeSlotKey == 'C',
          );
        } else {
          _drawLabel(
            canvas,
            'A',
            values['A'],
            '°',
            Offset(pA.dx - 16, pA.dy + 12),
            activeSlotKey == 'A',
          );
          _drawLabel(
            canvas,
            'B',
            values['B'],
            '°',
            Offset(pB.dx + 16, pB.dy + 12),
            activeSlotKey == 'B',
          );
        }
        break;
    }
  }

  void _drawLabel(
    Canvas canvas,
    String symbol,
    double? value,
    String unit,
    Offset center,
    bool active,
  ) {
    final text = value == null
        ? symbol
        : '$symbol=${fmt(value, 2).replaceAll(RegExp(r'\.?0+$'), '')}$unit';
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: kSurveyMono,
          fontSize: 11.5,
          fontWeight: active ? FontWeight.w700 : FontWeight.w600,
          color: active ? primary : onSurface,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: tp.width + 10,
        height: tp.height + 4,
      ),
      const Radius.circular(6),
    );
    final bg = Paint()
      ..color = active
          ? primary.withValues(alpha: 0.16)
          : (brightness == Brightness.dark
              ? IosColors.darkCard.withValues(alpha: 0.9)
              : IosColors.lightCard.withValues(alpha: 0.92));
    canvas.drawRRect(rect, bg);
    if (active) {
      canvas.drawRRect(
        rect,
        Paint()
          ..color = primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawStaticTag(Canvas canvas, String text, Offset center) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: kSurveyMono,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: muted,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _GeometryDiagramPainter old) {
    if (old.kind != kind ||
        old.activeSlotKey != activeSlotKey ||
        old.brightness != brightness ||
        old.primary != primary) {
      return true;
    }
    if (old.values.length != values.length) return true;
    for (final e in values.entries) {
      if (old.values[e.key] != e.value) return true;
    }
    return false;
  }
}

// ============================================================================
// 2. 积木拼图 (Block Builder)
// ============================================================================

enum _BlockKind {
  variable,
  number,
  functionOpen,
  operatorToken,
  parenOpen,
  parenClose,
}

class _PuzzleBlock {
  const _PuzzleBlock({
    required this.display,
    required this.evalToken,
    required this.kind,
    this.variableKey,
  });

  final String display;
  final String evalToken;
  final _BlockKind kind;
  final String? variableKey;
}

const List<_PuzzleBlock> _kVarConstBlocks = [
  _PuzzleBlock(
      display: 'S',
      evalToken: 'S',
      kind: _BlockKind.variable,
      variableKey: 'S'),
  _PuzzleBlock(
      display: 'D',
      evalToken: 'D',
      kind: _BlockKind.variable,
      variableKey: 'D'),
  _PuzzleBlock(
      display: 'α',
      evalToken: 'alpha',
      kind: _BlockKind.variable,
      variableKey: 'alpha'),
  _PuzzleBlock(
      display: 'β',
      evalToken: 'beta',
      kind: _BlockKind.variable,
      variableKey: 'beta'),
  _PuzzleBlock(
      display: 'a',
      evalToken: 'a',
      kind: _BlockKind.variable,
      variableKey: 'a'),
  _PuzzleBlock(
      display: 'b',
      evalToken: 'b',
      kind: _BlockKind.variable,
      variableKey: 'b'),
  _PuzzleBlock(display: 'π', evalToken: 'pi', kind: _BlockKind.variable),
];

const List<_PuzzleBlock> _kDigitBlocks = [
  _PuzzleBlock(display: '0', evalToken: '0', kind: _BlockKind.number),
  _PuzzleBlock(display: '1', evalToken: '1', kind: _BlockKind.number),
  _PuzzleBlock(display: '2', evalToken: '2', kind: _BlockKind.number),
  _PuzzleBlock(display: '3', evalToken: '3', kind: _BlockKind.number),
  _PuzzleBlock(display: '4', evalToken: '4', kind: _BlockKind.number),
  _PuzzleBlock(display: '5', evalToken: '5', kind: _BlockKind.number),
  _PuzzleBlock(display: '6', evalToken: '6', kind: _BlockKind.number),
  _PuzzleBlock(display: '7', evalToken: '7', kind: _BlockKind.number),
  _PuzzleBlock(display: '8', evalToken: '8', kind: _BlockKind.number),
  _PuzzleBlock(display: '9', evalToken: '9', kind: _BlockKind.number),
  _PuzzleBlock(display: '.', evalToken: '.', kind: _BlockKind.number),
];

const List<_PuzzleBlock> _kFunctionBlocks = [
  _PuzzleBlock(
      display: 'sin( )', evalToken: 'sin(', kind: _BlockKind.functionOpen),
  _PuzzleBlock(
      display: 'cos( )', evalToken: 'cos(', kind: _BlockKind.functionOpen),
  _PuzzleBlock(
      display: 'tan( )', evalToken: 'tan(', kind: _BlockKind.functionOpen),
  _PuzzleBlock(
      display: '√( )', evalToken: 'sqrt(', kind: _BlockKind.functionOpen),
  _PuzzleBlock(
      display: 'atan2( )', evalToken: 'atan2(', kind: _BlockKind.functionOpen),
  _PuzzleBlock(
      display: 'deg( )', evalToken: 'deg(', kind: _BlockKind.functionOpen),
  _PuzzleBlock(display: ',', evalToken: ',', kind: _BlockKind.operatorToken),
];

const List<_PuzzleBlock> _kOperatorBlocks = [
  _PuzzleBlock(display: '+', evalToken: '+', kind: _BlockKind.operatorToken),
  _PuzzleBlock(display: '-', evalToken: '-', kind: _BlockKind.operatorToken),
  _PuzzleBlock(display: '×', evalToken: '*', kind: _BlockKind.operatorToken),
  _PuzzleBlock(display: '÷', evalToken: '/', kind: _BlockKind.operatorToken),
  _PuzzleBlock(display: '^', evalToken: '^', kind: _BlockKind.operatorToken),
  _PuzzleBlock(display: '(', evalToken: '(', kind: _BlockKind.parenOpen),
  _PuzzleBlock(display: ')', evalToken: ')', kind: _BlockKind.parenClose),
];

const Map<String, double> _kDefaultBlockVars = {
  'S': 100,
  'D': 50,
  'alpha': 30,
  'beta': 45,
  'a': 3,
  'b': 4,
};

const Map<String, String> _kVarDisplayLabels = {
  'S': 'S',
  'D': 'D',
  'alpha': 'α (°)',
  'beta': 'β (°)',
  'a': 'a',
  'b': 'b',
};

/// 积木拼图视图：分类胶囊积木拼接表达式，点击表达式块可删除或聚焦括号内部，实时求值。
class FormulaBlockBuilderView extends StatefulWidget {
  const FormulaBlockBuilderView({super.key});

  @override
  State<FormulaBlockBuilderView> createState() =>
      _FormulaBlockBuilderViewState();
}

class _FormulaBlockBuilderViewState extends State<FormulaBlockBuilderView> {
  final List<_PuzzleBlock> _tokens = [
    _kVarConstBlocks[0], // S
    _kOperatorBlocks[2], // ×
    const _PuzzleBlock(
      display: 'cos(',
      evalToken: 'cos(',
      kind: _BlockKind.functionOpen,
    ),
    _kVarConstBlocks[2], // α
    _kOperatorBlocks[6], // )
  ];

  late int _cursorIndex = _tokens.length;

  final Map<String, TextEditingController> _varControllers = {
    for (final e in _kDefaultBlockVars.entries)
      e.key: TextEditingController(text: e.value.toInt().toString()),
  };

  @override
  void dispose() {
    for (final c in _varControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _insertBlock(_PuzzleBlock paletteBlock) {
    setState(() {
      if (paletteBlock.kind == _BlockKind.functionOpen) {
        final open = _PuzzleBlock(
          display:
              paletteBlock.evalToken == 'sqrt(' ? '√(' : paletteBlock.evalToken,
          evalToken: paletteBlock.evalToken,
          kind: _BlockKind.functionOpen,
        );
        const close = _PuzzleBlock(
          display: ')',
          evalToken: ')',
          kind: _BlockKind.parenClose,
        );
        _tokens.insert(_cursorIndex, open);
        _tokens.insert(_cursorIndex + 1, close);
        _cursorIndex += 1;
      } else {
        _tokens.insert(_cursorIndex, paletteBlock);
        _cursorIndex += 1;
      }
    });
  }

  void _onStripBlockTap(int index) {
    final block = _tokens[index];
    setState(() {
      if (block.kind == _BlockKind.functionOpen ||
          block.kind == _BlockKind.parenOpen) {
        // 如果光标已经在括号内紧邻处，再次点击则删除该块；否则把光标移入括号内
        if (_cursorIndex == index + 1) {
          _tokens.removeAt(index);
          _cursorIndex = index;
        } else {
          _cursorIndex = index + 1;
        }
      } else {
        _tokens.removeAt(index);
        if (_cursorIndex > index) {
          _cursorIndex--;
        }
      }
    });
  }

  void _backspace() {
    if (_cursorIndex <= 0 || _tokens.isEmpty) return;
    setState(() {
      _tokens.removeAt(_cursorIndex - 1);
      _cursorIndex--;
    });
  }

  void _clear() {
    setState(() {
      _tokens.clear();
      _cursorIndex = 0;
    });
  }

  String _compileExpression() {
    if (_tokens.isEmpty) return '';
    final buf = StringBuffer();
    for (var i = 0; i < _tokens.length; i++) {
      final cur = _tokens[i];
      if (i > 0) {
        final prev = _tokens[i - 1];
        final prevValueLike = prev.kind == _BlockKind.number ||
            prev.kind == _BlockKind.variable ||
            prev.kind == _BlockKind.parenClose;
        final curStartLike = cur.kind == _BlockKind.variable ||
            cur.kind == _BlockKind.functionOpen ||
            cur.kind == _BlockKind.parenOpen;
        final bothNumbers =
            prev.kind == _BlockKind.number && cur.kind == _BlockKind.number;
        if (prevValueLike && curStartLike && !bothNumbers) {
          buf.write('*');
        }
      }
      buf.write(cur.evalToken);
    }
    return buf.toString();
  }

  Set<String> _usedVariables() {
    final used = <String>{};
    for (final t in _tokens) {
      if (t.variableKey != null) {
        used.add(t.variableKey!);
      }
    }
    return used;
  }

  Map<String, double> _readVariables() {
    final map = <String, double>{};
    for (final e in _varControllers.entries) {
      final v = double.tryParse(e.value.text.trim());
      if (v != null) map[e.key] = v;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compiled = _compileExpression();
    final usedVars = _usedVariables();
    String? result;
    String? error;

    if (compiled.isNotEmpty) {
      try {
        final v = ExpressionEvaluator.evaluate(
          compiled,
          variables: _readVariables(),
          unit: TrigUnit.degrees,
        );
        result = fmt(v, 6);
      } on FormulaException catch (e) {
        error = e.message;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(Insets.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: LocalText(
                      '积木表达式',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _cursorIndex > 0 ? _backspace : null,
                    icon: const Icon(Icons.backspace_outlined, size: 16),
                    label: const LocalText('退格'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _tokens.isNotEmpty ? _clear : null,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const LocalText('清空'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.xs),
              LocalText(
                '点击积木块可删除，点击函数括号可聚焦内部继续拼接',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Insets.s),
              Container(
                constraints: const BoxConstraints(minHeight: 58),
                padding: const EdgeInsets.all(Insets.s),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(Radii.field),
                  border: Border.all(
                    color: IosColors.separator(scheme.brightness),
                  ),
                ),
                child: _tokens.isEmpty
                    ? Center(
                        child: LocalText(
                          '从下方点击积木块开始拼装公式',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (var i = 0; i <= _tokens.length; i++) ...[
                            if (i == _cursorIndex)
                              Container(
                                width: 2.5,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            if (i < _tokens.length)
                              _StripBlockPill(
                                block: _tokens[i],
                                onTap: () => _onStripBlockTap(i),
                              ),
                          ],
                        ],
                      ),
              ),
              if (usedVars.isNotEmpty) ...[
                const SizedBox(height: Insets.m),
                LocalText(
                  '变量赋值',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Insets.s),
                Wrap(
                  spacing: Insets.s,
                  runSpacing: Insets.s,
                  children: [
                    for (final key in usedVars)
                      SizedBox(
                        width: 128,
                        child: TextField(
                          controller: _varControllers[key],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          style: const TextStyle(
                            fontFamily: kSurveyMono,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            labelText: _kVarDisplayLabels[key] ?? key,
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: Insets.m),
              if (error != null)
                Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: scheme.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.tr(error),
                        style: TextStyle(fontSize: 12.5, color: scheme.error),
                      ),
                    ),
                  ],
                )
              else if (result != null)
                ResultTile(
                  label: '结果',
                  value: result,
                  note: compiled,
                  emphasis: true,
                ),
            ],
          ),
        ),
        const SizedBox(height: Insets.m),
        SurfaceCard(
          padding: const EdgeInsets.all(Insets.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PaletteSection(
                title: '变量与常数',
                blocks: const [..._kVarConstBlocks, ..._kDigitBlocks],
                onTap: _insertBlock,
              ),
              const SizedBox(height: Insets.m),
              _PaletteSection(
                title: '函数',
                blocks: _kFunctionBlocks,
                onTap: _insertBlock,
              ),
              const SizedBox(height: Insets.m),
              _PaletteSection(
                title: '运算符',
                blocks: _kOperatorBlocks,
                onTap: _insertBlock,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaletteSection extends StatelessWidget {
  const _PaletteSection({
    required this.title,
    required this.blocks,
    required this.onTap,
  });

  final String title;
  final List<_PuzzleBlock> blocks;
  final ValueChanged<_PuzzleBlock> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocalText(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Insets.s),
        Wrap(
          spacing: Insets.xs + 2,
          runSpacing: Insets.xs + 2,
          children: [
            for (final block in blocks)
              _StripBlockPill(
                block: block,
                onTap: () => onTap(block),
              ),
          ],
        ),
      ],
    );
  }
}

class _StripBlockPill extends StatelessWidget {
  const _StripBlockPill({
    required this.block,
    required this.onTap,
  });

  final _PuzzleBlock block;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final b = scheme.brightness;
    final Color tint = switch (block.kind) {
      _BlockKind.variable => IosColors.blue(b),
      _BlockKind.number => IosColors.teal(b),
      _BlockKind.functionOpen => IosColors.orange(b),
      _BlockKind.operatorToken => scheme.onSurfaceVariant,
      _BlockKind.parenOpen || _BlockKind.parenClose => IosColors.indigo(b),
    };

    return Material(
      color: tint.withValues(alpha: b == Brightness.dark ? 0.22 : 0.12),
      borderRadius: BorderRadius.circular(Radii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(
              color: tint.withValues(alpha: 0.38),
            ),
          ),
          child: Text(
            block.display,
            style: TextStyle(
              fontFamily: kSurveyMono,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: block.kind == _BlockKind.operatorToken
                  ? scheme.onSurface
                  : tint,
            ),
          ),
        ),
      ),
    );
  }
}
