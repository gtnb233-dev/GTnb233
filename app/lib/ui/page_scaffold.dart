import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../export/export_service.dart';
import '../l10n/survey_strings.dart';
import '../state/drafts.dart';
import '../state/settings.dart';
import '../theme/tokens.dart';
import '../theme/workspace_layout.dart';
import 'widgets/liquid_glass.dart';
import 'widgets/measurement_units_button.dart';
import 'widgets/overlays.dart';
import 'widgets/page_actions.dart';
import 'widgets/tutorial_panel.dart';
import 'widgets/workspace_commands.dart';
import 'widgets/workspace_sidebar_control.dart';

/// 一级页面骨架：可滚动大标题 + 内容区。
///
/// 内容区在桌面端限制宽度并居中。
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.children,
    this.caption,
    this.trailing,
    this.header,
    this.fab,
    this.toolbar,
    this.maxWidth = Insets.contentMaxWidth,
  });

  final String title;
  final String? caption;
  final List<Widget> children;
  final List<Widget>? trailing;

  /// 标题下方的一条工具插槽（草稿状态 + 导出等 PageActions 条）。
  final Widget? toolbar;

  /// 标题下方的自定义区块（如状态总览卡）。
  final Widget? header;
  final Widget? fab;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = workspaceUsesCompactLayout(context);
    final sidebar = WorkspaceSidebarScope.maybeOf(context);
    return Scaffold(
      // 不能留 transparent：一旦外层没有不透明底色，窗口黑底会透出来。
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButton: fab,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pad = constraints.maxWidth >= 900 ? Insets.xxl : Insets.l;
            return SingleChildScrollView(
              physics: compact
                  ? const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics())
                  : null,
              padding:
                  EdgeInsets.fromLTRB(pad, kTopBarTopInset, pad, Insets.xl),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ConstrainedBox(
                        constraints:
                            const BoxConstraints(minHeight: kTopBarHeight),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (sidebar != null) ...[
                              SizedBox(
                                height: kTopBarHeight,
                                child: Center(
                                  child: sidebar.open && sidebar.overlay
                                      ? const SizedBox(width: kTopBarButtonSize)
                                      : WorkspaceSidebarControl(
                                          open: sidebar.open,
                                          onToggle: sidebar.onToggle,
                                        ),
                                ),
                              ),
                              const SizedBox(width: Insets.s),
                            ],
                            Expanded(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                    minHeight: kTopBarHeight),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.tr(title),
                                      textHeightBehavior:
                                          kSurveyTextHeightBehavior,
                                      style: TextStyle(
                                        fontSize: constraints.maxWidth >= 900
                                            ? 32
                                            : 28,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.7,
                                        color: scheme.onSurface,
                                        height: 1.15,
                                      ),
                                    ),
                                    if (caption != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        context.tr(caption!),
                                        textHeightBehavior:
                                            kSurveyTextHeightBehavior,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: scheme.onSurfaceVariant,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (trailing != null) ...[
                              const SizedBox(width: Insets.s),
                              SizedBox(
                                height: kTopBarHeight,
                                child: Center(
                                  child: IconButtonTheme(
                                    data: IconButtonThemeData(
                                      style: IconButton.styleFrom(
                                        minimumSize: const Size.square(
                                          kTopBarButtonSize,
                                        ),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        padding: EdgeInsets.zero,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: _spaced(trailing!),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (toolbar != null) ...[
                        const SizedBox(height: Insets.m),
                        toolbar!,
                      ],
                      const SizedBox(height: Insets.xl),
                      if (header != null) ...[
                        header!,
                        const SizedBox(height: Insets.l),
                      ],
                      ..._stack(children),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 二级页面骨架：返回按钮 + 标题 + 滚动内容。
///
/// 宽屏（≥ 980dp）且提供 [sideVisual] 时自动排成「左输入、右可视化与核心成果、下方宽表」
/// 双栏工作台，窄屏自动退回单列，始终使用单一垂直滚动容器以保持键盘/定位一致。
class DetailScaffold extends StatefulWidget {
  const DetailScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.mobileSubtitle,
    this.actions,
    this.mobilePrimaryAction,
    this.bottomBar,
    this.toolbar,
    this.draftBadge,
    this.sideVisual,
    this.reserveSideVisual = false,
    this.bottomSection,
    this.resultsBesideInputs = false,
    this.maxWidth = 820,
    this.wideMaxWidth = 1160,
  });

  final String title;
  final String? subtitle;
  final String? mobileSubtitle;
  final List<Widget> children;
  final List<Widget>? actions;
  final IconButton? mobilePrimaryAction;

  /// 内容最上方的一条工具插槽（草稿状态 + 导出等 PageActions 条）。
  /// 由调用方传入；为 null 时只留出视觉间距，不占位。
  final Widget? toolbar;

  /// 可选标题右侧内联草稿状态徽标；未传入且 [toolbar] 为 [PageActions] 时自动读取。
  final Widget? draftBadge;

  /// 固定在底部的操作条（如「计算」主按钮）。
  final Widget? bottomBar;

  /// 宽屏右侧栏（实时图形 + 核心成果卡）；窄屏时顺次排在 [children] 之后。
  final Widget? sideVisual;

  /// Keeps the input and visual columns fixed while calculated data is pending.
  final bool reserveSideVisual;

  /// 双栏下方通栏区（宽表、手簿、教材表格等）。
  final Widget? bottomSection;
  final bool resultsBesideInputs;

  final double maxWidth;
  final double wideMaxWidth;

  @override
  State<DetailScaffold> createState() => _DetailScaffoldState();
}

class _DetailScaffoldState extends State<DetailScaffold> {
  final ScrollController _scrollCtrl = ScrollController();

  double get _scrollOffset =>
      _scrollCtrl.positions.length == 1 ? _scrollCtrl.offset : 0;

  final GlobalKey _leftKey = GlobalKey();
  final GlobalKey _rightKey = GlobalKey();

  PageActions? get _pageActions =>
      widget.toolbar is PageActions ? widget.toolbar! as PageActions : null;

  PageTutorial? get _tutorial =>
      widget.children.whereType<PageTutorial>().firstOrNull;

  static String _headerActionLabel(BuildContext context, String id) =>
      switch (id) {
        'export' => context.tr('导出'),
        'point_names' => context.tr('自定义点名'),
        'sample' => context.tr('载入教材算例'),
        'clear' => context.tr('清空'),
        _ => id,
      };

  static IconData _headerActionIcon(String id) => switch (id) {
        'export' => Icons.ios_share,
        'point_names' => Icons.edit_note_rounded,
        'sample' => Icons.auto_fix_high_outlined,
        'clear' => Icons.restart_alt,
        _ => Icons.bolt_rounded,
      };

  Widget? _buildDraftBadge(BuildContext context) {
    if (widget.draftBadge != null) return widget.draftBadge;
    final pageActions = _pageActions;
    if (pageActions == null) return null;
    final drafts = DraftScope.maybeOf(context);
    if (drafts == null) return null;
    final scheme = Theme.of(context).colorScheme;
    final savedAt = drafts.savedAt(pageActions.pageId);
    String two(int v) => v.toString().padLeft(2, '0');
    final label = savedAt == null
        ? context.tr('草稿未保存')
        : context.tr('已保存 {time}', {
            'time': '${two(savedAt.hour)}:${two(savedAt.minute)}',
          });
    final dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: savedAt == null
            ? scheme.onSurfaceVariant.withValues(alpha: 0.45)
            : const Color(0xFF2E7D32),
      ),
    );
    return Tooltip(
      message: label,
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 24) return dot;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dot,
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  List<Widget> _buildPinnedHeaderButtons(
    BuildContext context,
  ) {
    final settings = SettingsScope.maybeOf(context);
    final pinnedIds = settings?.pinnedHeaderActions ??
        AppSettings.kDefaultPinnedHeaderActions;
    final pageActions = _pageActions;
    final sampleCb = pageActions?.onLoadSample ?? _tutorial?.onLoadSample;
    final buttons = <Widget>[];
    for (final id in pinnedIds.take(3)) {
      switch (id) {
        case 'export':
          final buildTable = pageActions?.buildTable;
          if (buildTable == null) continue;
          buttons.add(
            PopupMenuButton<ExportFormat>(
              tooltip: context.tr('导出表格'),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.ios_share, size: 18),
              onSelected: (f) => PageActions.runExport(
                context,
                buildTable: buildTable,
                format: f,
              ),
              itemBuilder: (ctx) => [
                for (final f in ExportFormat.values)
                  PopupMenuItem(
                    value: f,
                    child: Row(
                      children: [
                        Icon(
                          switch (f) {
                            ExportFormat.xlsx => Icons.grid_on_outlined,
                            ExportFormat.png => Icons.image_outlined,
                            ExportFormat.csv => Icons.table_chart_outlined,
                            ExportFormat.txt => Icons.description_outlined,
                          },
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            ctx.tr(f.label),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        case 'point_names':
          final onPointNames = pageActions?.onPointNames;
          if (onPointNames == null) continue;
          buttons.add(
            IconButton(
              tooltip: context.tr('自定义点名'),
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: onPointNames,
              icon: const Icon(Icons.edit_note_rounded, size: 19),
            ),
          );
        case 'sample':
          if (sampleCb == null) continue;
          buttons.add(
            IconButton(
              tooltip: _headerActionLabel(context, id),
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: sampleCb,
              icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
            ),
          );
        case 'clear':
          final onClear = pageActions?.onClear;
          if (onClear == null) continue;
          buttons.add(
            IconButton(
              tooltip: context.tr('清空'),
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: () => PageActions.runClear(
                context,
                pageId: pageActions!.pageId,
                onClear: onClear,
                confirmClear: pageActions.confirmClear,
              ),
              icon: const Icon(Icons.restart_alt, size: 19),
            ),
          );
      }
    }
    return buttons;
  }

  Future<void> _showPinnedActionsPicker(BuildContext context) async {
    final settings = SettingsScope.maybeOf(context);
    if (settings == null) return;
    final initial = List<String>.of(settings.pinnedHeaderActions);
    final ordered = <String>[
      ...initial,
      for (final id in AppSettings.kValidHeaderActions)
        if (!initial.contains(id)) id,
    ];
    final selected = initial.toSet();
    void applySelection() {
      settings.setPinnedHeaderActions([
        for (final id in ordered)
          if (selected.contains(id)) id,
      ]);
    }

    await SurveyModal.show<void>(
      context,
      title: '自定义顶栏快捷动作',
      child: StatefulBuilder(
        builder: (sheetContext, setModalState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              sheetContext.tr('勾选并拖动排序 1–3 个常用动作固定到顶栏'),
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: Insets.s),
            SizedBox(
              height: 224,
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: ordered.length,
                onReorder: (oldIndex, newIndex) {
                  setModalState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = ordered.removeAt(oldIndex);
                    ordered.insert(
                        newIndex.clamp(0, selected.length - 1), item);
                  });
                  applySelection();
                },
                itemBuilder: (ctx, index) {
                  final id = ordered[index];
                  final checked = selected.contains(id);
                  return ListTile(
                    key: ValueKey('pin-action-$id'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Checkbox(
                      value: checked,
                      onChanged: (v) {
                        if (v == null) return;
                        if (!v && selected.length <= 1) {
                          SurveyToast.info(ctx, '至少保留 1 个快捷动作');
                          return;
                        }
                        if (v && selected.length >= 3) {
                          SurveyToast.info(ctx, '最多固定 3 个快捷动作');
                          return;
                        }
                        setModalState(() {
                          ordered.remove(id);
                          if (v) {
                            ordered.insert(selected.length, id);
                            selected.add(id);
                          } else {
                            selected.remove(id);
                            ordered.add(id);
                          }
                        });
                        applySelection();
                      },
                    ),
                    title: Row(
                      children: [
                        Icon(_headerActionIcon(id), size: 17),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _headerActionLabel(ctx, id),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    trailing: ReorderableDragStartListener(
                      index: index,
                      enabled: checked,
                      child: const ColoredBox(
                        color: Colors.transparent,
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(Icons.drag_handle_rounded, size: 18),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: Insets.s),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    final defaults = AppSettings.kDefaultPinnedHeaderActions;
                    setModalState(() {
                      selected
                        ..clear()
                        ..addAll(defaults);
                      ordered
                        ..clear()
                        ..addAll(defaults)
                        ..addAll(AppSettings.kValidHeaderActions
                            .where((id) => !selected.contains(id)));
                    });
                    applySelection();
                  },
                  child: Text(sheetContext.tr('恢复默认')),
                ),
                const SizedBox(width: Insets.s),
                FilledButton(
                  onPressed: () {
                    if (ModalRoute.of(sheetContext)?.isCurrent ?? false) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                  child: Text(sheetContext.tr('完成')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupHeader(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(top: Insets.xs, bottom: Insets.xs),
        child: Text(
          context.tr(title),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
      );

  Future<void> _showCompactActions() async {
    final android = WorkspaceHost.isAndroid(context);
    final settings = SettingsScope.maybeOf(context);
    final pageActions = _pageActions;
    final sampleCb = pageActions?.onLoadSample ?? _tutorial?.onLoadSample;
    final available = <String>[
      if (pageActions?.buildTable != null) 'export',
      if (pageActions?.onPointNames != null) 'point_names',
      if (sampleCb != null) 'sample',
      if (pageActions?.onClear != null) 'clear',
    ];
    final pinned = settings?.pinnedHeaderActions ??
        AppSettings.kDefaultPinnedHeaderActions;
    final unpinned = available.where((id) => !pinned.contains(id));
    final canReturn = WorkspaceSidebarScope.maybeOf(context) != null &&
        Navigator.canPop(context);
    final actions = widget.actions
            ?.where((action) => !identical(action, widget.mobilePrimaryAction))
            .toList() ??
        const <Widget>[];
    final command = await workspacePanel<String>(
      context,
      '更多操作',
      Builder(builder: (sheetContext) {
        void choose(String action) {
          if (ModalRoute.of(sheetContext)?.isCurrent ?? false) {
            Navigator.of(sheetContext).pop(action);
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (settings != null) ...[
              _groupHeader(context, '顶栏快捷动作'),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune_rounded),
                title: Text(context.tr('自定义顶栏快捷动作')),
                subtitle: Text(
                  settings.pinnedHeaderActions
                      .map((id) => _headerActionLabel(context, id))
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => choose('customize_pinned'),
              ),
              const Divider(height: Insets.m),
              _groupHeader(context, '外业显示'),
              AnimatedBuilder(
                animation: settings,
                builder: (ctx, _) => SwitchListTile.adaptive(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.light_mode_outlined),
                  title: Text(ctx.tr('外业保持屏幕常亮')),
                  subtitle: Text(ctx.tr('保持屏幕常亮，方便外业连续录数')),
                  value: settings.keepScreenOn,
                  onChanged: (v) => settings.setKeepScreenOn(v),
                ),
              ),
              const Divider(height: Insets.m),
            ],
            if (unpinned.isNotEmpty || actions.isNotEmpty || canReturn)
              _groupHeader(sheetContext, '工具与辅助操作'),
            if (canReturn)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                key: const ValueKey('more-action-back'),
                leading: const Icon(Icons.arrow_back),
                title: const LocalText('返回'),
                onTap: () => choose('back'),
              ),
            if (actions.isNotEmpty) ...[
              Wrap(spacing: 8, runSpacing: 8, children: actions),
              const SizedBox(height: Insets.s),
            ],
            for (final id in unpinned)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                key: ValueKey('more-action-$id'),
                leading: Icon(_headerActionIcon(id)),
                title: Text(_headerActionLabel(sheetContext, id)),
                onTap: () => choose(id),
              ),
          ],
        );
      }),
      useBottomSheet: android,
    );
    if (!mounted) return;
    switch (command) {
      case 'back':
        await Navigator.maybePop(context);
      case 'customize_pinned':
        await _showPinnedActionsPicker(context);
      case 'export':
        final format = await workspacePanel<ExportFormat>(
          context,
          '导出',
          Builder(
              builder: (sheetContext) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final format in ExportFormat.values)
                        ListTile(
                          title: LocalText(format.label),
                          onTap: () {
                            if (ModalRoute.of(sheetContext)?.isCurrent ??
                                false) {
                              Navigator.of(sheetContext).pop(format);
                            }
                          },
                        ),
                    ],
                  )),
          useBottomSheet: android,
        );
        if (format != null && mounted) {
          await PageActions.runExport(context,
              buildTable: pageActions!.buildTable!, format: format);
        }
      case 'point_names':
        pageActions?.onPointNames?.call();
      case 'sample':
        sampleCb?.call();
      case 'clear':
        if (pageActions?.onClear != null) {
          await PageActions.runClear(
            context,
            pageId: pageActions!.pageId,
            onClear: pageActions.onClear!,
            confirmClear: pageActions.confirmClear,
          );
        }
    }
  }

  Widget _toolHeader(
    BuildContext context, {
    required bool canPop,
    required bool stacked,
    required bool tight,
    required List<Widget> pinnedButtons,
    required double height,
  }) {
    final theme = Theme.of(context);
    final primary = widget.mobilePrimaryAction;
    final draftBadge = _buildDraftBadge(context);
    final sidebar = WorkspaceSidebarScope.maybeOf(context);
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sidebar != null) ...[
          SizedBox(
            height: kTopBarHeight,
            child: Center(
              child: sidebar.open && sidebar.overlay
                  ? const SizedBox(width: kTopBarButtonSize)
                  : WorkspaceSidebarControl(
                      open: sidebar.open, onToggle: sidebar.onToggle),
            ),
          ),
          const SizedBox(width: 7),
        ] else if (canPop) ...[
          SizedBox(
            height: kTopBarHeight,
            child: Center(
              child: SizedBox.square(
                dimension: kTopBarButtonSize,
                child: IconButton(
                  tooltip: context.tr('返回'),
                  onPressed: () => Navigator.maybePop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: kTopBarButtonSize,
                    height: kTopBarButtonSize,
                  ),
                  icon: LiquidGlassSurface(
                    width: kTopBarButtonSize,
                    height: kTopBarButtonSize,
                    borderRadius:
                        BorderRadius.circular(kTopBarButtonSize / 2),
                    elevated: false,
                    blurSigma: 12,
                    child: const Center(
                      child: Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
        ],
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kTopBarHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Row(
                children: [
                  Flexible(
                    flex: 3,
                    child: Text(
                      context.tr(widget.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (draftBadge != null) ...[
                    const SizedBox(width: 6),
                    Flexible(flex: 2, child: draftBadge),
                  ],
                ],
              ),
              if ((widget.mobileSubtitle ?? widget.subtitle)
                  case final subtitle?)
                Text(
                  context.tr(subtitle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        ),
      ],
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MeasurementUnitsButton(
          tight: tight,
          onLengthChanged: _pageActions?.onUnitChanged,
          onAngleChanged: _pageActions?.onAngleModeChanged,
        ),
        const SizedBox(width: 4),
        LiquidGlassSurface(
          key: const ValueKey('detail-action-capsule'),
          borderRadius: BorderRadius.circular(24),
          elevated: false,
          blurSigma: 12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (primary != null)
                SizedBox(width: 40, height: 42, child: primary),
              for (final button in pinnedButtons)
                SizedBox(width: 36, height: 42, child: button),
              SizedBox(
                width: 40,
                height: 42,
                child: IconButton(
                  tooltip: context.tr('更多操作'),
                  iconSize: 20,
                  onPressed: _showCompactActions,
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.scaffoldBackgroundColor,
              theme.scaffoldBackgroundColor.withValues(alpha: 0.92),
              theme.scaffoldBackgroundColor.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.62, 1.0],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, kTopBarTopInset, 12, 6),
          child: stacked
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ConstrainedBox(
                      constraints:
                          const BoxConstraints(minHeight: kTopBarHeight),
                      child: heading,
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: controls,
                    ),
                  ],
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kTopBarHeight),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: heading),
                      const SizedBox(width: 4),
                      SizedBox(
                        height: kTopBarHeight,
                        child: Center(child: controls),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _buildLayout);

  Widget _buildLayout(BuildContext context, BoxConstraints constraints) {
    final theme = Theme.of(context);
    final android = WorkspaceHost.isAndroid(context);
    final canPop = Navigator.canPop(context);
    final pinnedButtons = _buildPinnedHeaderButtons(context);
    final tight = constraints.maxWidth <= 360;
    final controlsWidth = (tight ? 76 : 94) +
        46 +
        36 * pinnedButtons.length +
        (widget.mobilePrimaryAction == null ? 0 : 40);
    final hasLeading = canPop || WorkspaceSidebarScope.maybeOf(context) != null;
    final stackedHeader =
        constraints.maxWidth - controlsWidth - (hasLeading ? 79 : 24) < 110;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final scaleExtra = math.max(0.0, (textScale - 1.0) * 40.0);
    final headerHeight = (stackedHeader
            ? 112.0
            : kTopBarTopInset + kTopBarHeight + 6.0) +
        scaleExtra;
    final twoPane = !workspaceUsesCompactLayout(context) &&
        (widget.sideVisual != null || widget.reserveSideVisual) &&
        constraints.maxWidth >= 560;
    final effectiveMaxWidth = twoPane ? widget.wideMaxWidth : widget.maxWidth;
    final resultsInRightPane = twoPane && widget.resultsBesideInputs;
    final sideVisual = widget.sideVisual ??
        const DeferredTransitionChild(
          placeholder: SizedBox(height: 220, child: ChartLoadingPlaceholder()),
          child: SizedBox.shrink(),
        );
    final content = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (twoPane) ...[
              Row(
                key: const ValueKey('workspace-detail-split'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    key: const ValueKey('workspace-detail-inputs'),
                    flex: 5,
                    child: RepaintBoundary(
                      child: KeyedSubtree(
                        key: _leftKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _stack(widget.children),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Insets.l),
                  Expanded(
                    key: const ValueKey('workspace-detail-visuals'),
                    flex: 6,
                    child: AnimatedBuilder(
                      animation: _scrollCtrl,
                      builder: (ctx, child) {
                        var dy = 0.0;
                        if (_scrollCtrl.hasClients) {
                          final leftBox = _leftKey.currentContext
                              ?.findRenderObject() as RenderBox?;
                          final rightBox = _rightKey.currentContext
                              ?.findRenderObject() as RenderBox?;
                          if (leftBox != null &&
                              leftBox.hasSize &&
                              rightBox != null &&
                              rightBox.hasSize) {
                            final maxShift = math.max(
                              0.0,
                              leftBox.size.height - rightBox.size.height,
                            );
                            dy = _scrollOffset.clamp(0.0, maxShift);
                          }
                        }
                        return Padding(
                          padding: EdgeInsets.only(top: dy),
                          child: KeyedSubtree(
                            key: _rightKey,
                            child: child!,
                          ),
                        );
                      },
                      child: RepaintBoundary(
                        child: resultsInRightPane
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _stack([
                                  sideVisual,
                                  if (widget.bottomSection != null)
                                    widget.bottomSection!,
                                ]),
                              )
                            : sideVisual,
                      ),
                    ),
                  ),
                ],
              ),
              if (!resultsInRightPane && widget.bottomSection != null) ...[
                const SizedBox(height: Insets.l),
                RepaintBoundary(child: widget.bottomSection!),
              ],
            ] else ...[
              ..._stack([
                for (final child in widget.children)
                  RepaintBoundary(child: child),
                if (widget.sideVisual != null)
                  RepaintBoundary(child: widget.sideVisual!),
                if (widget.bottomSection != null)
                  RepaintBoundary(child: widget.bottomSection!),
              ]),
            ],
          ],
        ),
      ),
    );
    return WorkspacePanelBackground(
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          bottom: widget.bottomBar == null,
          child: CustomScrollView(
            physics: android
                ? const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics())
                : null,
            controller: _scrollCtrl,
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _CompactHeaderDelegate(
                  height: headerHeight,
                  child: KeyedSubtree(
                    key: const ValueKey('workspace-detail-header'),
                    child: _toolHeader(context,
                        canPop: canPop,
                        stacked: stackedHeader,
                        tight: tight,
                        pinnedButtons: pinnedButtons,
                        height: headerHeight),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    Insets.l, Insets.s, Insets.l, Insets.xxl),
                sliver: SliverToBoxAdapter(child: content),
              ),
            ],
          ),
        ),
        bottomNavigationBar: widget.bottomBar == null
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Insets.l, Insets.s, Insets.l, Insets.m),
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
                      child: widget.bottomBar!,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _CompactHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _CompactHeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      child;

  @override
  bool shouldRebuild(_CompactHeaderDelegate oldDelegate) =>
      height != oldDelegate.height || child != oldDelegate.child;
}

List<Widget> _spaced(List<Widget> items) {
  final out = <Widget>[];
  for (var i = 0; i < items.length; i++) {
    if (i > 0) out.add(const SizedBox(width: Insets.s));
    out.add(items[i]);
  }
  return out;
}

List<Widget> _stack(List<Widget> items) {
  final out = <Widget>[];
  for (var i = 0; i < items.length; i++) {
    if (i > 0) out.add(const SizedBox(height: Insets.m));
    out.add(items[i]);
  }
  return out;
}
