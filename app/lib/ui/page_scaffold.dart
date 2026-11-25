import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/survey_strings.dart';
import '../state/settings.dart';
import '../theme/tokens.dart';
import 'widgets/glass_nav.dart';

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
    final bottomReserve = glassNavBottomReserve(context);
    return Scaffold(
      // 不能留 transparent：一旦外层没有不透明底色，窗口黑底会透出来。
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButton: fab,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pad = constraints.maxWidth >= 900 ? Insets.xxl : Insets.l;
            return SingleChildScrollView(
              // 玻璃导航悬浮在内容之上：把让位放进滚动内容，滚到底时
              // 最后一张卡片会停在条子上方，不会被永久遮住。
              padding: EdgeInsets.fromLTRB(
                pad,
                Insets.l,
                pad,
                Insets.xxxl + bottomReserve,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.tr(title),
                                  style: TextStyle(
                                    fontSize:
                                        constraints.maxWidth >= 900 ? 32 : 28,
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
                          if (trailing != null) ...[
                            const SizedBox(width: Insets.s),
                            ..._spaced(trailing!),
                          ],
                        ],
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
    this.actions,
    this.bottomBar,
    this.toolbar,
    this.sideVisual,
    this.bottomSection,
    this.desktopRail,
    this.resultsBesideInputs = false,
    this.maxWidth = 820,
    this.wideMaxWidth = 1160,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget>? actions;

  /// 内容最上方的一条工具插槽（草稿状态 + 导出等 PageActions 条）。
  /// 由调用方传入；为 null 时只留出视觉间距，不占位。
  final Widget? toolbar;

  /// 固定在底部的操作条（如「计算」主按钮）。
  final Widget? bottomBar;

  /// 宽屏右侧栏（实时图形 + 核心成果卡）；窄屏时顺次排在 [children] 之后。
  final Widget? sideVisual;

  /// 双栏下方通栏区（宽表、手簿、教材表格等）。
  final Widget? bottomSection;
  final Widget? desktopRail;
  final bool resultsBesideInputs;

  final double maxWidth;
  final double wideMaxWidth;

  @override
  State<DetailScaffold> createState() => _DetailScaffoldState();
}

class _DetailScaffoldState extends State<DetailScaffold> {
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _leftKey = GlobalKey();
  final GlobalKey _rightKey = GlobalKey();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomReserve = glassNavBottomReserve(context);
    final twoPane =
        widget.sideVisual != null && MediaQuery.sizeOf(context).width >= 980;
    final effectiveMaxWidth = twoPane ? widget.wideMaxWidth : widget.maxWidth;
    final resultsInRightPane = twoPane && widget.resultsBesideInputs;
    final detail = Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              context.tr(widget.title),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.25,
              ),
            ),
            if (widget.subtitle != null)
              Text(
                context.tr(widget.subtitle!),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0.5),
          child: Divider(height: 0.5, thickness: 0.5),
        ),
        actions: widget.actions,
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: EdgeInsets.fromLTRB(
            Insets.l,
            Insets.s,
            Insets.l,
            Insets.xxl + bottomReserve,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.toolbar != null) ...[
                    widget.toolbar!,
                    const SizedBox(height: Insets.m),
                  ],
                  if (twoPane) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: KeyedSubtree(
                            key: _leftKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: _stack(widget.children),
                            ),
                          ),
                        ),
                        const SizedBox(width: Insets.l),
                        Expanded(
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
                                  dy = _scrollCtrl.offset.clamp(0.0, maxShift);
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
                            child: resultsInRightPane
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: _stack([
                                      widget.sideVisual!,
                                      if (widget.bottomSection != null)
                                        widget.bottomSection!,
                                    ]),
                                  )
                                : widget.sideVisual!,
                          ),
                        ),
                      ],
                    ),
                    if (!resultsInRightPane &&
                        widget.bottomSection != null) ...[
                      const SizedBox(height: Insets.l),
                      widget.bottomSection!,
                    ],
                  ] else ...[
                    ..._stack([
                      ...widget.children,
                      if (widget.sideVisual != null) widget.sideVisual!,
                      if (widget.bottomSection != null) widget.bottomSection!,
                    ]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: widget.bottomBar == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.l,
                  Insets.s,
                  Insets.l,
                  Insets.m,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
                    child: widget.bottomBar!,
                  ),
                ),
              ),
            ),
    );
    if (MediaQuery.sizeOf(context).width < 1140 || widget.desktopRail == null) {
      return detail;
    }
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 192, child: widget.desktopRail),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: detail),
        ],
      ),
    );
  }
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

/// 玻璃导航栏悬浮在内容之上时，滚动内容需要补的底部让位。
///
/// 窄屏使用悬浮玻璃导航时返回
/// [GlassNavBar.bottomReserve]；宽屏是侧栏玻璃，不遮内容，返回 0。
///
/// 这里用 dependOnInheritedWidgetOfExactType 而不是 SettingsScope.of：
/// 页面在没有 SettingsScope 的裸 pump 场景（个别测试 / 预览）按 0 处理，不崩。
double glassNavBottomReserve(BuildContext context) {
  final settings =
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()?.notifier;
  if (settings == null || !settings.floatingGlassNav) return 0;
  if (MediaQuery.sizeOf(context).width >= kSidebarNavigationMinWidth) return 0;
  return GlassNavBar.bottomReserve;
}
