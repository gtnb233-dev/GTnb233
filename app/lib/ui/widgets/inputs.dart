import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:survey_core/survey_core.dart';

import '../../l10n/survey_strings.dart';
import '../../state/settings.dart';
import '../../theme/tokens.dart';
import 'foundation.dart';

/// 字段外壳：标签 + 可选计数/徽标/微操作 + 输入 + 说明。
class FieldShell extends StatelessWidget {
  const FieldShell({
    super.key,
    required this.label,
    required this.child,
    this.helper,
    this.trailing,
  });

  final String label;
  final Widget child;
  final String? helper;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                context.tr(label),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.1,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 6),
              trailing!,
            ],
          ],
        ),
        const SizedBox(height: 6),
        child,
        if (helper != null && helper!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            context.tr(helper!),
            style: TextStyle(
              fontSize: 11.5,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
              fontFamily: kSurveyMono,
              fontFamilyFallback: const ['Noto Sans SC'],
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}

/// 实数输入格式化：自动将中文全角小数点「。」与负号「－/−」规整为 ASCII，
/// 同时拦截重复小数点与非法位置负号。
class _SignedDecimalFormatter extends TextInputFormatter {
  const _SignedDecimalFormatter({required this.allowNegative});

  final bool allowNegative;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = newValue.text
        .replaceAll('。', '.')
        .replaceAll('．', '.')
        .replaceAll('－', '-')
        .replaceAll('−', '-')
        .replaceAll('—', '-');

    final buf = StringBuffer();
    var hasDot = false;
    var hasSign = false;
    for (var i = 0; i < normalized.length; i++) {
      final ch = normalized[i];
      if (ch == '-') {
        if (allowNegative && buf.isEmpty && !hasSign) {
          buf.write('-');
          hasSign = true;
        }
      } else if (ch == '.') {
        if (!hasDot) {
          buf.write('.');
          hasDot = true;
        }
      } else if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
        buf.write(ch);
      }
    }
    final text = buf.toString();
    final offset = newValue.selection.baseOffset.clamp(0, text.length);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// 规整角度输入中的中文标点、全角符号与空白。
String _normalizeAngleSymbols(String s) => s
    .replaceAll('。', '.')
    .replaceAll('．', '.')
    .replaceAll('－', '-')
    .replaceAll('−', '-')
    .replaceAll('—', '-')
    .replaceAll('\u3000', ' ')
    .replaceAll('：', ':')
    .replaceAll('，', ',')
    .replaceAll("'", '′')
    .replaceAll('’', '′')
    .replaceAll('"', '″')
    .replaceAll('”', '″');

enum _DmsPart { degree, minute, second }

enum _DecPart { integer, fraction }

/// 度 / 分 / 秒三格分格输入格式化器：支持空格与小数点自动跳格，以及整串角度粘贴自动拆格。
class _DmsCellFormatter extends TextInputFormatter {
  const _DmsCellFormatter({
    required this.part,
    required this.onAdvance,
    required this.onFullPaste,
  });

  final _DmsPart part;
  final VoidCallback onAdvance;
  final String? Function(String raw) onFullPaste;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final norm = _normalizeAngleSymbols(newValue.text);
    final sepPattern = RegExp(r'[.\s:°′″度分秒,]+');
    final segs =
        norm.split(sepPattern).where((e) => e.isNotEmpty && e != '-').toList();

    // 若一次贴入整串角度（如 48.4318 / 48 43 18 / 48.43.18），自动拆进度分秒三格
    final delta = newValue.text.length - oldValue.text.length;
    final looksLikePaste =
        (delta > 1 || (oldValue.text.isEmpty && segs.length >= 2)) &&
            segs.length >= 2 &&
            (part != _DmsPart.second ||
                norm.contains(RegExp(r'[\s:°′度分,]')) ||
                '.'.allMatches(norm).length >= 2);
    if (looksLikePaste) {
      final replaced = onFullPaste(norm);
      if (replaced != null) {
        return TextEditingValue(
          text: replaced,
          selection: TextSelection.collapsed(offset: replaced.length),
        );
      }
    }

    switch (part) {
      case _DmsPart.degree:
        final jumped = RegExp(r'[.\s:°]').hasMatch(norm);
        final buf = StringBuffer();
        for (var i = 0; i < norm.length; i++) {
          final ch = norm[i];
          if (ch == '-' && buf.isEmpty) {
            buf.write('-');
          } else if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
            if (buf.length < (buf.toString().startsWith('-') ? 5 : 4)) {
              buf.write(ch);
            }
          }
        }
        final out = buf.toString();
        if (jumped) {
          onAdvance();
          return TextEditingValue(
            text: out,
            selection: TextSelection.collapsed(offset: out.length),
          );
        }
        return TextEditingValue(
          text: out,
          selection: TextSelection.collapsed(
            offset: newValue.selection.baseOffset.clamp(0, out.length),
          ),
        );

      case _DmsPart.minute:
        final jumped = RegExp(r"[.\s:′']").hasMatch(norm);
        final digits = norm.replaceAll(RegExp(r'[^0-9]'), '');
        final out = digits.length > 3 ? digits.substring(0, 3) : digits;
        if (jumped) {
          onAdvance();
          return TextEditingValue(
            text: out,
            selection: TextSelection.collapsed(offset: out.length),
          );
        }
        return TextEditingValue(
          text: out,
          selection: TextSelection.collapsed(
            offset: newValue.selection.baseOffset.clamp(0, out.length),
          ),
        );

      case _DmsPart.second:
        final jumped = RegExp(r'[\s″"]').hasMatch(norm);
        final buf = StringBuffer();
        var hasDot = false;
        var intLen = 0;
        var fracLen = 0;
        for (var i = 0; i < norm.length; i++) {
          final ch = norm[i];
          if (ch == '.') {
            if (!hasDot && buf.isNotEmpty) {
              buf.write('.');
              hasDot = true;
            }
          } else if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
            if (!hasDot) {
              if (intLen < 3) {
                buf.write(ch);
                intLen++;
              }
            } else if (fracLen < 3) {
              buf.write(ch);
              fracLen++;
            }
          }
        }
        final out = buf.toString();
        if (jumped) {
          onAdvance();
          return TextEditingValue(
            text: out,
            selection: TextSelection.collapsed(offset: out.length),
          );
        }
        return TextEditingValue(
          text: out,
          selection: TextSelection.collapsed(
            offset: newValue.selection.baseOffset.clamp(0, out.length),
          ),
        );
    }
  }
}

