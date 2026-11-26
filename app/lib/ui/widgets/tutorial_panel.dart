import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../content/tutorials.dart';
import '../../l10n/survey_strings.dart';
import '../../theme/tokens.dart';
import 'foundation.dart';
import 'overlays.dart';
import 'workspace_commands.dart';

/// 计算页内置教程卡：折叠态只占一行，展开给「公式 / 步骤 / 算例 / 注意」。
///
/// 放在页面的 children 最前面（工具条之下），例如：
/// ```dart
/// DetailScaffold(children: [PageTutorial(id: 'inverse'), ...])
/// ```
/// 内容来自 `lib/content/tutorials.dart`，页面不需要自己写文案。
class PageTutorial extends StatefulWidget {
  const PageTutorial({
    super.key,
    required this.id,
    this.initiallyExpanded = false,
    this.workedSteps,
    this.liveCalcBuilder,
    this.onLoadSample,
  });

  final String id;
  final bool initiallyExpanded;
  final List<String>? workedSteps;
  final List<String> Function(BuildContext context)? liveCalcBuilder;
  final VoidCallback? onLoadSample;

  Future<void> openGuide(BuildContext context) => workspacePanel<void>(
        context,
        context.tr('离线教程'),
        PageTutorial(
          id: id,
          initiallyExpanded: true,
          workedSteps: workedSteps,
          liveCalcBuilder: liveCalcBuilder,
          onLoadSample: onLoadSample,
        ),
        desktopDrawer: true,
      );

  @override
  State<PageTutorial> createState() => _PageTutorialState();
}

class _PageTutorialState extends State<PageTutorial> {
  late bool _open = widget.initiallyExpanded;

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    SurveyToast.success(context, '公式已复制');
  }

  @override
  Widget build(BuildContext context) {
    final strings = SurveyStrings.of(context);
    final t = tutorialFor(widget.id, languageCode: strings.languageCode);
    if (t == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.m,
                vertical: Insets.s + 2,
              ),
              child: Row(
                children: [
                  Icon(Icons.menu_book_outlined,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  // 折叠态只放标题（可收缩、可省略号）——曾经把 summary 也塞进这一行，
                  // 结果每页在 320dp / 1.3 倍字体下溢出 30~230px（23 条版式用例一起红）。
                  Expanded(
                    child: Text(
                      strings.translate('教程 · {tool}', {'tool': t.title}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (!widget.initiallyExpanded && widget.id != 'leveling4')
                    IconButton(
                      tooltip: context.tr('打开离线教程'),
                      onPressed: () => widget.openGuide(context),
                      icon: const Icon(Icons.help_outline, size: 17),
                    ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.m,
                0,
                Insets.m,
                Insets.m,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr(t.summary),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (t.formulas.isNotEmpty) ...[
                    const SizedBox(height: Insets.m),
                    _label(context, context.tr('公式')),
                    const SizedBox(height: 6),
                    for (final f in t.formulas)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: InkWell(
                          onLongPress: () => _copy(context.tr(f)),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: Insets.s,
                              vertical: 7,
                            ),
                            color: scheme.surfaceContainerHigh,
                            child: SelectableText(
                              context.tr(f),
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                fontFamily: kSurveyMono,
                                fontFamilyFallback: const [
                                  'Noto Sans SC',
                                  'monospace',
                                ],
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Text(
                      context.tr('长按公式可复制'),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if ((widget.liveCalcBuilder?.call(context) ??
                          widget.workedSteps)
                      case final steps?) ...[
                    const SizedBox(height: Insets.m),
                    _label(context, context.tr('代入当前数据')),
                    const SizedBox(height: 6),
                    if (steps.isEmpty)
                      const LocalText('完成录入后显示代入步骤')
                    else
                      for (final step in steps)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: SelectableText(context.tr(step),
                              style: monoNumber(context,
                                  size: 12, weight: FontWeight.w400)),
                        ),
                  ],
                  if (t.steps.isNotEmpty) ...[
                    const SizedBox(height: Insets.m),
                    _label(context, context.tr('怎么用')),
                    const SizedBox(height: 4),
                    for (var i = 0; i < t.steps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${i + 1}.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                context.tr(t.steps[i]),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.55,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  if (t.example.isNotEmpty) ...[
                    const SizedBox(height: Insets.m),
                    Row(
                      children: [
                        Expanded(child: _label(context, context.tr('算例'))),
                        if (widget.onLoadSample != null)
                          TextButton.icon(
                            onPressed: widget.onLoadSample,
                            icon: const Icon(Icons.science_outlined, size: 15),
                            label: Text(context.tr('载入算例')),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    for (final e in t.example)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: 78,
                                maxWidth: 128,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  context.tr(e.$1),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                context.tr(e.$2),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.5,
                                  color: scheme.onSurface,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  if (t.notes.isNotEmpty) ...[
                    const SizedBox(height: Insets.m),
                    _label(context, context.tr('注意')),
                    const SizedBox(height: 4),
                    for (final n in t.notes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6, right: 6),
                              child: Container(
                                width: 4,
                                height: 4,
                                color: scheme.tertiary,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                context.tr(n),
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.55,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Row(
        children: [
          Container(
            width: 10,
            height: 2,
            color: Theme.of(context).colorScheme.tertiary,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      );
}
