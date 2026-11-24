import 'package:flutter/material.dart';

import '../nav/tools.dart';
import '../state/settings.dart';
import 'pages/tools/batch_tools.dart';
import 'pages/tools/control_tools.dart';
import 'pages/tools/convert_tools.dart';
import 'pages/tools/coord_tools.dart';
import 'pages/tools/four_order_leveling.dart';
import 'pages/tools/curve_tools.dart';
import 'pages/tools/projection_tools.dart';
import 'pages/tools/quadrant_tools.dart';
import 'pages/tools/earthwork_tools.dart';
import 'pages/tools_page.dart' show FormulaToolPage;

/// 按工具 id 打开对应页面。
Future<void> openTool(BuildContext context, ToolDef tool) async {
  // 先取好 Navigator，避免在 await 之后再用 context（async gap）。
  final navigator = Navigator.of(context);
  final settings = SettingsScope.read(context);
  await settings.setLastTool(tool.id);
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => toolPage(tool),
    ),
  );
}

/// 工具 id → 页面组件。
Widget toolPage(ToolDef tool) {
  return switch (tool.id) {
    // 坐标与放样
    'inverse' => const InversePage(),
    'polar' => const PolarPage(),
    'stakeout' => const StakeoutPage(),
    'batch_stakeout' => const BatchStakeoutPage(),
    'intersection' => const IntersectionPage(),
    // 控制测量
    'traverse' => const TraversePage(),
    'leveling' => const LevelingPage(),
    'leveling4' => const FourOrderLevelingPage(),
    'precision' => const PrecisionPage(),
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
