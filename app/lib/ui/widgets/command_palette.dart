import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:survey_core/survey_core.dart';

import '../../l10n/survey_strings.dart';
import '../../nav/tools.dart';
import '../../theme/tokens.dart';
import '../pages/tools_page.dart' show FormulaDetailPage;
import '../tool_router.dart';
import 'outline_symbol.dart';

/// 弹出全局快捷命令面板（工具与公式模糊搜索、`↑/↓` 选择、`Enter` 跳转）。
Future<void> showCommandPalette(BuildContext context,
    {String initialQuery = ''}) {
  final workspace = Navigator.of(context);
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) =>
        _CommandPaletteDialog(initialQuery: initialQuery, workspace: workspace),
  );
}

class _PaletteEntry {
  const _PaletteEntry.tool(this.tool) : formula = null;
  const _PaletteEntry.formula(this.formula) : tool = null;

  final ToolDef? tool;
  final FormulaDef? formula;

  String get title => tool?.title ?? formula!.name;
  String get subtitle =>
      tool?.subtitle ?? '${formula!.category} · ${formula!.expression}';
  IconData get icon => tool?.icon ?? Icons.functions;
  String get badge => tool?.group.label ?? '公式';
}

class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog(
      {required this.initialQuery, required this.workspace});
  final String initialQuery;
  final NavigatorState workspace;

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  late final TextEditingController _query =
      TextEditingController(text: widget.initialQuery);
  final FocusNode _inputFocus = FocusNode();
  int _selected = 0;

  @override
  void dispose() {
    _query.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  List<_PaletteEntry> get _matches {
    final q = _query.text.trim().toLowerCase();
    final strings = SurveyStrings.of(context);
    final tools = searchTools(q, strings: strings).map(_PaletteEntry.tool);
    final formulas = q.isEmpty
        ? kFormulaLibrary.take(4).map(_PaletteEntry.formula)
        : kFormulaLibrary
            .where(
              (f) =>
                  strings.translate(f.name).toLowerCase().contains(q) ||
                  f.name.toLowerCase().contains(q) ||
                  strings.translate(f.category).toLowerCase().contains(q) ||
                  f.category.toLowerCase().contains(q) ||
                  (f.description != null &&
                      (strings
                              .translate(f.description!)
                              .toLowerCase()
                              .contains(q) ||
                          f.description!.toLowerCase().contains(q))) ||
                  f.expression.toLowerCase().contains(q),
            )
            .map(_PaletteEntry.formula);
    return [...tools, ...formulas].take(12).toList(growable: false);
  }

  void _activate(_PaletteEntry entry) {
    Navigator.of(context).pop();
    final nav = widget.workspace;
    if (!nav.mounted) return;
    if (entry.tool != null) {
      openTool(nav.context, entry.tool!);
    } else if (entry.formula != null) {
      openWorkspacePage(
        nav.context,
        name: 'tool/formula/detail',
        argument: entry.formula!.id,
        builder: (_) => FormulaDetailPage(formula: entry.formula!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _matches;
    final activeIdx = items.isEmpty ? 0 : _selected.clamp(0, items.length - 1);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () {
              if (items.isNotEmpty) {
                setState(() => _selected = (activeIdx + 1) % items.length);
              }
            },
            const SingleActivator(LogicalKeyboardKey.arrowUp): () {
              if (items.isNotEmpty) {
                setState(
                  () =>
                      _selected = (activeIdx - 1 + items.length) % items.length,
                );
              }
            },
            const SingleActivator(LogicalKeyboardKey.enter): () {
              if (items.isNotEmpty) _activate(items[activeIdx]);
            },
            const SingleActivator(LogicalKeyboardKey.escape): () {
              Navigator.of(context).pop();
            },
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.l,
                  Insets.m,
                  Insets.m,
                  Insets.s,
                ),
                child: Row(
                  children: [
                    OutlineSymbol(Icons.search,
                        size: 20, color: scheme.primary),
                    const SizedBox(width: Insets.s),
                    Expanded(
                      child: TextField(
                        controller: _query,
                        focusNode: _inputFocus,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: context.tr('搜索测量工具或公式（如：导线、交会、水准、圆曲线）'),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onChanged: (_) => setState(() => _selected = 0),
                        onSubmitted: (_) {
                          if (items.isNotEmpty) _activate(items[activeIdx]);
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('关闭 (Esc)'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 0.5,
                thickness: 0.5,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Insets.xxl),
                  child: LocalText(
                    '没有匹配的工具或公式',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(Insets.s),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final entry = items[i];
                      final active = i == activeIdx;
                      return InkWell(
                        borderRadius: BorderRadius.circular(Radii.field),
                        onTap: () => _activate(entry),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Insets.m,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? scheme.primary.withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(Radii.field),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                entry.icon,
                                size: 18,
                                color: active
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: Insets.m),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.tr(entry.title),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: active
                                            ? scheme.primary
                                            : scheme.onSurface,
                                      ),
                                    ),
                                    Text(
                                      entry.tool != null
                                          ? context.tr(entry.subtitle)
                                          : '${context.tr(entry.formula!.category)} · ${entry.formula!.expression}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: Insets.s),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest
                                      .withValues(alpha: 0.6),
                                  borderRadius:
                                      BorderRadius.circular(Radii.pill),
                                ),
                                child: Text(
                                  context.tr(entry.badge),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
