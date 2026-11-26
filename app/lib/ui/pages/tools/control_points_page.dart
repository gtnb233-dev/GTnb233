import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../export/export_service.dart';
import '../../../l10n/survey_strings.dart';
import '../../../platform/native_bridge_contract.dart';
import '../../../state/control_points.dart';
import '../../../state/live_plot_controller.dart';
import '../../../state/settings.dart';
import '../../../theme/tokens.dart';
import '../../../theme/workspace_layout.dart';
import '../../page_scaffold.dart';
import '../../widgets/outline_symbol.dart';
import '../../widgets/widgets.dart';
import '../../widgets/workspace_commands.dart';

String _l(BuildContext context, String zh, String en) {
  if (SurveyStrings.of(context).languageCode == 'zh') return zh;
  final translated = context.tr(zh);
  return translated == zh ? en : translated;
}

/// Opens a reusable modal/bottom-sheet picker to select a [ControlPoint] in 1 tap.
Future<ControlPoint?> showControlPointPicker(BuildContext context) async {
  final store = ControlPointScope.maybeRead(context);
  if (store != null && !store.loaded) {
    await store.load();
  }
  if (!context.mounted) return null;

  final isNarrow = workspaceUsesCompactLayout(context);
  if (isNarrow) {
    return showWorkspaceBottomSheet<ControlPoint>(
      context,
      (_) => const _ControlPointPickerSheet(isSheet: true),
    );
  }
  return showDialog<ControlPoint>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: const _ControlPointPickerSheet(isSheet: false),
      ),
    ),
  );
}

class _ControlPointPickerSheet extends StatefulWidget {
  const _ControlPointPickerSheet({required this.isSheet});

  final bool isSheet;

  @override
  State<_ControlPointPickerSheet> createState() =>
      _ControlPointPickerSheetState();
}

