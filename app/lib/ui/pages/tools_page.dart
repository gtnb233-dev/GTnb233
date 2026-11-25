import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../l10n/survey_strings.dart';
import '../../nav/tools.dart';
import '../../state/settings.dart';
import '../../theme/tokens.dart';
import '../page_scaffold.dart';
import '../tool_router.dart';
import '../widgets/tutorial_panel.dart';
import '../widgets/widgets.dart';

/// 工具库：搜索 + 分类浏览全部工具。
class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  final _search = TextEditingController();
  String _query = '';

  /// 手风琴：可同时展开多个分类，默认全部收起。
  final Set<ToolGroup> _expanded = <ToolGroup>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(ToolGroup group) {
    setState(() {
      if (!_expanded.remove(group)) _expanded.add(group);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final matched = searchTools(_query, strings: SurveyStrings.of(context));
    final searching = _query.trim().isNotEmpty;

    // 搜索时只保留命中组，且自动展开；清空搜索回到手风琴常态。
    final grouped = <ToolGroup, List<ToolDef>>{};
    for (final t in matched) {
      grouped.putIfAbsent(t.group, () => <ToolDef>[]).add(t);
    }
    return PageScaffold(
      title: '工具库',
      caption: context.tr('{count} 个测量工具，按分类浏览', {'count': kTools.length}),
      children: [
        TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: context.tr('搜索工具，如「导线」「曲线」「面积」'),
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
        const SizedBox(height: Insets.l),
        SectionHeader(
          title: '分类总览',
          caption: searching
              ? context.tr('搜索命中 {count} 个工具', {'count': matched.length})
              : context.tr('{count} 个工具 · {groups} 个分类，点分类就地展开', {'count': kTools.length, 'groups': ToolGroup.values.length}),
          trailing: searching
              ? null
              : TextButton(
                  onPressed: () {
                    setState(() {
                      if (_expanded.length == ToolGroup.values.length) {
                        _expanded.clear();
                      } else {
                        _expanded.addAll(ToolGroup.values);
                      }
                    });
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    context.tr(_expanded.length == ToolGroup.values.length
                        ? '全部收起'
                        : '全部展开'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
        ),
        const SizedBox(height: Insets.s),
        if (searching && matched.isEmpty)
          const EmptyHint(
            message: '没有匹配的工具',
            icon: Icons.search_off,
            hint: '试试「坐标」「水准」「土方」等关键词',
          )
        else
          for (final group in ToolGroup.values)
            if (!searching || grouped[group] != null) ...[
              _GroupCard(
                group: group,
                tools: searching ? grouped[group]! : toolsOf(group),
                expanded: searching || _expanded.contains(group),
                // 搜索时不允许手动收起（结果就是命中的那几行）
                onToggle: searching ? null : () => _toggle(group),
              ),
              const SizedBox(height: Insets.s),
            ],
        if (!searching && _expanded.isNotEmpty)
          Center(
            child: LocalText(
              '点击分类卡片可展开/收起',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// 手风琴式分类卡片：点标题就地展开，工具行紧贴卡片下方、缩进对齐标题。
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.tools,
    required this.expanded,
    this.onToggle,
  });

  final ToolGroup group;

  /// 要展示的工具行（搜索时是命中的那几行）。
  final List<ToolDef> tools;
  final bool expanded;

  /// 为 null 表示不可折叠（搜索命中态）。
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      key: ValueKey<String>('toolbox-group-${group.name}'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(Radii.card),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.l,
                Insets.m,
                Insets.m,
                Insets.m,
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(group.icon, size: 19, color: scheme.primary),
                  ),
                  const SizedBox(width: Insets.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(group.label),
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tools.map((t) => context.tr(t.title)).take(3).join(' · '),
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
                  Pill(label: '${tools.length}', tone: PillTone.neutral),
                  const SizedBox(width: 2),
                  // 展开时箭头转 90°。
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Column(
                    key: ValueKey<String>('toolbox-group-body-${group.name}'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                      for (var i = 0; i < tools.length; i++) ...[
                        _ToolRow(tool: tools[i]),
                        if (i != tools.length - 1)
                          Padding(
                            padding: const EdgeInsets.only(left: 56),
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color:
                                  scheme.outlineVariant.withValues(alpha: 0.3),
                            ),
                          ),
                      ],
                      const SizedBox(height: Insets.xs),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// 展开后的一个工具行：图标 + 名称 + 副标题 + 右箭头（左内边距 56 对齐标题）。
class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.tool});

  final ToolDef tool;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings =
        context.dependOnInheritedWidgetOfExactType<SettingsScope>()?.notifier;
    final pinned = settings?.isPinned(tool.id) ?? false;
    return InkWell(
      key: ValueKey<String>('toolbox-tool-${tool.id}'),
      onTap: () => openTool(context, tool),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(56, 10, Insets.m, 10),
        child: Row(
          children: [
            Icon(tool.icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: Insets.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr(tool.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    context.tr(tool.subtitle),
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
            if (settings != null)
              IconButton(
                key: ValueKey<String>('toolbox-pin-${tool.id}'),
                tooltip: context.tr(pinned ? '取消首页固定' : '固定到首页常用'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: Icon(
                  pinned ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 17,
                  color: pinned
                      ? scheme.primary
                      : scheme.onSurfaceVariant.withValues(alpha: 0.65),
                ),
                onPressed: () async {
                  final ok = await SettingsScope.read(context)
                      .togglePinnedTool(tool.id);
                  if (!context.mounted) return;
                  if (!ok) {
                    SurveyToast.warning(context, '首页至少保留 1 个常用工具');
                  } else {
                    SurveyToast.info(
                      context,
                      context.tr(
                        pinned ? '已从首页常用移除「{tool}」' : '已固定「{tool}」到首页常用',
                        {'tool': context.tr(tool.title)},
                      ),
                    );
                  }
                },
              ),
            const SizedBox(width: Insets.xs),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// 坐标与放样页：只展示坐标类工具，附计算约定说明。
class CoordPage extends StatelessWidget {
  const CoordPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = SettingsScope.of(context);
    final tools = toolsOf(ToolGroup.coordinates);
    return PageScaffold(
      title: '坐标工具',
      caption: '国内测量坐标系：X 为纵轴（北），Y 为横轴（东），方位角自北顺时针',
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(Insets.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, size: 17, color: scheme.primary),
                  const SizedBox(width: 6),
                  const LocalText(
                    '计算约定',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: Insets.s),
              Text(
                [
                  context.tr('· 方位角 = atan2(ΔY, ΔX)，取值 0°–360°'),
                  context.tr('· 坐标增量 ΔX = D·cosα，ΔY = D·sinα'),
                  context.tr('· 小数位：{digits} 位；角度：{angle}', {
                    'digits': settings.coordDigits,
                    'angle': context.tr(settings.angleMode == AngleInputMode.dmsCompact ? '度分秒输入' : '十进制度输入'),
                  }),
                ].join('\n'),
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Insets.l),
        const SectionHeader(title: '可用工具'),
        const SizedBox(height: Insets.s),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final t in tools)
                ChoiceTile(
                  title: t.title,
                  subtitle: t.subtitle,
                  icon: t.icon,
                  onTap: () => openTool(context, t),
                  dense: true,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 公式计算页：自定义表达式 + 内置公式库。
class FormulaPage extends StatefulWidget {
  const FormulaPage({super.key, this.embedded = false});

  /// true = 作为二级页面（带返回按钮）从工具库打开。
  final bool embedded;

  @override
  State<FormulaPage> createState() => _FormulaPageState();
}

class _FormulaPageState extends State<FormulaPage> {
  final _expr = TextEditingController(text: 'sqrt((x2-x1)^2 + (y2-y1)^2)');
  final _vars = TextEditingController(text: 'x1=1000, y1=2000, x2=1100, y2=2050');
  String? _result;
  String? _error;

  @override
  void dispose() {
    _expr.dispose();
    _vars.dispose();
    super.dispose();
  }

  Map<String, double> _parseVars() {
    final map = <String, double>{};
    for (final part in _vars.text.split(RegExp(r'[,，;；\n]+'))) {
      final t = part.trim();
      if (t.isEmpty) continue;
      final idx = t.indexOf('=');
      if (idx <= 0) continue;
      final key = t.substring(0, idx).trim();
      final value = double.tryParse(t.substring(idx + 1).trim());
      if (value != null) map[key] = value;
    }
    return map;
  }

  void _compute({bool notify = false}) {
    if (!mounted) return;
    final settings = SettingsScope.read(context);
    try {
      final v = ExpressionEvaluator.evaluate(
        _expr.text,
        variables: _parseVars(),
        unit: TrigUnit.degrees,
      );
      setState(() {
        _result = fmt(v, 6);
        _error = null;
      });
      if (notify) {
        SurveyToast.calcSuccess(context, '表达式计算成功');
      }
      // 角度模式不影响表达式求值单位，这里读取一次以保证依赖关系。
      assert(settings.angleMode.index >= 0);
    } on FormulaException catch (e) {
      setState(() {
        _error = e.message;
        _result = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[
        const PageTutorial(id: 'formula'),
        InputCard(
          title: '表达式计算',
          caption: '支持 + − × ÷ ^ 与 sqrt、sin、cos、tan、atan2、abs、ln 等函数；'
              '三角函数按「度」解释，反三角函数返回弧度（用 deg(...) 转度）。',
          fields: [
            TextField(
              controller: _expr,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                labelText: context.tr('表达式'),
                hintText: context.tr('例如 sqrt((x2-x1)^2 + (y2-y1)^2)'),
              ),
              onSubmitted: (_) => _compute(notify: true),
            ),
            TextField(
              controller: _vars,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: context.tr('变量（可选，逗号分隔）'),
                hintText: 'x1=0, y1=0',
              ),
              onSubmitted: (_) => _compute(notify: true),
            ),
            if (_result != null && _error == null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  LocalText(
                    '结果',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  SelectableText(
                    _result!,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            if (_error != null)
              Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.tr(_error!),
                      style: TextStyle(fontSize: 12.5, color: scheme.error),
                    ),
                  ),
                ],
              ),
          ],
          action: PrimaryAction(
            label: '计算',
            icon: Icons.play_arrow_rounded,
            onPressed: () => _compute(notify: true),
          ),
        ),
        const SizedBox(height: Insets.l),
        const SectionHeader(
          title: '内置公式',
          caption: '点开即用，填写参数后实时出结果',
        ),
        const SizedBox(height: Insets.s),
        for (final category in formulaCategories()) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.xs, Insets.s, 0, 4),
            child: Text(
              context.tr(category),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final f in kFormulaLibrary.where((e) => e.category == category))
                  ChoiceTile(
                    title: f.name,
                    subtitle: f.expression,
                    icon: Icons.functions,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FormulaDetailPage(formula: f),
                      ),
                    ),
                    dense: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: Insets.s),
        ],
    ];
    if (widget.embedded) {
      return DetailScaffold(
        title: '公式计算',
        subtitle: '表达式求值 · 内置测量公式',
        children: children,
      );
    }
    return PageScaffold(
      title: '计算',
      caption: '表达式求值 · 内置测量公式',
      children: children,
    );
  }
}

/// 工具库入口：带返回按钮的公式计算页。
class FormulaToolPage extends StatelessWidget {
  const FormulaToolPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const FormulaPage(embedded: true);
}

/// 单个内置公式的填写与实时计算。
class FormulaDetailPage extends StatefulWidget {
  const FormulaDetailPage({super.key, required this.formula});

  final FormulaDef formula;

  @override
  State<FormulaDetailPage> createState() => _FormulaDetailPageState();
}

class _FormulaDetailPageState extends State<FormulaDetailPage> {
  late final Map<String, TextEditingController> _controllers;
  String? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final v in widget.formula.variables)
        v.key: TextEditingController(
          text: v.defaultValue == null ? '' : _trim(v.defaultValue!),
        ),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _compute());
  }

  static String _trim(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e15) {
      return v.toInt().toString();
    }
    return v.toString();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _compute() {

    if (!mounted) return;
    final vars = <String, double>{};
    for (final e in _controllers.entries) {
      final t = e.value.text.trim();
      if (t.isEmpty || t == '-' || t == '.') continue;
      final v = double.tryParse(t);
      if (v != null) vars[e.key] = v;
    }
    try {
      final v = ExpressionEvaluator.evaluate(
        widget.formula.expression,
        variables: vars,
      );
      setState(() {
        _result = fmt(v, widget.formula.resultDigits);
        _error = null;
      });
    } on FormulaException catch (e) {
      setState(() {
        _error = e.message;
        _result = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.formula;
    final scheme = Theme.of(context).colorScheme;
    return DetailScaffold(
      title: f.name,
      subtitle: f.category,
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(Insets.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                f.expression,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: scheme.primary,
                ),
              ),
              if (f.description != null) ...[
                const SizedBox(height: Insets.s),
                Text(
                  context.tr(f.description!),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Insets.l),
        for (final v in f.variables) ...[
          FieldShell(
            label: v.label,
            helper: v.hint,
            child: TextField(
              controller: _controllers[v.key],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              onChanged: (_) => _compute(),
              decoration: InputDecoration(suffixText: v.unit),
            ),
          ),
          const SizedBox(height: Insets.m),
        ],
        const SizedBox(height: Insets.s),
        SurfaceCard(
          tone: CardTone.raised,
          padding: const EdgeInsets.all(Insets.l),
          child: Row(
            children: [
              LocalText(
                '结果',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: Insets.m),
              Expanded(
                child: _error != null
                    ? Text(
                        context.tr(_error!),
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 13, color: scheme.error),
                      )
                    : Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _result ?? '—',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.primary,
                                  letterSpacing: -0.8,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              if (f.resultUnit != null) ...[
                                const SizedBox(width: 4),
                                Text(
                                  f.resultUnit!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
