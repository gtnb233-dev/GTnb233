import 'package:flutter/material.dart';

/// 功能分组，用于工具库分区展示。
enum ToolGroup {
  coordinates('坐标与放样', Icons.place_outlined),
  network('控制测量', Icons.hub_outlined),
  route('线路与曲线', Icons.timeline_outlined),
  earthwork('面积与土方', Icons.landscape_outlined),
  formula('计算与换算', Icons.calculate_outlined);

  const ToolGroup(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// 一个测量工具条目。
class ToolDef {
  const ToolDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.group,
    required this.icon,
    this.keywords = const <String>[],
  });

  final String id;
  final String title;
  final String subtitle;
  final ToolGroup group;
  final IconData icon;
  final List<String> keywords;
}

/// 全部工具注册表（顺序即展示顺序）。
const List<ToolDef> kTools = [
  // ── 坐标与放样 ──────────────────────────────────────────
  ToolDef(
    id: 'inverse',
    title: '坐标反算',
    subtitle: '两点坐标 → 距离、方位角、坐标增量',
    group: ToolGroup.coordinates,
    icon: Icons.straighten,
    keywords: ['方位角', '距离', '反算'],
  ),
  ToolDef(
    id: 'polar',
    title: '坐标正算 / 极坐标放样',
    subtitle: '已知点 + 方位角 + 距离 → 待放点坐标',
    group: ToolGroup.coordinates,
    icon: Icons.navigation_outlined,
    keywords: ['正算', '放样', '极坐标'],
  ),
  ToolDef(
    id: 'stakeout',
    title: '放样数据计算',
    subtitle: '测站 + 后视 → 目标点的水平角与距离',
    group: ToolGroup.coordinates,
    icon: Icons.gps_fixed,
    keywords: ['放样', '水平角', '后视'],
  ),
  ToolDef(
    id: 'batch_stakeout',
    title: '批量放样',
    subtitle: '一次定向，批量算多个目标点的水平角与平距',
    group: ToolGroup.coordinates,
    icon: Icons.playlist_add_check_circle_outlined,
    keywords: ['批量', '放样', '放样表', '转角'],
  ),
  ToolDef(
    id: 'intersection',
    title: '交会计算',
    subtitle: '前方交会 / 距离交会求待定点坐标',
    group: ToolGroup.coordinates,
    icon: Icons.call_merge,
    keywords: ['交会', '前方交会', '距离交会'],
  ),

  // ── 控制测量 ────────────────────────────────────────────
  ToolDef(
    id: 'traverse',
    title: '导线平差',
    subtitle: '附合 / 闭合导线角度闭合差与坐标平差',
    group: ToolGroup.network,
    icon: Icons.polyline_outlined,
    keywords: ['导线', '平差', '闭合差'],
  ),
  ToolDef(
    id: 'leveling',
    title: '水准路线平差',
    subtitle: '附合 / 闭合水准高差闭合差调整与高程',
    group: ToolGroup.network,
    icon: Icons.water_outlined,
    keywords: ['水准', '高差', '高程', '平差'],
  ),
  ToolDef(
    id: 'leveling4',
    title: '四等水准测量',
    subtitle: '双面尺手簿 + 路线闭合差与高程成果',
    group: ToolGroup.network,
    icon: Icons.water_damage_outlined,
    keywords: ['四等', '水准', '双面尺', '手簿', 'K+黑-红', '视距差', '闭合差'],
  ),
  ToolDef(
    id: 'precision',
    title: '精度估算',
    subtitle: '中误差、相对误差、限差判定',
    group: ToolGroup.network,
    icon: Icons.rule,
    keywords: ['中误差', '相对误差', '限差'],
  ),

  // ── 线路与曲线 ──────────────────────────────────────────
  ToolDef(
    id: 'circular_curve',
    title: '圆曲线要素',
    subtitle: '切线长、曲线长、外距、切曲差与主点里程',
    group: ToolGroup.route,
    icon: Icons.roundabout_left_outlined,
    keywords: ['圆曲线', '切线长', '主点'],
  ),
  ToolDef(
    id: 'clothoid',
    title: '缓和曲线要素',
    subtitle: '回旋线参数、内移值、切垂距与要素计算',
    group: ToolGroup.route,
    icon: Icons.gesture,
    keywords: ['缓和曲线', '回旋线', '内移值'],
  ),
  ToolDef(
    id: 'vertical_curve',
    title: '竖曲线要素',
    subtitle: '变坡点、竖曲线长、切线与设计高程',
    group: ToolGroup.route,
    icon: Icons.show_chart,
    keywords: ['竖曲线', '纵坡', '坡度'],
  ),
  ToolDef(
    id: 'route_stake',
    title: '路线中桩坐标',
    subtitle: '直线段逐桩坐标与边桩放样',
    group: ToolGroup.route,
    icon: Icons.route_outlined,
    keywords: ['中桩', '逐桩', '里程'],
  ),

  // ── 面积与土方 ──────────────────────────────────────────
  ToolDef(
    id: 'area',
    title: '面积计算',
    subtitle: '坐标法（鞋带公式）面积、周长与亩换算',
    group: ToolGroup.earthwork,
    icon: Icons.crop_free,
    keywords: ['面积', '鞋带', '亩'],
  ),
  ToolDef(
    id: 'earthwork',
    title: '土方量计算',
    subtitle: '平均断面法与方格网法土方量',
    group: ToolGroup.earthwork,
    icon: Icons.terrain_outlined,
    keywords: ['土方', '断面', '方格网'],
  ),

  // ── 计算与换算 ──────────────────────────────────────────
  ToolDef(
    id: 'formula',
    title: '公式计算器',
    subtitle: '表达式求值、常用测量公式与变量代入',
    group: ToolGroup.formula,
    icon: Icons.functions,
    keywords: ['公式', '表达式', '计算'],
  ),
  ToolDef(
    id: 'projection',
    title: '坐标转换',
    subtitle: '高斯投影正反算（3°/6°带）与平面四参数拟合',
    group: ToolGroup.formula,
    icon: Icons.swap_horiz,
    keywords: ['高斯', '投影', '坐标转换', '四参数', '中央子午线', '带号'],
  ),
  ToolDef(
    id: 'convert',
    title: '角度与坡度换算',
    subtitle: '度分秒↔十进制、坡度百分比、方位角象限',
    group: ToolGroup.formula,
    icon: Icons.sync_alt,
    keywords: ['角度', '换算', '坡度'],
  ),
];

List<ToolDef> toolsOf(ToolGroup group) =>
    kTools.where((t) => t.group == group).toList(growable: false);

final _toolsById = {for (final tool in kTools) tool.id: tool};

ToolDef? toolById(String? id) => _toolsById[id];

final _searchFields = {
  for (final tool in kTools)
    tool: [tool.title, tool.subtitle, ...tool.keywords]
        .map((field) => field.toLowerCase())
        .toList(growable: false),
};

/// 按关键词搜索工具（标题、副标题、关键词）。
List<ToolDef> searchTools(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return kTools;
  return kTools
      .where((tool) => _searchFields[tool]!.any((field) => field.contains(q)))
      .toList(growable: false);
}