class _ControlPointPickerSheetState extends State<_ControlPointPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _group;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ControlPointScope.maybeOf(context);
    final settings =
        context.dependOnInheritedWidgetOfExactType<SettingsScope>()?.notifier;
    final digits = settings?.coordDigits ?? 3;
    final scheme = Theme.of(context).colorScheme;
    final allPoints = store?.points ?? const <ControlPoint>[];
    final groups = store?.groups ?? const <String>[];

    final filtered = allPoints.where((p) {
      if (_group != null && p.group != _group) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.group.toLowerCase().contains(q) ||
          p.note.toLowerCase().contains(q);
    }).toList();

    return LiquidGlassSurface(
      borderRadius: BorderRadius.circular(Radii.sheet),
      blurSigma: (settings?.floatingGlassNav ?? false) ? 18 : 0,
      elevated: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            Insets.l,
            Insets.m,
            Insets.l,
            Insets.l + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: LocalText(
                      '选择控制点',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('关闭'),
                    icon: const OutlineSymbol(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Insets.s),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const OutlineSymbol(Icons.search, size: 18),
                  hintText: context.tr('搜索点名、分组或备注'),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
              if (groups.length > 1) ...[
                const SizedBox(height: Insets.s),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const LocalText('全部'),
                        selected: _group == null,
                        onSelected: (_) => setState(() => _group = null),
                      ),
                      for (final g in groups) ...[
                        const SizedBox(width: Insets.xs),
                        ChoiceChip(
                          label: Text(g),
                          selected: _group == g,
                          onSelected: (_) => setState(() => _group = g),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: Insets.s),
              Flexible(
                child: filtered.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: Insets.xl),
                        child: EmptyHint(
                          icon: Icons.location_off_outlined,
                          message: '暂无控制点',
                          hint: '请先在控制点库中添加或导入控制点',
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final p = filtered[index];
                          return SurfaceCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Insets.m,
                              vertical: Insets.s,
                            ),
                            onTap: () => Navigator.of(context).pop(p),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            p.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(width: Insets.s),
                                          Pill(label: p.group),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${context.tr('X(北)')} ${p.x.toStringAsFixed(digits)}   '
                                        '${context.tr('Y(东)')} ${p.y.toStringAsFixed(digits)}'
                                        '${p.h != null ? '   ${context.tr('H')} ${p.h!.toStringAsFixed(digits)}' : ''}',
                                        style: monoNumber(context, size: 12.5)
                                            .copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ],
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

/// Tool #19: Control Point Library page.
class ControlPointsPage extends StatefulWidget {
  const ControlPointsPage({super.key});

  @override
  State<ControlPointsPage> createState() => _ControlPointsPageState();
}

class _ControlPointsPageState extends State<ControlPointsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selectedGroup;
  bool _requestedLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requestedLoad) {
      _requestedLoad = true;
      final store = ControlPointScope.maybeRead(context);
      if (store != null && !store.loaded) {
        store.load();
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ControlPoint> _filtered(ControlPointStore store) {
    return store.points.where((p) {
      if (_selectedGroup != null && p.group != _selectedGroup) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.group.toLowerCase().contains(q) ||
          p.note.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openEditor(
    ControlPointStore store, {
    ControlPoint? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final xCtrl = TextEditingController(
      text: existing != null ? existing.x.toString() : '',
    );
    final yCtrl = TextEditingController(
      text: existing != null ? existing.y.toString() : '',
    );
    final hCtrl = TextEditingController(
      text: existing?.h != null ? existing!.h.toString() : '',
    );
    final groupCtrl = TextEditingController(text: existing?.group ?? '默认');
    final noteCtrl = TextEditingController(text: existing?.note ?? '');

    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final hasDuplicate = store.hasDuplicateName(
            nameCtrl.text,
            excludeId: existing?.id,
          );
          final scheme = Theme.of(context).colorScheme;
          return AlertDialog(
            title: LocalText(existing == null ? '新增控制点' : '编辑控制点'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextValueField(
                      controller: nameCtrl,
                      label: '点名',
                      hint: '例如 BM1 / GPS01',
                      onChanged: (_) => setDialogState(() => errorText = null),
                    ),
                    if (hasDuplicate) ...[
                      const SizedBox(height: Insets.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Insets.s,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: IosColors.orange(scheme.brightness)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(Radii.field),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 16,
                              color: IosColors.orange(scheme.brightness),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: LocalText(
                                '已存在同名控制点，请注意区分或修改点名',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: IosColors.orange(scheme.brightness),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: Insets.m),
                    Row(
                      children: [
                        Expanded(
                          child: NumberField(
                            controller: xCtrl,
                            label: 'X(北)',
                            unit: 'm',
                            onChanged: (_) =>
                                setDialogState(() => errorText = null),
                          ),
                        ),
                        const SizedBox(width: Insets.m),
                        Expanded(
                          child: NumberField(
                            controller: yCtrl,
                            label: 'Y(东)',
                            unit: 'm',
                            onChanged: (_) =>
                                setDialogState(() => errorText = null),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Insets.m),
                    Row(
                      children: [
                        Expanded(
                          child: NumberField(
                            controller: hCtrl,
                            label: 'H(高程)',
                            unit: 'm',
                            hint: '可选',
                            onChanged: (_) =>
                                setDialogState(() => errorText = null),
                          ),
                        ),
                        const SizedBox(width: Insets.m),
                        Expanded(
                          child: TextValueField(
                            controller: groupCtrl,
                            label: '分组',
                            hint: '默认',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Insets.m),
                    TextValueField(
                      controller: noteCtrl,
                      label: '备注',
                      hint: '点位说明（可选）',
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: Insets.s),
                      Text(
                        context.tr(errorText!),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: IosColors.red(scheme.brightness),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const LocalText('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  final x = double.tryParse(xCtrl.text.trim());
                  final y = double.tryParse(yCtrl.text.trim());
                  final hText = hCtrl.text.trim();
                  final h = hText.isEmpty ? null : double.tryParse(hText);
                  if (name.isEmpty) {
                    setDialogState(() => errorText = '请输入点名');
                    return;
                  }
                  if (x == null || !x.isFinite || y == null || !y.isFinite) {
                    setDialogState(() => errorText = '请输入有效的 X / Y 坐标');
                    return;
                  }
                  if (hText.isNotEmpty && (h == null || !h.isFinite)) {
                    setDialogState(() => errorText = '请输入有效的高程 H');
                    return;
                  }
                  Navigator.of(context).pop(true);
                },
                child: const LocalText('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true && mounted) {
      final name = nameCtrl.text.trim();
      final x = double.parse(xCtrl.text.trim());
      final y = double.parse(yCtrl.text.trim());
      final hText = hCtrl.text.trim();
      final h = hText.isEmpty ? null : double.parse(hText);
      final group =
          groupCtrl.text.trim().isEmpty ? '默认' : groupCtrl.text.trim();
      final note = noteCtrl.text.trim();

      if (existing == null) {
        await store.add(
          name: name,
          x: x,
          y: y,
          h: h,
          group: group,
          note: note,
        );
        if (mounted) SurveyToast.success(context, '已添加控制点');
      } else {
        await store.update(
          existing.copyWith(
            name: name,
            x: x,
            y: y,
            h: h,
            clearH: h == null,
            group: group,
            note: note,
          ),
        );
        if (mounted) SurveyToast.success(context, '已更新控制点');
      }
    }

    nameCtrl.dispose();
    xCtrl.dispose();
    yCtrl.dispose();
    hCtrl.dispose();
    groupCtrl.dispose();
    noteCtrl.dispose();
  }

  Future<void> _confirmDelete(
    ControlPointStore store,
    ControlPoint point,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalText('删除控制点'),
        content: Text(
          context.tr('确定删除控制点 {name} 吗？', {'name': point.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const LocalText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const LocalText('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await store.remove(point.id);
      if (mounted) SurveyToast.info(context, '已删除控制点');
    }
  }

  Future<void> _importFromFile(ControlPointStore store) async {
    try {
      final path = await NativeFilesBridge.pickOpenFile(
        filterLabel: 'CSV / DXF',
        extensions: const ['csv', 'txt', 'dat', 'dxf'],
      );
      if (path == null || path.isEmpty || !mounted) return;
      final file = File(path);
      if (!await file.exists()) return;
      final content = await file.readAsString();
      if (!mounted) return;
      await _applyImportedContent(store, content);
    } catch (e) {
      if (mounted) {
        SurveyToast.error(context, '导入失败：$e');
      }
    }
  }

  Future<void> _importFromPaste(ControlPointStore store) async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalText('粘贴导入 CSV / DXF'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LocalText(
                '支持标准 CSV（点名,X,Y,H,分组,备注）、南方 CASS（点名,编码,Y,X,H）或 ASCII DXF。',
              ),
              const SizedBox(height: Insets.s),
              TextField(
                controller: controller,
                maxLines: 8,
                autofocus: true,
                style: monoNumber(context, size: 12.5),
                decoration: InputDecoration(
                  hintText: context.tr('在此粘贴坐标文本…'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const LocalText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const LocalText('导入'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (content != null && content.trim().isNotEmpty && mounted) {
      await _applyImportedContent(store, content);
    }
  }

  Future<void> _applyImportedContent(
    ControlPointStore store,
    String content,
  ) async {
    final parsed = store.parseCsvOrDxf(
      content,
      defaultGroup: _selectedGroup ?? '默认',
    );
    if (parsed.isEmpty) {
      SurveyToast.warning(context, '未识别到有效控制点数据');
      return;
    }
    await store.addAll(parsed);
    if (!mounted) return;
    SurveyToast.success(
      context,
      context.tr('已导入 {count} 个控制点', {'count': parsed.length}),
    );
  }

  Future<void> _exportCsvFile(ControlPointStore store) async {
    final digits = context
            .getInheritedWidgetOfExactType<SettingsScope>()
            ?.notifier
            ?.coordDigits ??
        3;
    final points = _filtered(store);
    if (points.isEmpty) {
      SurveyToast.info(context, '暂无可导出的控制点');
      return;
    }
    final table = SheetTable(
      title: context.tr('控制点库'),
      rows: [
        [
          context.tr('点名'),
          context.tr('X(北)'),
          context.tr('Y(东)'),
          context.tr('H(高程)'),
          context.tr('分组'),
          context.tr('备注'),
        ],
        for (final p in points)
          [
            p.name,
            p.x.toStringAsFixed(digits),
            p.y.toStringAsFixed(digits),
            p.h != null ? p.h!.toStringAsFixed(digits) : '',
            p.group,
            p.note,
          ],
      ],
    );
    final res = await ExportService.export(table, format: ExportFormat.csv);
    if (!mounted) return;
    if (!res.ok) {
      SurveyToast.error(context, '导出失败：${res.error ?? ''}');
      return;
    }
    SurveyToast.success(
      context,
      '已导出 CSV：${res.path}',
      duration: const Duration(seconds: 4),
      actionLabel: Platform.isWindows ? '打开文件夹' : null,
      onAction: () => ExportService.openFolder(res.path!),
    );
  }

  Future<void> _exportCassFile(ControlPointStore store) async {
    final digits = context
            .getInheritedWidgetOfExactType<SettingsScope>()
            ?.notifier
            ?.coordDigits ??
        3;
    final cass = store.toCassCsv(group: _selectedGroup, digits: digits);
    if (cass.trim().isEmpty) {
      SurveyToast.info(context, '暂无可导出的控制点');
      return;
    }
    final savePath = await NativeFilesBridge.pickSaveFile(
      suggestedName: 'control_points_cass.csv',
      filterLabel: 'CSV / DAT',
      extensions: const ['csv', 'dat'],
    );
    if (!mounted) return;
    if (savePath != null && savePath.isNotEmpty) {
      await File(savePath).writeAsString(cass, flush: true);
      if (mounted) {
        SurveyToast.success(context, '已导出 CASS CSV：$savePath');
      }
      return;
    }
    final points = _filtered(store);
    final table = SheetTable(
      title: '${context.tr('控制点库')}_CASS',
      rows: [
        for (final p in points)
          [
            p.name,
            p.note,
            p.y.toStringAsFixed(digits),
            p.x.toStringAsFixed(digits),
            p.h != null ? p.h!.toStringAsFixed(digits) : '0.000',
          ],
      ],
    );
    final res = await ExportService.export(table, format: ExportFormat.csv);
    if (!mounted) return;
    if (res.ok) {
      SurveyToast.success(
        context,
        '已导出 CASS CSV：${res.path}',
        duration: const Duration(seconds: 4),
        actionLabel: Platform.isWindows ? '打开文件夹' : null,
        onAction: () => ExportService.openFolder(res.path!),
      );
    } else {
      SurveyToast.error(context, '导出失败：${res.error ?? ''}');
    }
  }

  Future<void> _copyText(String text, String successMessage) async {
    if (text.trim().isEmpty) {
      SurveyToast.info(context, '暂无可复制的控制点');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    await HapticFeedback.selectionClick();
    if (mounted) {
      SurveyToast.success(context, successMessage);
    }
  }

  Future<void> _projectToLivePlot(ControlPointStore store) async {
    final points = _filtered(store);
    if (points.isEmpty) {
      SurveyToast.info(context, '暂无可投影的控制点');
      return;
    }
    final controller = LivePlotScope.maybeRead(context);
    if (controller == null) {
      SurveyToast.warning(context, '实时坐标图控制器未挂载');
      return;
    }
    controller.updateSnapshot(
      LivePlotSnapshot(
        title: context.tr('控制点库'),
        sourceToolId: 'control_points',
        sourceLabel: _selectedGroup ?? context.tr('控制点库'),
        sourceKind: LivePlotSourceKind.controlPoints,
        points: [
          for (final p in points)
            LivePlotPointData(
              x: p.x,
              y: p.y,
              label: p.name,
              emphasis: true,
              draggable: false,
            ),
        ],
        surveyNorthUp: true,
        unit: 'm',
      ),
      sourceKind: LivePlotSourceKind.controlPoints,
    );
    SurveyToast.success(
      context,
      context.tr('已将 {count} 个控制点投影到 LivePlot', {'count': points.length}),
    );
    await showWorkspacePlot(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = ControlPointScope.of(context);
    final digits = context
            .dependOnInheritedWidgetOfExactType<SettingsScope>()
            ?.notifier
            ?.coordDigits ??
        3;
    final filtered = _filtered(store);
    final groups = store.groups;
    final scheme = Theme.of(context).colorScheme;

    return PageScaffold(
      title: _l(context, '控制点库', 'Control Points'),
      caption: _l(
        context,
        '管理本地已知控制点，支持 CSV / CASS / DXF 导入导出与 LivePlot 实时投影',
        'Manage local control points with CSV / CASS / DXF import/export and LivePlot projection',
      ),
      trailing: [
        FilledButton.icon(
          onPressed: () => _openEditor(store),
          icon: const OutlineSymbol(Icons.add, size: 18),
          label: Text(_l(context, '新增控制点', 'Add Point')),
        ),
      ],
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const OutlineSymbol(Icons.search, size: 18),
                  hintText: context.tr('搜索点名、分组或备注'),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.tr('清空'),
                          icon: const OutlineSymbol(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
              if (groups.isNotEmpty) ...[
                const SizedBox(height: Insets.m),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text(_l(context, '全部', 'All')),
                        selected: _selectedGroup == null,
                        onSelected: (_) =>
                            setState(() => _selectedGroup = null),
                      ),
                      for (final g in groups) ...[
                        const SizedBox(width: Insets.xs),
                        ChoiceChip(
                          label: Text(
                              g == '默认' ? _l(context, '默认', 'Default') : g),
                          selected: _selectedGroup == g,
                          onSelected: (_) => setState(() => _selectedGroup = g),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: Insets.m),
              Wrap(
                spacing: Insets.s,
                runSpacing: Insets.s,
                children: [
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'file') {
                        _importFromFile(store);
                      } else if (value == 'paste') {
                        _importFromPaste(store);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'file',
                        child: LocalText('从文件导入 (CSV / DXF)'),
                      ),
                      PopupMenuItem(
                        value: 'paste',
                        child: LocalText('粘贴导入 (CSV / CASS / DXF)'),
                      ),
                    ],
                    child: IgnorePointer(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const OutlineSymbol(
                          Icons.file_upload_outlined,
                          size: 18,
                        ),
                        label: Text(_l(context, '批量导入', 'Batch Import')),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'csv_file':
                          _exportCsvFile(store);
                        case 'cass_file':
                          _exportCassFile(store);
                        case 'csv_clip':
                          _copyText(
                            store.toCsv(
                              group: _selectedGroup,
                              digits: digits,
                            ),
                            '已复制 CSV 到剪贴板',
                          );
                        case 'cass_clip':
                          _copyText(
                            store.toCassCsv(
                              group: _selectedGroup,
                              digits: digits,
                            ),
                            '已复制 CASS CSV 到剪贴板',
                          );
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'csv_file',
                        child: LocalText('导出 CSV 文件'),
                      ),
                      PopupMenuItem(
                        value: 'cass_file',
                        child: LocalText('导出 CASS CSV 文件'),
                      ),
                      PopupMenuItem(
                        value: 'csv_clip',
                        child: LocalText('复制为 CSV'),
                      ),
                      PopupMenuItem(
                        value: 'cass_clip',
                        child: LocalText('复制为 CASS CSV'),
                      ),
                    ],
                    child: IgnorePointer(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const OutlineSymbol(
                          Icons.file_download_outlined,
                          size: 18,
                        ),
                        label: Text(_l(context, '导出', 'Export')),
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _projectToLivePlot(store),
                    icon:
                        const OutlineSymbol(Icons.polyline_outlined, size: 18),
                    label: Text(
                        _l(context, '投影到 LivePlot', 'Project to LivePlot')),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Insets.l),
        SectionHeader(
          title: _l(context, '控制点列表', 'Control Point List'),
          trailing: Pill(
            label: _l(
              context,
              context.tr('{count} 个点', {'count': filtered.length}),
              '${filtered.length} pts',
            ),
          ),
        ),
        if (filtered.isEmpty)
          SurfaceCard(
            child: EmptyHint(
              icon: Icons.location_searching_outlined,
              message: _l(context, '暂无控制点', 'No control points'),
              hint: _l(
                context,
                '点击右上角“新增控制点”或使用“批量导入”添加控制点',
                'Tap "Add Point" or "Batch Import" to add control points',
              ),
            ),
          )
        else
          for (final p in filtered) ...[
            SurfaceCard(
              margin: const EdgeInsets.only(bottom: Insets.s),
              onTap: () => _openEditor(store, existing: p),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              p.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: Insets.s),
                            Pill(
                              label: p.group == '默认'
                                  ? _l(context, '默认', 'Default')
                                  : p.group,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${context.tr('X(北)')} ${p.x.toStringAsFixed(digits)}   '
                          '${context.tr('Y(东)')} ${p.y.toStringAsFixed(digits)}'
                          '${p.h != null ? '   ${context.tr('H')} ${p.h!.toStringAsFixed(digits)}' : ''}',
                          style: monoNumber(context, size: 13.5),
                        ),
                        if (p.note.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            p.note,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('编辑'),
                    icon: const OutlineSymbol(Icons.edit_outlined, size: 18),
                    onPressed: () => _openEditor(store, existing: p),
                  ),
                  IconButton(
                    tooltip: context.tr('删除'),
                    icon: const OutlineSymbol(Icons.delete_outline, size: 18),
                    onPressed: () => _confirmDelete(store, p),
                  ),
                ],
              ),
            ),
          ],
      ],
    );
  }
}