/// 十进制度双格（整数度 . | 小数 °）分格输入格式化器：支持空格/小数点跳格与整串角度粘贴拆格。
class _DecCellFormatter extends TextInputFormatter {
  const _DecCellFormatter({
    required this.part,
    required this.onAdvance,
    required this.onFullPaste,
  });

  final _DecPart part;
  final VoidCallback onAdvance;
  final String? Function(String raw) onFullPaste;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final norm = _normalizeAngleSymbols(newValue.text);
    final sepPattern = RegExp(r'[.\s:°′″度分秒,]+');
    final segs =
        norm.split(sepPattern).where((e) => e.isNotEmpty && e != '-').toList();

    if (segs.length >= 2) {
      final replaced = onFullPaste(norm);
      if (replaced != null) {
        return TextEditingValue(
          text: replaced,
          selection: TextSelection.collapsed(offset: replaced.length),
        );
      }
    }

    switch (part) {
      case _DecPart.integer:
        final jumped = RegExp(r'[.\s:°]').hasMatch(norm);
        final buf = StringBuffer();
        for (var i = 0; i < norm.length; i++) {
          final ch = norm[i];
          if (ch == '-' && buf.isEmpty) {
            buf.write('-');
          } else if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
            if (buf.length < (buf.toString().startsWith('-') ? 5 : 4)) {
              buf.write(ch);
            }
          }
        }
        final out = buf.toString();
        if (jumped) {
          onAdvance();
          return TextEditingValue(
            text: out,
            selection: TextSelection.collapsed(offset: out.length),
          );
        }
        return TextEditingValue(
          text: out,
          selection: TextSelection.collapsed(
            offset: newValue.selection.baseOffset.clamp(0, out.length),
          ),
        );

      case _DecPart.fraction:
        final jumped = RegExp(r'[\s°]').hasMatch(norm);
        final digits = norm.replaceAll(RegExp(r'[^0-9]'), '');
        final out = digits.length > 10 ? digits.substring(0, 10) : digits;
        if (jumped) {
          onAdvance();
          return TextEditingValue(
            text: out,
            selection: TextSelection.collapsed(offset: out.length),
          );
        }
        return TextEditingValue(
          text: out,
          selection: TextSelection.collapsed(
            offset: newValue.selection.baseOffset.clamp(0, out.length),
          ),
        );
    }
  }
}

