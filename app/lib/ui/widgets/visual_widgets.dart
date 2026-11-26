import 'package:flutter/material.dart';

import '../../l10n/survey_strings.dart';
import '../../theme/tokens.dart';

/// 限差进度仪表条：直观展示当前计算值占限差的比例与余量，
/// 或在推荐区间模式下展示所处区间（如交会角 30°–150°）。
class ToleranceGauge extends StatelessWidget {
  const ToleranceGauge({
    super.key,
    required this.label,
    required double value,
    required double limit,
    required this.valueText,
    required String limitText,
    this.ok,
  })  : _isRange = false,
        _value = value,
        _limit = limit,
        _min = 0,
        _max = 1,
        _goodMin = 0,
        _goodMax = 1,
        _rightLabel = limitText;

  const ToleranceGauge.range({
    super.key,
    required this.label,
    required double value,
    required double min,
    required double max,
    required double goodMin,
    required double goodMax,
    required this.valueText,
    required String rangeText,
    this.ok,
  })  : _isRange = true,
        _value = value,
        _limit = 1,
        _min = min,
        _max = max,
        _goodMin = goodMin,
        _goodMax = goodMax,
        _rightLabel = rangeText;

  final String label;
  final String valueText;
  final String _rightLabel;
  final bool? ok;

  final bool _isRange;
  final double _value;
  final double _limit;
  final double _min;
  final double _max;
  final double _goodMin;
  final double _goodMax;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final b = scheme.brightness;
    final isDark = b == Brightness.dark;
    final green = IosColors.green(b);
    final amber = IosColors.orange(b);
    final red = IosColors.red(b);

    if (_isRange) {
      final span = (_max - _min).abs() < 1e-9 ? 1.0 : (_max - _min);
      final pos = ((_value - _min) / span).clamp(0.0, 1.0);
      final gStart = ((_goodMin - _min) / span).clamp(0.0, 1.0);
      final gEnd = ((_goodMax - _min) / span).clamp(0.0, 1.0);
      final inGood = ok ?? (_value >= _goodMin && _value <= _goodMax);
      final statusColor = inGood ? green : scheme.error;
      final statusText = inGood ? '推荐区间' : '精度偏弱';

      return _GaugeFrame(
        label: label,
        valueText: valueText,
        rightLabel: _rightLabel,
        statusText: statusText,
        statusColor: statusColor,
        bar: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return SizedBox(
              height: 14,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: scheme.error.withValues(alpha: isDark ? 0.30 : 0.20),
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                  Positioned(
                    left: w * gStart,
                    width: (w * (gEnd - gStart)).clamp(4.0, w),
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: green.withValues(alpha: isDark ? 0.45 : 0.32),
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (w * pos - 5).clamp(0.0, (w - 10).clamp(0.0, w)),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.surface, width: 1.8),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    final absLimit = _limit.abs();
    final absVal = _value.abs();
    final ratio = absLimit <= 1e-12
        ? (absVal <= 1e-12 ? 0.0 : 1.5)
        : (absVal / absLimit);
    final passed = ok ?? (absLimit <= 1e-12 ? absVal <= 1e-12 : absVal <= absLimit);
    final statusColor = !passed
        ? red
        : ratio >= 0.70
            ? amber
            : green;
    final pct = (ratio * 100).clamp(0, 999).round();
    final statusText = passed ? '占用 $pct%' : '超限 $pct%';
    final fillRatio = (ratio / 1.2).clamp(0.0, 1.0);
    final limitMark = (1.0 / 1.2).clamp(0.0, 1.0);

    return _GaugeFrame(
      label: label,
      valueText: valueText,
      rightLabel: _rightLabel,
      statusText: statusText,
      statusColor: statusColor,
      bar: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return SizedBox(
            height: 16,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: isDark ? IosColors.darkTertiary : IosColors.lightFill,
                    borderRadius: BorderRadius.circular(Radii.chip),
                    border: Border.all(
                      color: IosColors.separator(b),
                      width: 1.0,
                    ),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: fillRatio,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(Radii.chip),
                    ),
                  ),
                ),
                // 100% 限差边界刻度线
                Positioned(
                  left: (w * limitMark - 1).clamp(0.0, (w - 2).clamp(0.0, w)),
                  child: Container(
                    width: 2,
                    height: 14,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GaugeFrame extends StatelessWidget {
  const _GaugeFrame({
    required this.label,
    required this.valueText,
    required this.rightLabel,
    required this.statusText,
    required this.statusColor,
    required this.bar,
  });

  final String label;
  final String valueText;
  final String rightLabel;
  final String statusText;
  final Color statusColor;
  final Widget bar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: Insets.s),
              Text(
                valueText,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  context.tr(statusText),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          bar,
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              context.tr(rightLabel),
              style: TextStyle(
                fontSize: 10.5,
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 流程/检核步骤状态。
enum PipelineStatus { ok, warn, error, pending }

/// 单个流程步骤定义。
class PipelineStep {
  const PipelineStep({
    required this.label,
    required this.status,
    this.detail,
    this.onTap,
  });

  final String label;
  final PipelineStatus status;
  final String? detail;
  final VoidCallback? onTap;
}

/// 执行与检核步骤状态流：自动折行适应 320dp 窄屏，异常节点可点击定位。
class PipelineStrip extends StatelessWidget {
  const PipelineStrip({super.key, required this.steps});

  final List<PipelineStep> steps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const green = Color(0xFF16A34A);
    const amber = Color(0xFFD97706);

    Color colorOf(PipelineStatus s) => switch (s) {
          PipelineStatus.ok => green,
          PipelineStatus.warn => amber,
          PipelineStatus.error => scheme.error,
          PipelineStatus.pending => scheme.onSurfaceVariant,
        };

    IconData iconOf(PipelineStatus s) => switch (s) {
          PipelineStatus.ok => Icons.check_circle_rounded,
          PipelineStatus.warn => Icons.warning_amber_rounded,
          PipelineStatus.error => Icons.cancel_rounded,
          PipelineStatus.pending => Icons.radio_button_unchecked,
        };

    return Wrap(
      spacing: 4,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Icon(
              Icons.chevron_right_rounded,
              size: 15,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          _StepChip(
            step: steps[i],
            color: colorOf(steps[i].status),
            icon: iconOf(steps[i].status),
          ),
        ],
      ],
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.step,
    required this.color,
    required this.icon,
  });

  final PipelineStep step;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            step.detail == null
                ? context.tr(step.label)
                : '${context.tr(step.label)} · ${context.tr(step.detail!)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: step.status == PipelineStatus.pending
                  ? scheme.onSurfaceVariant
                  : color,
            ),
          ),
        ],
      ),
    );
    if (step.onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.pill),
      onTap: step.onTap,
      child: content,
    );
  }
}
