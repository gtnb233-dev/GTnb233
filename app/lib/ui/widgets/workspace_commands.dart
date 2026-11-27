import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../l10n/survey_strings.dart';
import '../../nav/tools.dart';
import '../../platform/native_bridge_contract.dart';
import '../../state/drafts.dart';
import '../../state/live_plot_controller.dart';
import '../../state/settings.dart';
import '../../theme/tokens.dart';
import '../../theme/workspace_layout.dart';
import '../tool_router.dart';
import '../pages/tools/tin_workspace.dart';
import 'command_palette.dart';
import 'liquid_glass.dart';
import 'live_plot.dart';
import 'outline_symbol.dart';
import 'overlays.dart';
import 'workspace_points.dart';

export 'workspace_points.dart' show WorkspaceLivePlotPanel;

String draftTitle(BuildContext context, DraftStore? store, String id) =>
    store?.value(id, '_title') ??
    context.tr(id == 'intersection/resection'
        ? '三点后方交会'
        : toolById(id.split('/').first)?.title ?? '草稿');

Future<void> openWorkspaceDraft(BuildContext context, String id,
    {bool fromSidebar = false}) async {
  final tool = toolById(id.split('/').first);
  if (tool != null) {
    await openTool(context, tool, draftId: id, fromSidebar: fromSidebar);
  }
}

final _workspaceSheets = Expando<ValueNotifier<bool>>();

class WorkspacePanelBackground extends StatelessWidget {
  const WorkspacePanelBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final canAnimate = !MediaQuery.disableAnimationsOf(context);
    final ValueListenable<bool> visible = route == null
        ? const AlwaysStoppedAnimation(false)
        : _workspaceSheets[route] ??= ValueNotifier(false);
    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      child: child,
      builder: (context, open, child) => AnimatedScale(
        scale: canAnimate && open ? .94 : 1,
        alignment: Alignment.topCenter,
        duration: Motion.base,
        curve: Motion.ease,
        child: child,
      ),
    );
  }
}

Future<T?> _withWorkspaceDepth<T>(
  BuildContext context,
  Future<T?> Function() show,
) async {
  final route = ModalRoute.of(context);
  final visible = route == null ? null : _workspaceSheets[route];
  visible?.value = true;
  try {
    return await show();
  } finally {
    visible?.value = false;
  }
}

Future<T?> showWorkspaceBottomSheet<T>(
  BuildContext context,
  WidgetBuilder builder,
) =>
    _withWorkspaceDepth<T>(
        context,
        () => showModalBottomSheet<T>(
              context: context,
              useRootNavigator: true,
              useSafeArea: true,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) {
                final animation = ModalRoute.of(context)?.animation;
                if (animation == null) return builder(context);
                return AnimatedBuilder(
                  animation: animation,
                  child: builder(context),
                  builder: (context, child) => GlassBlurSuspensionScope(
                    suspended: !animation.isCompleted,
                    child: child!,
                  ),
                );
              },
            ));

Future<T?> workspacePanel<T>(BuildContext context, String title, Widget content,
    {bool useBottomSheet = false}) async {
  Widget panel(BuildContext context) {
    final settings = SettingsScope.of(context);
    return LiquidGlassSurface(
      borderRadius: BorderRadius.circular(Radii.sheet),
      blurSigma: settings.floatingGlassNav ? 18 : 0,
      elevated: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * .78,
        ),
        child: SingleChildScrollView(
          primary: false,
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                      child: LocalText(title,
                          style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(
                    tooltip: context.tr('关闭'),
                    icon: const OutlineSymbol(Icons.close),
                    onPressed: () {
                      if (ModalRoute.of(context)?.isCurrent ?? false) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              content,
            ],
          ),
        ),
      ),
    );
  }

  if (useBottomSheet || workspaceUsesCompactLayout(context)) {
    return showWorkspaceBottomSheet<T>(context, panel);
  }
  return showDialog<T>(
    context: context,
    builder: (context) =>
        Dialog(backgroundColor: Colors.transparent, child: panel(context)),
  );
}

Future<void> showWorkspaceCreate(BuildContext context) async {
  final choice = await workspacePanel<String>(
      context,
      '新建草稿',
      Builder(
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const OutlineSymbol(Icons.add),
              title: const LocalText('新建四等水准路线'),
              onTap: () => Navigator.pop(context, 'level'),
            ),
            ListTile(
              leading: const OutlineSymbol(Icons.file_upload_outlined),
              title: const LocalText('导入 DXF / CSV'),
              onTap: () => Navigator.pop(context, 'import'),
            ),
          ],
        ),
      ));
  if (!context.mounted || choice == null) return;
  if (choice == 'import') {
    await _importPoints(context);
    return;
  }
  String name = '';
  final title = await workspacePanel<String>(
      context,
      '新建四等水准路线',
      Builder(
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(labelText: context.tr('路线名称')),
              onChanged: (text) => name = text.trim(),
              onSubmitted: (text) => Navigator.pop(context, text.trim()),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context, name),
              child: const LocalText('创建'),
            ),
          ],
        ),
      ));
  if (!context.mounted || title == null) return;
  final store = DraftScope.read(context);
  final id = await store
      .createLevelRoute(title.isEmpty ? context.tr('水准路线草稿') : title);
  if (context.mounted) await openWorkspaceDraft(context, id);
}