/// 数值输入框：带实数格式化、等宽数字、轴/量标签、单位胶囊、一键清除与量级自动换算提示。
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.controller,
    this.label,
    this.unit,
    this.lengthUnit,
    this.prefixTag,
    this.hint,
    this.helper,
    this.enabled = true,
    this.onChanged,
    this.allowNegative = true,
    this.autofocus = false,
    this.showClearButton = true,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? label;
  final String? unit;

  /// 若传入厘米/毫米量级且未显式覆盖 [unit]，自动使用其单位徽标并在下方附「= x.xxxx m」提示。
  final LengthUnit? lengthUnit;
  final String? prefixTag;
  final String? hint;
  final String? helper;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final bool allowNegative;
  final bool autofocus;
  final bool showClearButton;
  final ValueChanged<String>? onSubmitted;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_scheduleRefresh);
    widget.controller.addListener(_scheduleRefresh);
  }

  @override
  void didUpdateWidget(covariant NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleRefresh);
      widget.controller.addListener(_scheduleRefresh);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_scheduleRefresh);
    _focus.dispose();
    widget.controller.removeListener(_scheduleRefresh);
    super.dispose();
  }

  void _scheduleRefresh() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final raw = widget.controller.text.trim();
    final isIncomplete = raw.isEmpty || raw == '-' || raw == '.' || raw == '-.';
    final parsed = isIncomplete ? null : double.tryParse(raw);
    final invalid = !isIncomplete && (parsed == null || !parsed.isFinite);
    final effectiveUnit = widget.unit ?? widget.lengthUnit?.symbol;

    String? mergedHelper() {
      final parts = <String>[
        if (widget.helper != null && widget.helper!.isNotEmpty) widget.helper!,
        if (widget.lengthUnit != null &&
            widget.lengthUnit != LengthUnit.meter &&
            parsed != null &&
            parsed.isFinite)
          '= ${fmt(widget.lengthUnit!.toMeters(parsed), 4)} m',
      ];
      return parts.isEmpty ? null : parts.join(' · ');
    }

    final showClear = widget.showClearButton &&
        widget.enabled &&
        _focus.hasFocus &&
        raw.isNotEmpty;

    Widget? suffix;
    if (showClear || (effectiveUnit != null && effectiveUnit.isNotEmpty)) {
      suffix = Padding(
        padding: const EdgeInsets.only(right: 8, left: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showClear)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  widget.controller.clear();
                  widget.onChanged?.call('');
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (effectiveUnit != null && effectiveUnit.isNotEmpty) ...[
              if (showClear) const SizedBox(width: 2),
              _InlineBadge(
                label: effectiveUnit,
                accent: widget.lengthUnit != null &&
                    widget.lengthUnit != LengthUnit.meter,
              ),
            ],
          ],
        ),
      );
    }

    Widget? prefix;
    if (widget.prefixTag != null && widget.prefixTag!.isNotEmpty) {
      prefix = Padding(
        padding: const EdgeInsets.only(left: 10, right: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            widget.prefixTag!,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ),
      );
    }

    final defaultHint = switch (widget.lengthUnit) {
      LengthUnit.centimeter => '0.00',
      LengthUnit.millimeter => '0.0',
      _ => '0.000',
    };

    final field = TextField(
      controller: widget.controller,
      focusNode: _focus,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: widget.allowNegative,
      ),
      textInputAction: TextInputAction.next,
      style: const TextStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      inputFormatters: [
        _SignedDecimalFormatter(allowNegative: widget.allowNegative),
      ],
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        hintText: widget.hint ?? defaultHint,
        errorText: invalid ? '请输入有效数值' : null,
        prefixIcon: prefix,
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 28),
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 28),
      ),
    );
    if (widget.label == null) return field;
    return FieldShell(
      label: widget.label!,
      helper: mergedHelper(),
      child: field,
    );
  }
}

/// 文本输入框。
class TextValueField extends StatelessWidget {
  const TextValueField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.helper,
    this.enabled = true,
    this.maxLines = 1,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final String? helper;
  final bool enabled;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      onChanged: onChanged,
      decoration: InputDecoration(hintText: hint),
    );
    if (label == null) return field;
    return FieldShell(label: label!, helper: helper, child: field);
  }
}

