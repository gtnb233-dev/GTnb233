import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../l10n/survey_strings.dart';
import '../../state/settings.dart';
import '../../theme/tokens.dart';
import '../../theme/workspace_layout.dart';
import 'compact_controls.dart';
import 'liquid_glass.dart';
import 'workspace_commands.dart';

class MeasurementUnitsButton extends StatelessWidget {
  const MeasurementUnitsButton(
      {super.key,
      this.onLengthChanged,
      this.onAngleChanged,
      this.tight = false});

  final VoidCallback? onLengthChanged;
  final VoidCallback? onAngleChanged;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.maybeOf(context);
    if (settings == null) return const SizedBox.shrink();
    final label =
        '${settings.lengthUnit.symbol} · ${settings.angleMode.symbol}';
    return Tooltip(
      message: context.tr('单位与精度'),
      child: LiquidGlassSurface(
        borderRadius: BorderRadius.circular(Radii.pill),
        elevated: false,
        blurSigma: 12,
        width: tight ? 76 : null,
        child: TextButton(
          key: const ValueKey('measurement-units-button'),
          onPressed: () => _open(context, settings),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, style: const TextStyle(fontSize: 11)),
                ),
              ),
              const Icon(Icons.arrow_drop_down_rounded, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext pageContext, AppSettings settings) =>
      workspacePanel<void>(
        pageContext,
        '单位与精度',
        ListenableBuilder(
          listenable: settings,
          builder: (context, _) => Column(
            key: const ValueKey('measurement-units-panel'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const LocalText('角度输入格式'),
              const SizedBox(height: Insets.s),
              SurveySegmentedControl<AngleInputMode>(
                segments: const [
                  ButtonSegment(
                      value: AngleInputMode.dmsCompact,
                      label: LocalText('度分秒')),
                  ButtonSegment(
                      value: AngleInputMode.decimalDegrees,
                      label: LocalText('十进制度')),
                  ButtonSegment(
                      value: AngleInputMode.radians, label: LocalText('弧度')),
                ],
                selected: {settings.angleMode},
                onSelectionChanged: (values) {
                  final next = values.single;
                  if (next == settings.angleMode) return;
                  settings.setAngleMode(next);
                  _afterFieldUpdate(pageContext, onAngleChanged);
                },
              ),
              const SizedBox(height: Insets.m),
              const LocalText('长度输入量级'),
              const SizedBox(height: Insets.s),
              SurveySegmentedControl<LengthUnit>(
                segments: const [
                  ButtonSegment(
                      value: LengthUnit.meter, label: LocalText('米 (m)')),
                  ButtonSegment(
                      value: LengthUnit.centimeter,
                      label: LocalText('厘米 (cm)')),
                  ButtonSegment(
                      value: LengthUnit.millimeter,
                      label: LocalText('毫米 (mm)')),
                ],
                selected: {settings.lengthUnit},
                onSelectionChanged: (values) {
                  final next = values.single;
                  if (next == settings.lengthUnit) return;
                  settings.setLengthUnit(next);
                  _afterFieldUpdate(pageContext, onLengthChanged);
                },
              ),
              const SizedBox(height: Insets.m),
              _PrecisionStepper(
                key: const ValueKey('coordinate-precision'),
                label: '坐标小数位',
                value: settings.coordDigits,
                max: 6,
                onChanged: settings.setCoordDigits,
              ),
              _PrecisionStepper(
                key: const ValueKey('arcsecond-precision'),
                label: '角度秒小数位',
                value: settings.angleSecDigits,
                max: 3,
                onChanged: settings.setAngleSecDigits,
              ),
            ],
          ),
        ),
        useBottomSheet: WorkspaceHost.isAndroid(pageContext),
      );

  void _afterFieldUpdate(BuildContext context, VoidCallback? callback) {
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) callback();
    });
  }
}

class _PrecisionStepper extends StatelessWidget {
  const _PrecisionStepper(
      {super.key,
      required this.label,
      required this.value,
      required this.max,
      required this.onChanged});

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: LocalText(label)),
          IconButton(
            tooltip: context.tr('减少 {label}', {'label': context.tr(label)}),
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
              width: 24, child: Text('$value', textAlign: TextAlign.center)),
          IconButton(
            tooltip: context.tr('增加 {label}', {'label': context.tr(label)}),
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      );
}