Future<void> showDraftHistory(BuildContext context) async {
  final store = DraftScope.read(context);
  final active = SettingsScope.read(context).lastDraftId;
  var filter = '';
  final id = await workspacePanel<String>(context, '全部工程与草稿', StatefulBuilder(
    builder: (context, setState) {
      final ids = store.recentIds
          .where((id) =>
              draftTitle(context, store, id).toLowerCase().contains(filter))
          .toList();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: context.tr('筛选草稿')),
            onChanged: (value) =>
                setState(() => filter = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 8),
          if (ids.isEmpty)
            const Padding(
                padding: EdgeInsets.all(12), child: LocalText('暂无草稿')),
          for (final id in ids)
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              selected: id == active,
              leading: const OutlineSymbol(Icons.description_outlined),
              title: Text(draftTitle(context, store, id)),
              onTap: () => Navigator.pop(context, id),
            ),
        ],
      );
    },
  ));
  if (context.mounted && id != null) await openWorkspaceDraft(context, id);
}

Future<void> _importPoints(BuildContext context) async {
  try {
    final doc = await NativeFilesBridge.pickDocument(
      extensions: const ['dxf', 'csv', 'dat', 'txt'],
    );
    if (doc == null || !context.mounted) return;
    final lowerName = doc.name.toLowerCase();
    final isDxf = lowerName.endsWith('.dxf');
    final sourceLabel = isDxf
        ? 'DXF'
        : (lowerName.endsWith('.dat')
            ? 'DAT'
            : (lowerName.endsWith('.txt') ? 'TXT' : 'CSV'));
    final points = decodeWorkspacePoints(doc.text, isDxf);
    if (!context.mounted) return;
    final store = DraftScope.read(context);
    final existing = readWorkspacePoints(store);
    if (isDxf) {
      final unique = <String, PlotPoint>{};
      var index = 1;
      for (final point in points.values) {
        while (existing.containsKey('DXF-$index')) {
          index++;
        }
        final id = 'DXF-${index++}';
        unique[id] =
            PlotPoint(x: point.x, y: point.y, label: id, draggable: false);
      }
      points
        ..clear()
        ..addAll(unique);
    }
    if (points.keys.any(existing.containsKey)) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const LocalText('发现同名点号'),
          content: const LocalText('覆盖本地坐标，或保留同名点原有记录。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const LocalText('取消')),
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const LocalText('保留原记录')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const LocalText('覆盖')),
          ],
        ),
      );
      if (!context.mounted || overwrite == null) return;
      if (!overwrite) points.removeWhere((id, _) => existing.containsKey(id));
    }
    store.putAll(workspacePointsKey, {
      for (final p in points.values) p.label: '${p.x},${p.y}',
    });
    await store.flushPage(workspacePointsKey);
    if (context.mounted) {
      LivePlotScope.maybeRead(context)?.updateSnapshot(
        LivePlotSnapshot(
          title: context.tr('导入点位'),
          sourceToolId: 'import',
          sourceLabel: sourceLabel,
          sourceKind: LivePlotSourceKind.importedFile,
          points: [
            for (final p in points.values)
              LivePlotPointData(
                x: p.x,
                y: p.y,
                label: p.label,
                draggable: false,
              ),
          ],
          surveyNorthUp: true,
          unit: 'm',
        ),
        sourceKind: LivePlotSourceKind.importedFile,
      );
      SurveyToast.success(
        context,
        context.tr('已导入 {count} 个点', {'count': points.length}),
      );
      await showWorkspacePlot(context);
    }
  } on Exception {
    if (context.mounted) {
      SurveyToast.show(
        context,
        '无法导入，请检查 DXF / CSV / DAT / TXT 文件格式',
        tone: ToastTone.warning,
      );
    }
  }
}

Future<void> showWorkspacePlot(BuildContext context,
    {String? selected, (double, double)? coordinate}) {
  final controller = LivePlotScope.of(context);
  if (controller.current == null || controller.current!.isEmpty) {
    controller.loadLatestAvailable(
        preferredKind: LivePlotSourceKind.activeDraft);
  }
  return workspacePanel<void>(
    context,
    '实时坐标图',
    WorkspaceLivePlotPanel(selectedLabel: selected, coordinate: coordinate),
  );
}

class WorkspaceCommandsEnabled extends InheritedWidget {
  const WorkspaceCommandsEnabled({super.key, required super.child});
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceCommandsEnabled>() !=
      null;
  @override
  bool updateShouldNotify(WorkspaceCommandsEnabled oldWidget) => false;
}