/// 批量多行坐标/观测列表输入框：内置有效行数徽标、格式示例与快捷粘贴/清空操作。
///
/// 内部只保留单一 [TextField]，与页面级既有表单下标完全兼容。
class DataTextField extends StatefulWidget {
  const DataTextField({
    super.key,
    required this.controller,
    required this.label,
    this.fieldLabel,
    this.hint,
    this.helper,
    this.formatHint,
    this.unit,
    this.minLines = 3,
    this.maxLines = 6,
    this.countLabel,
    this.showPasteClear = true,
    this.showLineNumbers = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? fieldLabel;
  final String? hint;
  final String? helper;
  final String? formatHint;
  final String? unit;
  final int minLines;
  final int maxLines;
  final String Function(String text)? countLabel;
  final bool showPasteClear;
  final bool showLineNumbers;
  final ValueChanged<String>? onChanged;

  @override
  State<DataTextField> createState() => _DataTextFieldState();
}

class _DataTextFieldState extends State<DataTextField> {
  final ScrollController _textScroll = ScrollController();
  final ScrollController _gutterScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _textScroll.addListener(_syncGutterScroll);
  }

  void _syncGutterScroll() {
    if (!_textScroll.hasClients || !_gutterScroll.hasClients) return;
    final target =
        _textScroll.offset.clamp(0.0, _gutterScroll.position.maxScrollExtent);
    if ((_gutterScroll.offset - target).abs() > 0.5) {
      _gutterScroll.jumpTo(target);
    }
  }

  @override
  void didUpdateWidget(covariant DataTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _textScroll.removeListener(_syncGutterScroll);
    _textScroll.dispose();
    _gutterScroll.dispose();
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    final txt = data?.text;
    if (txt == null || txt.isEmpty) return;
    widget.controller.text = txt.trimRight();
    widget.onChanged?.call(widget.controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = widget.controller.text;
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).length;
    final badge = widget.countLabel?.call(text) ??
        (widget.unit == null ? '$lines 行' : '$lines 行 · ${widget.unit}');

    final helperParts = <String>[
      if (widget.formatHint != null && widget.formatHint!.isNotEmpty)
        '格式：${widget.formatHint!}',
      if (widget.helper != null && widget.helper!.isNotEmpty) widget.helper!,
    ];

    return FieldShell(
      label: widget.label,
      helper: helperParts.isEmpty ? null : helperParts.join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _InlineBadge(label: badge, accent: lines > 0),
          if (widget.showPasteClear) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: '从剪贴板粘贴',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: _paste,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    Icons.content_paste_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (text.trim().isNotEmpty)
              Tooltip(
                message: '清空此框',
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    widget.controller.clear();
                    widget.onChanged?.call('');
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.clear_rounded,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
      child: widget.showLineNumbers && widget.fieldLabel == null
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(
                  builder: (context) {
                    final totalLines = math.max(
                      widget.minLines,
                      '\n'.allMatches(text).length + 1,
                    );
                    final textScale =
                        MediaQuery.textScalerOf(context).scale(13.5) / 13.5;
                    final lineH = 13.5 * 1.4 * textScale;
                    final boxMaxH = widget.maxLines * lineH + 26;
                    final nums = List<String>.generate(
                      totalLines,
                      (i) => '${i + 1}',
                    ).join('\n');
                    return ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: boxMaxH),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 13, right: 6),
                        child: SingleChildScrollView(
                          controller: _gutterScroll,
                          physics: const NeverScrollableScrollPhysics(),
                          child: SizedBox(
                            width: totalLines >= 100 ? 28 : 22,
                            child: Text(
                              nums,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.4,
                                color: scheme.onSurfaceVariant
                                    .withValues(alpha: 0.45),
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    scrollController: _textScroll,
                    maxLines: widget.maxLines,
                    minLines: widget.minLines,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: InputDecoration(
                      labelText: widget.fieldLabel,
                      hintText: widget.hint,
                    ),
                    onChanged: widget.onChanged,
                  ),
                ),
              ],
            )
          : TextField(
              controller: widget.controller,
              maxLines: widget.maxLines,
              minLines: widget.minLines,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                labelText: widget.fieldLabel,
                hintText: widget.hint,
              ),
              onChanged: widget.onChanged,
            ),
    );
  }
}

/// 角度输入。
///
/// - [AngleInputMode.dmsCompact]（默认）：展示「度° / 分′ / 秒″」三格联动输入框，
///   支持空格或小数点自动跳格，也支持整串 `GG.MMSS`、`90 30 15`、`90.30.15` 粘贴自动拆格，
///   内部与外部 [controller] 双向同步为标准 `GG.MMSS`。
/// - [AngleInputMode.decimalDegrees]：单格十进制度输入，同时兼容空格与多小数点度分秒直填解析。
class AngleField extends StatefulWidget {
  const AngleField({
    super.key,
    this.label = '角度',
    this.mode = AngleInputMode.dmsCompact,
    this.initialDegrees,
    this.onChanged,
    this.enabled = true,
    this.helper,
    this.secDigits = 1,
    this.controller,
  });

  final String label;
  final AngleInputMode mode;
  final double? initialDegrees;
  final ValueChanged<double?>? onChanged;
  final bool enabled;
  final String? helper;

  /// 回显度分秒时秒的小数位。
  final int secDigits;

  /// 外部文本控制器（可选）。
  final TextEditingController? controller;

  @override
  State<AngleField> createState() => AngleFieldState();
}

class AngleFieldState extends State<AngleField> {
  TextEditingController? _owned;
  final _degCtrl = TextEditingController();
  final _minCtrl = TextEditingController();
  final _secCtrl = TextEditingController();
  final _decIntCtrl = TextEditingController();
  final _decFracCtrl = TextEditingController();

  late final FocusNode _degFocus;
  late final FocusNode _minFocus;
  late final FocusNode _secFocus;
  late final FocusNode _decIntFocus;
  late final FocusNode _decFracFocus;

  double? _value;
  String? _formatError;
  bool _syncingExternal = false;
  bool _syncingCells = false;

  /// 当前角度值（度）；输入为空或无法解析时为 null。
  double? get value => _value;

  bool get _decimal => widget.mode == AngleInputMode.decimalDegrees;

  bool get _anyFocused => _decimal
      ? (_decIntFocus.hasFocus || _decFracFocus.hasFocus)
      : (_degFocus.hasFocus || _minFocus.hasFocus || _secFocus.hasFocus);

