import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:survey_core/survey_core.dart';

import '../../l10n/survey_strings.dart';
import '../../state/settings.dart';
import '../../theme/tokens.dart';
import 'liquid_glass.dart';
import 'overlays.dart';

class MeasurementUnitsButton extends StatelessWidget {
  const MeasurementUnitsButton({
    super.key,
    this.onLengthChanged,
    this.onAngleChanged,
    this.tight = false,
  });

  final VoidCallback? onLengthChanged;
  final VoidCallback? onAngleChanged;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.maybeOf(context);
    if (settings == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return LiquidGlassSurface(
      key: const ValueKey('measurement-units-button'),
      borderRadius: BorderRadius.circular(Radii.pill),
      elevated: false,
      blurSigma: 12,
      width: tight ? 76 : 94,
      height: 46,
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            _segment(
              key: const ValueKey('measurement-length-segment'),
              label: settings.lengthUnit.symbol,
              tooltip: context.tr('切换长度输入量级（当前：{unit}）',
                  {'unit': context.tr(settings.lengthUnit.label)}),
              onTap: () => _cycleLength(context, settings),
            ),
            Container(width: 1, height: 16, color: scheme.outlineVariant),
            _segment(
              key: const ValueKey('measurement-angle-segment'),
              label: settings.angleMode.symbol,
              tooltip: context.tr('点击切换角度输入格式（度分秒 / 十进制度 / 弧度）'),
              onTap: () => _cycleAngle(context, settings),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment({
    required Key key,
    required String label,
    required String tooltip,
    required VoidCallback onTap,
  }) =>
      Expanded(
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            key: key,
            onTap: onTap,
            child: SizedBox.expand(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  void _cycleLength(BuildContext context, AppSettings settings) {
    final units = LengthUnit.values;
    final next = units[(settings.lengthUnit.index + 1) % units.length];
    unawaited(settings.setLengthUnit(next));
    _feedback(context, settings, next.symbol, onLengthChanged);
  }

  void _cycleAngle(BuildContext context, AppSettings settings) {
    final modes = AngleInputMode.values;
    final next = modes[(settings.angleMode.index + 1) % modes.length];
    unawaited(settings.setAngleMode(next));
    _feedback(context, settings, next.symbol, onAngleChanged);
  }

  void _feedback(BuildContext context, AppSettings settings, String symbol,
      VoidCallback? onChanged) {
    if (settings.haptic) unawaited(HapticFeedback.selectionClick());
    SurveyToast.info(context, symbol,
        duration: const Duration(milliseconds: 500));
    if (onChanged != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) onChanged();
      });
    }
  }
}
