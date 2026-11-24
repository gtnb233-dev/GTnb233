import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'overlays.dart';

/// 自定义点名预设方案。
class PointNamePreset {
  const PointNamePreset({
    required this.label,
    required this.buildNames,
  });

  final String label;
  final List<String> Function(int count, String startName) buildNames;
}

/// 批量/逐点自定义点名（号）与尺号配置弹窗。
///
/// 通过模态框编辑点名，不改变主页面表单字段数量与顺序。
Future<
    ({
      String startName,
      String backRod,
      String frontRod,
      List<String> names,
    })?> showPointNamesDialog(
  BuildContext context, {
  String title = '自定义点名（号）',
  String? startName,
  String startLabel = '起点名',
  required List<String> pointNames,
  String Function(int index, String prevPoint)? stationLabelBuilder,
  List<PointNamePreset>? presets,
  bool isClosed = false,
  bool showRodFields = false,
  String backRodLabel = '',
  String frontRodLabel = '',
}) {
  return SurveyModal.show<
      ({
        String startName,
        String backRod,
        String frontRod,
        List<String> names,
      })>(
    context,
    title: title,
    subtitle: '自定义点号与尺号将同步用于成果表与导出手簿',
    icon: Icons.edit_note_rounded,
    tone: ModalTone.info,
    maxWidth: 460,
    child: _PointNamesDialog(
      startName: startName,
      startLabel: startLabel,
      pointNames: pointNames,
      stationLabelBuilder: stationLabelBuilder,
      presets: presets,
      isClosed: isClosed,
      showRodFields: showRodFields,
      backRodLabel: backRodLabel,
      frontRodLabel: frontRodLabel,
    ),
  );
}

class _PointNamesDialog extends StatefulWidget {
  const _PointNamesDialog({
    required this.startName,
    required this.startLabel,
    required this.pointNames,
    required this.stationLabelBuilder,
    required this.presets,
    required this.isClosed,
    required this.showRodFields,
    required this.backRodLabel,
    required this.frontRodLabel,
  });

  final String? startName;
  final String startLabel;
  final List<String> pointNames;
  final String Function(int index, String prevPoint)? stationLabelBuilder;
  final List<PointNamePreset>? presets;
  final bool isClosed;
  final bool showRodFields;
  final String backRodLabel;
  final String frontRodLabel;

  @override
  State<_PointNamesDialog> createState() => _PointNamesDialogState();
}

class _PointNamesDialogState extends State<_PointNamesDialog> {
  late final TextEditingController _startCtrl;
  late final TextEditingController _backRodCtrl;
  late final TextEditingController _frontRodCtrl;
  late final List<TextEditingController> _nameCtrls;

  @override
  void initState() {
    super.initState();
    _startCtrl = TextEditingController(text: widget.startName ?? '');
    _backRodCtrl = TextEditingController(text: widget.backRodLabel);
    _frontRodCtrl = TextEditingController(text: widget.frontRodLabel);
    _nameCtrls = [
      for (final n in widget.pointNames) TextEditingController(text: n),
    ];
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _backRodCtrl.dispose();
    _frontRodCtrl.dispose();
    for (final c in _nameCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyPrefix(String prefix, {bool closeToStart = false}) {
    final start = _startCtrl.text.trim();
    for (var i = 0; i < _nameCtrls.length; i++) {
      if (closeToStart &&
          i == _nameCtrls.length - 1 &&
          start.isNotEmpty) {
        _nameCtrls[i].text = start;
      } else {
        _nameCtrls[i].text = '$prefix${i + 1}';
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final presets = widget.presets;
    final startVal =
        _startCtrl.text.trim().isEmpty ? (widget.startName ?? '起点') : _startCtrl.text.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
                spacing: Insets.xs,
                runSpacing: Insets.xs,
                children: [
                  if (presets != null)
                    for (final p in presets)
                      ActionChip(
                        label: Text(p.label, style: const TextStyle(fontSize: 11.5)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          final built = p.buildNames(_nameCtrls.length, startVal);
                          for (var i = 0; i < _nameCtrls.length && i < built.length; i++) {
                            _nameCtrls[i].text = built[i];
                          }
                          setState(() {});
                        },
                      )
                  else ...[
                    ActionChip(
                      label: const Text('转点 TP1, TP2…', style: TextStyle(fontSize: 11.5)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _applyPrefix('TP', closeToStart: widget.isClosed),
                    ),
                    ActionChip(
                      label: const Text('水准点 BM1, BM2…', style: TextStyle(fontSize: 11.5)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _applyPrefix('BM', closeToStart: widget.isClosed),
                    ),
                    ActionChip(
                      label: const Text('测点 P1, P2…', style: TextStyle(fontSize: 11.5)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _applyPrefix('P', closeToStart: widget.isClosed),
                    ),
                    if (_nameCtrls.isNotEmpty && widget.startName != null)
                      ActionChip(
                        label: const Text('末点闭合起点', style: TextStyle(fontSize: 11.5)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _nameCtrls.last.text = startVal;
                          setState(() {});
                        },
                      ),
                  ],
                ],
              ),
              const SizedBox(height: Insets.m),
              if (widget.startName != null) ...[
                TextField(
                  controller: _startCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: widget.startLabel,
                    hintText: '如 BM1',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: Insets.s),
              ],
              if (widget.showRodFields) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _backRodCtrl,
                        decoration: const InputDecoration(
                          labelText: '后尺号（可选）',
                          hintText: '如 5',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: Insets.s),
                    Expanded(
                      child: TextField(
                        controller: _frontRodCtrl,
                        decoration: const InputDecoration(
                          labelText: '前尺号（可选）',
                          hintText: '如 6',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.m),
              ],
              Text(
                '各站 / 各点编号',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Insets.xs),
              for (var i = 0; i < _nameCtrls.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.s),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 112,
                        child: Text(
                          widget.stationLabelBuilder != null
                              ? widget.stationLabelBuilder!(
                                  i,
                                  i == 0
                                      ? startVal
                                      : (_nameCtrls[i - 1].text.trim().isEmpty
                                          ? 'P$i'
                                          : _nameCtrls[i - 1].text.trim()),
                                )
                              : '第 ${i + 1} 站前点',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: Insets.s),
                      Expanded(
                        child: TextField(
                          controller: _nameCtrls[i],
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'TP${i + 1}',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
        const SizedBox(height: Insets.s),
        Divider(
          height: 1,
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
        const SizedBox(height: Insets.m),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: Insets.s,
            runSpacing: Insets.s,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop((
                    startName: _startCtrl.text.trim().isEmpty
                        ? (widget.startName ?? 'BM1')
                        : _startCtrl.text.trim(),
                    backRod: _backRodCtrl.text.trim(),
                    frontRod: _frontRodCtrl.text.trim(),
                    names: [
                      for (var i = 0; i < _nameCtrls.length; i++)
                        _nameCtrls[i].text.trim().isEmpty
                            ? 'P${i + 1}'
                            : _nameCtrls[i].text.trim(),
                    ],
                  ));
                },
                child: const Text('应用'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