  TextEditingController get _text =>
      widget.controller ?? (_owned ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _degFocus = FocusNode()..addListener(_onFocusChanged);
    _minFocus = FocusNode(onKeyEvent: _handleMinKeyEvent)
      ..addListener(_onFocusChanged);
    _secFocus = FocusNode(onKeyEvent: _handleSecKeyEvent)
      ..addListener(_onFocusChanged);
    _decIntFocus = FocusNode()..addListener(_onFocusChanged);
    _decFracFocus = FocusNode(onKeyEvent: _handleDecFracKeyEvent)
      ..addListener(_onFocusChanged);

    _text.addListener(_onExternalTextChanged);
    _degCtrl.addListener(_onCellChanged);
    _minCtrl.addListener(_onCellChanged);
    _secCtrl.addListener(_onCellChanged);
    _decIntCtrl.addListener(_onCellChanged);
    _decFracCtrl.addListener(_onCellChanged);

    final init = widget.initialDegrees;
    if (init != null && _text.text.trim().isEmpty) {
      setDegrees(init);
    } else {
      _pullFromExternal(notify: false);
    }
  }

  @override
  void didUpdateWidget(covariant AngleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final oldCtrl = oldWidget.controller ?? _owned;
      oldCtrl?.removeListener(_onExternalTextChanged);
      _text.addListener(_onExternalTextChanged);
      _pullFromExternal(notify: false);
    }
    if (oldWidget.mode != widget.mode) {
      final v = _value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (v != null) {
          setDegrees(v);
        } else {
          _pullFromExternal(notify: false);
        }
      });
    }
  }

  @override
  void dispose() {
    _text.removeListener(_onExternalTextChanged);
    _degCtrl.removeListener(_onCellChanged);
    _minCtrl.removeListener(_onCellChanged);
    _secCtrl.removeListener(_onCellChanged);
    _decIntCtrl.removeListener(_onCellChanged);
    _decFracCtrl.removeListener(_onCellChanged);
    _degCtrl.dispose();
    _minCtrl.dispose();
    _secCtrl.dispose();
    _decIntCtrl.dispose();
    _decFracCtrl.dispose();
    _degFocus.dispose();
    _minFocus.dispose();
    _secFocus.dispose();
    _decIntFocus.dispose();
    _decFracFocus.dispose();
    _owned?.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() {});
  }

  KeyEventResult _handleMinKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _minCtrl.text.isEmpty) {
      _focusWithCursorEnd(_degFocus, _degCtrl);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleSecKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _secCtrl.text.isEmpty) {
      _focusWithCursorEnd(_minFocus, _minCtrl);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleDecFracKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _decFracCtrl.text.isEmpty) {
      _focusWithCursorEnd(_decIntFocus, _decIntCtrl);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _focusWithCursorEnd(FocusNode focus, TextEditingController ctrl) {
    Future.microtask(() {
      if (!mounted) return;
      focus.requestFocus();
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    });
  }

  void _advanceTo(FocusNode nextFocus, TextEditingController nextCtrl) {
    Future.microtask(() {
      if (!mounted) return;
      nextFocus.requestFocus();
      nextCtrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: nextCtrl.text.length,
      );
    });
  }

  void _advanceToNextField() {
    Future.microtask(() {
      if (!mounted) return;
      FocusScope.of(context).nextFocus();
    });
  }

  (String deg, String min, String sec) _dmsPartsFor(double deg) {
    final dms = degToDms(deg, secDigits: widget.secDigits);
    final degStr = '${dms.isNegative ? '-' : ''}${dms.degree.abs()}';
    final minStr = dms.minute.toString().padLeft(2, '0');
    final intSec = dms.second.floor();
    final secIntStr = intSec.toString().padLeft(2, '0');
    if (widget.secDigits <= 0) {
      return (degStr, minStr, dms.second.round().toString().padLeft(2, '0'));
    }
    final formatted = dms.second.toStringAsFixed(widget.secDigits);
    final dot = formatted.indexOf('.');
    if (dot < 0) {
      return (degStr, minStr, formatted.padLeft(2, '0'));
    }
    var frac = formatted.substring(dot + 1);
    while (frac.endsWith('0')) {
      frac = frac.substring(0, frac.length - 1);
    }
    final secStr = frac.isEmpty ? secIntStr : '$secIntStr.$frac';
    return (degStr, minStr, secStr);
  }

  (String intPart, String fracPart) _decPartsFor(double deg) {
    final neg = deg < 0 || (deg == 0 && deg.isNegative);
    final formatted = deg.abs().toStringAsFixed(8);
    final dot = formatted.indexOf('.');
    final intDigits = formatted.substring(0, dot);
    var frac = formatted.substring(dot + 1);
    while (frac.length > 1 && frac.endsWith('0')) {
      frac = frac.substring(0, frac.length - 1);
    }
    return ('${neg ? '-' : ''}$intDigits', frac);
  }

  void _writeDmsCells(String deg, String min, String sec) {
    _syncingCells = true;
    try {
      if (_degCtrl.text != deg) _degCtrl.text = deg;
      if (_minCtrl.text != min) _minCtrl.text = min;
      if (_secCtrl.text != sec) _secCtrl.text = sec;
    } finally {
      _syncingCells = false;
    }
  }

  void _writeDecCells(String intPart, String fracPart) {
    _syncingCells = true;
    try {
      if (_decIntCtrl.text != intPart) _decIntCtrl.text = intPart;
      if (_decFracCtrl.text != fracPart) _decFracCtrl.text = fracPart;
    } finally {
      _syncingCells = false;
    }
  }

  String? _applyFullAnglePaste(_DmsPart targetPart, String raw) {
    try {
      final parsed = parseAngle(raw, mode: widget.mode);
      final parts = _dmsPartsFor(parsed);
      _syncingCells = true;
      try {
        if (targetPart != _DmsPart.degree) _degCtrl.text = parts.$1;
        if (targetPart != _DmsPart.minute) _minCtrl.text = parts.$2;
        if (targetPart != _DmsPart.second) _secCtrl.text = parts.$3;
      } finally {
        _syncingCells = false;
      }
      Future.microtask(() {
        if (mounted) _onCellChanged();
      });
      return switch (targetPart) {
        _DmsPart.degree => parts.$1,
        _DmsPart.minute => parts.$2,
        _DmsPart.second => parts.$3,
      };
    } on FormatException {
      return null;
    }
  }

  String? _applyFullDecimalPaste(_DecPart targetPart, String raw) {
    try {
      final parsed = parseAngle(raw, mode: widget.mode);
      final parts = _decPartsFor(parsed);
      _syncingCells = true;
      try {
        if (targetPart != _DecPart.integer) _decIntCtrl.text = parts.$1;
        if (targetPart != _DecPart.fraction) _decFracCtrl.text = parts.$2;
      } finally {
        _syncingCells = false;
      }
      Future.microtask(() {
        if (mounted) _onCellChanged();
      });
      return targetPart == _DecPart.integer ? parts.$1 : parts.$2;
    } on FormatException {
      return null;
    }
  }

  /// 清空输入并通知外层。
  void clear() {
    _syncingExternal = true;
    try {
      _text.clear();
    } finally {
      _syncingExternal = false;
    }
    _writeDmsCells('', '', '');
    _writeDecCells('', '');
    _value = null;
    _formatError = null;
    _scheduleRefresh(notifyChanged: true);
  }

  /// 以度为单位写入输入框。
  void setDegrees(double deg) {
    final extText = _decimal
        ? deg.toStringAsFixed(6)
        : fmtDmsCompact(deg, secDigits: widget.secDigits);
    _value = deg;
    _formatError = null;
    _syncingExternal = true;
    try {
      _text.text = extText;
    } finally {
      _syncingExternal = false;
    }
    if (_decimal) {
      final parts = _decPartsFor(deg);
      _writeDecCells(parts.$1, parts.$2);
    } else {
      final parts = _dmsPartsFor(deg);
      _writeDmsCells(parts.$1, parts.$2, parts.$3);
    }
    _scheduleRefresh(notifyChanged: false);
  }

  void _onExternalTextChanged() {
    if (_syncingExternal) return;
    _pullFromExternal(notify: true);
  }

  void _pullFromExternal({required bool notify}) {
    final prevVal = _value;
    final prevErr = _formatError;
    final raw = _text.text.trim();
    if (raw.isEmpty || raw == '-' || raw == '.' || raw == '-.') {
      _value = null;
      _formatError = null;
      if (_decimal) {
        _writeDecCells('', '');
      } else {
        _writeDmsCells('', '', '');
      }
    } else {
      try {
        final parsed = parseAngle(raw, mode: widget.mode);
        _value = parsed;
        _formatError = null;
        if (_decimal) {
          final parts = _decPartsFor(parsed);
          _writeDecCells(parts.$1, parts.$2);
        } else {
          final parts = _dmsPartsFor(parsed);
          _writeDmsCells(parts.$1, parts.$2, parts.$3);
        }
      } on FormatException catch (e) {
        _value = null;
        _formatError = e.message.isNotEmpty
            ? e.message
            : (_decimal ? '请输入有效十进制度' : '分/秒须小于 60，示例 90 30 30');
      }
    }
    if (prevVal != _value || prevErr != _formatError) {
      _scheduleRefresh(notifyChanged: notify && prevVal != _value);
    }
  }

  void _onCellChanged() {
    if (_syncingCells) return;
    final prevVal = _value;
    final prevErr = _formatError;

    if (_decimal) {
      final iRaw = _decIntCtrl.text.trim();
      final fRaw = _decFracCtrl.text.trim();
      if ((iRaw.isEmpty || iRaw == '-') && fRaw.isEmpty) {
        _value = null;
        _formatError = null;
        _syncingExternal = true;
        try {
          if (_text.text.isNotEmpty) _text.text = '';
        } finally {
          _syncingExternal = false;
        }
      } else {
        final neg = iRaw.startsWith('-');
        final iDigits = (neg ? iRaw.substring(1) : iRaw).trim();
        final intPart = iDigits.isEmpty ? '0' : iDigits;
        final combined =
            '${neg ? '-' : ''}$intPart${fRaw.isEmpty ? '' : '.$fRaw'}';
        final parsed = double.tryParse(combined);
        if (parsed == null || !parsed.isFinite) {
          _value = null;
          _formatError = '请输入有效十进制度';
          _syncingExternal = true;
          try {
            if (_text.text.isNotEmpty) _text.text = '';
          } finally {
            _syncingExternal = false;
          }
        } else {
          _value = parsed;
          _formatError = null;
          _syncingExternal = true;
          try {
            if (_text.text != combined) _text.text = combined;
          } finally {
            _syncingExternal = false;
          }
        }
      }
      if (prevVal != _value || prevErr != _formatError) {
        _scheduleRefresh(notifyChanged: prevVal != _value);
      }
      return;
    }

    final dRaw = _degCtrl.text.trim();
    final mRaw = _minCtrl.text.trim();
    final sRaw = _secCtrl.text.trim();

    if ((dRaw.isEmpty || dRaw == '-') && mRaw.isEmpty && sRaw.isEmpty) {
      _value = null;
      _formatError = null;
      _syncingExternal = true;
      try {
        if (_text.text.isNotEmpty) _text.text = '';
      } finally {
        _syncingExternal = false;
      }
    } else {
      final neg = dRaw.startsWith('-');
      final dDigits = neg ? dRaw.substring(1).trim() : dRaw;
      final d = dDigits.isEmpty ? 0 : int.tryParse(dDigits);
      final m = mRaw.isEmpty ? 0 : int.tryParse(mRaw);
      final s = (sRaw.isEmpty || sRaw == '.') ? 0.0 : double.tryParse(sRaw);

      if (d == null || m == null || s == null || !s.isFinite) {
        _value = null;
        _formatError = '请输入有效度分秒数字';
      } else if (m >= 60 || s >= 60) {
        _value = null;
        _formatError = '分和秒须小于 60';
        _syncingExternal = true;
        try {
          if (_text.text.isNotEmpty) _text.text = '';
        } finally {
          _syncingExternal = false;
        }
      } else {
        final val = (neg ? -1.0 : 1.0) * (d + m / 60.0 + s / 3600.0);
        _value = val;
        _formatError = null;
        final compact = fmtDmsCompact(val, secDigits: widget.secDigits);
        _syncingExternal = true;
        try {
          if (_text.text != compact) _text.text = compact;
        } finally {
          _syncingExternal = false;
        }
      }
    }

    if (prevVal != _value || prevErr != _formatError) {
      _scheduleRefresh(notifyChanged: prevVal != _value);
    }
  }

  void _scheduleRefresh({required bool notifyChanged}) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {});
        if (notifyChanged) widget.onChanged?.call(_value);
      });
    } else {
      if (mounted) setState(() {});
      if (notifyChanged) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onChanged?.call(_value);
        });
      }
    }
  }

  /// 输入框下方的实时解读：在度分秒与十进制间给出双向提示。
  String? _describe() {
    final v = _value;
    final parts = <String>[
      if (widget.helper != null && widget.helper!.isNotEmpty) widget.helper!,
      if (v != null)
        _decimal
            ? '= ${fmtAngle(v, secDigits: widget.secDigits)} (${fmtDmsCompact(v, secDigits: widget.secDigits)})'
            : '= ${fmtAngle(v, secDigits: widget.secDigits)}'
      else if (_decimal)
        '按 整数.小数 填写，空格或小数点自动跳格'
      else
        '按 度/分/秒 填写，空格或小数点自动跳格',
      if (v != null && _anyFocused) '空格或小数点跳格',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _buildSegmentCell({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required String unit,
    required int flex,
    required List<TextInputFormatter> inputFormatters,
    TextInputAction textInputAction = TextInputAction.next,
    TextAlign textAlign = TextAlign.right,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: widget.enabled,
                keyboardType: TextInputType.text,
                autocorrect: false,
                enableSuggestions: false,
                textAlign: textAlign,
                textInputAction: textInputAction,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: widget.enabled
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
                  fontFamily: kSurveyMono,
                  fontFamilyFallback: const ['Noto Sans SC'],
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                inputFormatters: inputFormatters,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                  ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 11,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Text(
              unit,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedContainer(BuildContext context, List<Widget> cells) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final fillColor = Theme.of(context).inputDecorationTheme.fillColor ??
        (isDark ? IosColors.darkTertiary : IosColors.lightFill);
    final borderColor = _formatError != null
        ? scheme.error
        : _anyFocused
            ? scheme.primary
            : scheme.outlineVariant;
    final borderWidth = (_formatError != null || _anyFocused) ? 1.5 : 0.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color:
                widget.enabled ? fillColor : fillColor.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(Radii.field),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: cells),
        ),
        if (_formatError != null) ...[
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              _formatError!,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: scheme.error,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDmsGroupedInput(BuildContext context) {
    final hairlineColor = Theme.of(context).colorScheme.outlineVariant;
    return _buildGroupedContainer(context, [
      _buildSegmentCell(
        controller: _degCtrl,
        focusNode: _degFocus,
        hint: '度',
        unit: '°',
        flex: 11,
        inputFormatters: [
          _DmsCellFormatter(
            part: _DmsPart.degree,
            onAdvance: () => _advanceTo(_minFocus, _minCtrl),
            onFullPaste: (raw) => _applyFullAnglePaste(_DmsPart.degree, raw),
          ),
        ],
      ),
      Container(width: 0.5, height: 22, color: hairlineColor),
      _buildSegmentCell(
        controller: _minCtrl,
        focusNode: _minFocus,
        hint: '分',
        unit: '′',
        flex: 9,
        inputFormatters: [
          _DmsCellFormatter(
            part: _DmsPart.minute,
            onAdvance: () => _advanceTo(_secFocus, _secCtrl),
            onFullPaste: (raw) => _applyFullAnglePaste(_DmsPart.minute, raw),
          ),
        ],
      ),
      Container(width: 0.5, height: 22, color: hairlineColor),
      _buildSegmentCell(
        controller: _secCtrl,
        focusNode: _secFocus,
        hint: '秒',
        unit: '″',
        flex: 12,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          _DmsCellFormatter(
            part: _DmsPart.second,
            onAdvance: _advanceToNextField,
            onFullPaste: (raw) => _applyFullAnglePaste(_DmsPart.second, raw),
          ),
        ],
      ),
    ]);
  }

  Widget _buildDecimalGroupedInput(BuildContext context) {
    final hairlineColor = Theme.of(context).colorScheme.outlineVariant;
    return _buildGroupedContainer(context, [
      _buildSegmentCell(
        controller: _decIntCtrl,
        focusNode: _decIntFocus,
        hint: '整数',
        unit: '.',
        flex: 10,
        inputFormatters: [
          _DecCellFormatter(
            part: _DecPart.integer,
            onAdvance: () => _advanceTo(_decFracFocus, _decFracCtrl),
            onFullPaste: (raw) => _applyFullDecimalPaste(_DecPart.integer, raw),
          ),
        ],
      ),
      Container(width: 0.5, height: 22, color: hairlineColor),
      _buildSegmentCell(
        controller: _decFracCtrl,
        focusNode: _decFracFocus,
        hint: '小数',
        unit: '°',
        flex: 13,
        textAlign: TextAlign.left,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          _DecCellFormatter(
            part: _DecPart.fraction,
            onAdvance: _advanceToNextField,
            onFullPaste: (raw) =>
                _applyFullDecimalPaste(_DecPart.fraction, raw),
          ),
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return FieldShell(
      label: widget.label,
      helper: _formatError != null ? null : _describe(),
      trailing: _InlineBadge(
        label: _decimal ? '十进制' : '度分秒',
        accent: _anyFocused,
      ),
      child: _decimal
          ? _buildDecimalGroupedInput(context)
          : _buildDmsGroupedInput(context),
    );
  }
}

class _InlineBadge extends StatelessWidget {
  const _InlineBadge({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent
            ? scheme.primary.withValues(alpha: isDark ? 0.24 : 0.12)
            : (isDark ? IosColors.darkQuaternary : IosColors.lightTertiary)
                .withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        context.tr(label),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: accent ? scheme.primary : scheme.onSurfaceVariant,
          fontFamily: kSurveyMono,
          fontFamilyFallback: const ['Noto Sans SC'],
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// 输入卡片：可选步骤编号/图标 + 标题 + 字段组 + 底部动作。
class InputCard extends StatelessWidget {
  const InputCard({
    super.key,
    this.title,
    this.caption,
    required this.fields,
    this.action,
    this.trailing,
    this.step,
    this.icon,
  });

  final String? title;
  final String? caption;

  /// 卡片内的字段（按顺序纵向排列，自动插入间距）。
  final List<Widget> fields;
  final Widget? action;
  final Widget? trailing;

  /// 步骤序号（如 1、2、3），显示在标题前以增强计算流程感。
  final int? step;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < fields.length; i++) {
      if (i > 0) rows.add(const SizedBox(height: Insets.m));
      rows.add(fields[i]);
    }
    return SurfaceCard(
      padding: const EdgeInsets.all(Insets.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: EdgeInsets.only(
                bottom: (step != null || icon != null) ? Insets.s : Insets.m,
              ),
              child: Row(
                children: [
                  if (step != null) ...[
                    Container(
                      width: 21,
                      height: 21,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$step',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimary,
                          fontFamily: kSurveyMono,
                          fontFamilyFallback: const ['Noto Sans SC'],
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (icon != null) ...[
                    Icon(icon, size: 17, color: scheme.primary),
                    const SizedBox(width: 7),
                  ],
                  Expanded(
                    child: Text(
                      context.tr(title!),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
            if (step != null || icon != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Insets.m),
                child: Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
          ],
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.m),
              child: Text(
                context.tr(caption!),
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ...rows,
          if (action != null) ...[
            const SizedBox(height: Insets.l),
            action!,
          ],
        ],
      ),
    );
  }
}