class QuickCommandBar extends StatefulWidget {
  const QuickCommandBar({super.key, this.secondary = false});

  final bool secondary;
  static const double reserve = 132;

  static double bottomClearance(BuildContext context) =>
      reserve + 24 + MediaQuery.viewPaddingOf(context).bottom;

  @override
  State<QuickCommandBar> createState() => _QuickCommandBarState();
}

class _QuickCommandBarState extends State<QuickCommandBar> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      await showCommandPalette(context);
      return;
    }
    final points = readWorkspacePoints(DraftScope.maybeRead(context));
    if (points.containsKey(text)) {
      FocusScope.of(context).unfocus();
      await showWorkspacePlot(context, selected: text);
      return;
    }
    final coordinate = parseWorkspaceCoordinates(text);
    if (coordinate != null) {
      FocusScope.of(context).unfocus();
      await showWorkspacePlot(context, coordinate: coordinate);
      return;
    }
    if (text.toLowerCase() == 'tin') {
      await openWorkspacePage(context,
          name: 'tool/earthwork/tin', builder: (_) => const TinWorkspacePage());
      return;
    }
    final matches = searchTools(text, strings: SurveyStrings.of(context));
    if (matches.length == 1) {
      FocusScope.of(context).unfocus();
      await openTool(context, matches.single);
      return;
    }
    if (matches.isEmpty) {
      try {
        final expression =
            text.startsWith('=') ? text.substring(1).trim() : text;
        if (expression.isEmpty) throw FormulaException('无有效算式');
        final answer = ExpressionEvaluator.evaluate(expression);
        FocusScope.of(context).unfocus();
        await workspacePanel<void>(
            context,
            '快速计算',
            SelectableText(answer.toString(),
                style: monoNumber(context, size: 28)));
        return;
      } on FormulaException {
        if (!mounted) return;
        if (text.startsWith('=') || RegExp(r'^[0-9+\-(]').hasMatch(text)) {
          SurveyToast.show(context, '无有效算式', tone: ToastTone.warning);
          return;
        }
      }
    }
    if (mounted) await showCommandPalette(context, initialQuery: text);
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 480;
      final bar = SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: LiquidGlassSurface(
              key: const ValueKey('workspace-command-dock'),
              borderRadius: BorderRadius.circular(24),
              blurSigma: settings.floatingGlassNav ? 18 : 0,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const ValueKey('workspace-command-input'),
                    controller: _input,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _run(),
                    decoration: InputDecoration(
                      isDense: false,
                      hintText:
                          context.tr(narrow ? '搜工具、点号或算式' : '搜索工具、输入点号、坐标或算式'),
                      prefixIcon: const Center(
                          widthFactor: 1,
                          heightFactor: 1,
                          child: OutlineSymbol(Icons.search, size: 18)),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: context.tr('新建草稿'),
                        onPressed: () => showWorkspaceCreate(context),
                        icon: const OutlineSymbol(Icons.add),
                      ),
                      if (narrow) ...[
                        IconButton(
                          tooltip: context.tr('四等水准'),
                          onPressed: () =>
                              openTool(context, toolById('leveling4')!),
                          icon: const OutlineSymbol(Icons.rule),
                        ),
                        IconButton(
                          tooltip: 'LivePlot',
                          onPressed: () => showWorkspacePlot(context),
                          icon: const OutlineSymbol(Icons.polyline_outlined),
                        ),
                      ] else ...[
                        TextButton(
                            onPressed: () =>
                                openTool(context, toolById('leveling4')!),
                            child: const LocalText('四等水准')),
                        TextButton(
                            onPressed: () => showWorkspacePlot(context),
                            child: const Text('LivePlot')),
                      ],
                      const Spacer(),
                      PopupMenuButton<AngleInputMode>(
                        tooltip: context.tr('角度输入格式'),
                        onSelected: settings.setAngleMode,
                        itemBuilder: (_) => [
                          for (final mode in AngleInputMode.values)
                            PopupMenuItem(
                                value: mode, child: Text(mode.symbol)),
                        ],
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(minWidth: 48, minHeight: 48),
                          child: Center(child: Text(settings.angleMode.symbol)),
                        ),
                      ),
                      if (widget.secondary)
                        IconButton(
                          tooltip: context.tr('执行'),
                          onPressed: _run,
                          icon: const OutlineSymbol(Icons.arrow_upward),
                        )
                      else
                        IconButton.filled(
                          tooltip: context.tr('执行'),
                          onPressed: _run,
                          icon: const OutlineSymbol(Icons.arrow_upward),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return Stack(
        children: [
          Positioned.fill(
            child: ScrollEdgeFade(
                color: Theme.of(context).scaffoldBackgroundColor),
          ),
          bar,
        ],
      );
    });
  }
}
