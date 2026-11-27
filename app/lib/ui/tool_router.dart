import 'dart:async';

import 'package:flutter/material.dart';
import 'workspace_page_route.dart';

import '../nav/tools.dart';
import '../state/live_plot_controller.dart';
import '../state/settings.dart';
import '../l10n/survey_strings.dart';
import '../theme/workspace_layout.dart';
import 'widgets/liquid_glass.dart';
import 'pages/tools/batch_tools.dart';
import 'pages/tools/control_points_page.dart';
import 'pages/tools/control_tools.dart';
import 'pages/tools/convert_tools.dart';
import 'pages/tools/coord_tools.dart';
import 'pages/tools/four_order_leveling.dart';
import 'pages/tools/curve_tools.dart';
import 'pages/tools/projection_tools.dart';
import 'pages/tools/quadrant_tools.dart';
import 'pages/tools/resection_page.dart';
import 'pages/tools/earthwork_tools.dart';
import 'pages/tools_page.dart' show FormulaToolPage;

/// 按工具 id 打开对应页面。
Future<void> openTool(
  BuildContext context,
  ToolDef tool, {
  String? draftId,
  bool fromSidebar = false,
  bool replaceExistingTool = false,
}) async {
  final navigator = Navigator.of(context);
  final settings = SettingsScope.read(context);
  final requested = draftId ??
      (tool.id == 'leveling4' &&
              settings.lastDraftId?.startsWith('leveling4/') == true
          ? settings.lastDraftId
          : null);
  final resume = requested == tool.id ? null : requested;
  final name = 'tool/${tool.id}';
  final observer = navigator.widget.observers
      .whereType<WorkspaceNavigatorObserver>()
      .firstOrNull;
  final current = observer?.topRoute ?? ModalRoute.of(context);
  if ((observer != null || replaceExistingTool) &&
      (observer?.activeName ?? current?.settings.name) == name &&
      (observer == null
              ? current?.settings.arguments
              : observer.activeArgument) ==
          resume) {
    return;
  }

  unawaited(settings.setLastTool(tool.id, draftId: resume));
  final wide = observer != null && !workspaceUsesCompactLayout(context);
  Widget buildTool(BuildContext _) => toolPage(tool, draftId: resume);
  if (wide) {
    if (current is WorkspaceToolRoute) {
      if (current.select((name, resume), buildTool)) {
        LivePlotScope.maybeRead(context)?.activateRecentForTool(tool.id);
      }
      observer.onChanged();
      return;
    }
    final route = WorkspaceToolRoute((name, resume), buildTool,
        fromSidebar: fromSidebar,
        reduceMotion: MediaQuery.disableAnimationsOf(context));
    if (navigator.canPop()) {
      await navigator.pushAndRemoveUntil(route, (route) => route.isFirst);
    } else {
      await navigator.push(route);
    }
    return;
  }
  final defer = observer != null && WorkspaceHost.isAndroid(context);
  await openWorkspacePage(
    context,
    name: name,
    argument: resume,
    builder: (context) => ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: defer
          ? DeferredTransitionChild(
              afterFrame: true,
              placeholder: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(context.tr(tool.title),
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ),
                ),
              ),
              child: buildTool(context),
            )
          : buildTool(context),
    ),
    replaceExistingTool: replaceExistingTool,
  );
}

Future<void> openWorkspacePage(
  BuildContext context, {
  required String name,
  required WidgetBuilder builder,
  Object? argument,
  bool replaceExistingTool = false,
}) async {
  final navigator = Navigator.of(context);
  final observer = navigator.widget.observers
      .whereType<WorkspaceNavigatorObserver>()
      .firstOrNull;
  final shallow = replaceExistingTool || observer != null;
  final current = observer?.topRoute ?? ModalRoute.of(context);
  if (shallow &&
      (observer?.activeName ?? current?.settings.name) == name &&
      (observer == null
              ? current?.settings.arguments
              : observer.activeArgument) ==
          argument) {
    return;
  }
  final route = WorkspacePageRoute<void>(
    settings: RouteSettings(name: name, arguments: argument),
    reduceMotion: MediaQuery.disableAnimationsOf(context),
    builder: builder,
  );
  if (shallow && navigator.canPop()) {
    await navigator.pushAndRemoveUntil(route, (route) => route.isFirst);
  } else {
    await navigator.push(route);
  }
}

/// 工具 id → 页面组件。
Widget toolPage(ToolDef tool, {String? draftId}) {
  return switch (tool.id) {
    // 坐标与放样
    'inverse' => const InversePage(),
    'polar' => const PolarPage(),
    'stakeout' => const StakeoutPage(),
    'batch_stakeout' => const BatchStakeoutPage(),
    'intersection' => draftId == 'intersection/resection'
        ? const ResectionPage()
        : const IntersectionPage(),
    // 控制测量
    'traverse' => const TraversePage(),
    'leveling' => const LevelingPage(),
    'leveling4' => FourOrderLevelingPage(draftId: draftId),
    'precision' => const PrecisionPage(),
    'control_points' => const ControlPointsPage(),
    // 线路与曲线
    'circular_curve' => const CircularCurvePage(),
    'clothoid' => const ClothoidPage(),
    'vertical_curve' => const VerticalCurvePage(),
    'route_stake' => const RouteStakePage(),
    // 面积与土方
    'area' => const AreaPage(),
    'earthwork' => const EarthworkPage(),
    // 计算与换算
    'formula' => const FormulaToolPage(),
    'projection' => const ProjectionPage(),
    'convert' => const ConvertPage(),
    'quadrant' => const QuadrantPage(),
    _ => _MissingToolPage(tool: tool),
  };
}

class _MissingToolPage extends StatelessWidget {
  const _MissingToolPage({required this.tool});

  final ToolDef tool;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tool.title)),
      body: Center(child: Text('工具「${tool.id}」尚未实现')),
    );
  }
}
