/// 公式库中的一个输入变量。
class FormulaVarSpec {
  const FormulaVarSpec({
    required this.key,
    required this.label,
    this.unit,
    this.defaultValue,
    this.hint,
  });

  /// 表达式中使用的标识符。
  final String key;

  /// 界面上显示的中文名称。
  final String label;
  final String? unit;
  final double? defaultValue;
  final String? hint;
}

/// 内置公式定义。
class FormulaDef {
  const FormulaDef({
    required this.id,
    required this.name,
    required this.category,
    required this.expression,
    required this.variables,
    this.resultUnit,
    this.resultDigits = 4,
    this.description,
  });

  final String id;
  final String name;
  final String category;

  /// 可直接求值的表达式。
  final String expression;
  final List<FormulaVarSpec> variables;
  final String? resultUnit;
  final int resultDigits;
  final String? description;
}

/// 工程测量常用公式库。
const List<FormulaDef> kFormulaLibrary = [
  FormulaDef(
    id: 'dms_to_deg',
    name: '度分秒 → 十进制度',
    category: '角度换算',
    expression: 'd + m/60 + s/3600',
    resultUnit: '°',
    resultDigits: 6,
    variables: [
      FormulaVarSpec(key: 'd', label: '度', unit: '°', defaultValue: 0),
      FormulaVarSpec(key: 'm', label: '分', unit: '′', defaultValue: 0),
      FormulaVarSpec(key: 's', label: '秒', unit: '″', defaultValue: 0),
    ],
  ),
  FormulaDef(
    id: 'distance',
    name: '两点间水平距离',
    category: '坐标计算',
    expression: 'sqrt((x2-x1)^2 + (y2-y1)^2)',
    resultUnit: 'm',
    resultDigits: 3,
    variables: [
      FormulaVarSpec(key: 'x1', label: '起点 X', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'y1', label: '起点 Y', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'x2', label: '终点 X', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'y2', label: '终点 Y', unit: 'm', defaultValue: 0),
    ],
  ),
  FormulaDef(
    id: 'azimuth',
    name: '坐标方位角',
    category: '坐标计算',
    expression: 'norm360(deg(atan2(y2-y1, x2-x1)))',
    resultUnit: '°',
    resultDigits: 6,
    description: 'x 为纵轴（北），y 为横轴（东），方位角自北方向顺时针起算。',
    variables: [
      FormulaVarSpec(key: 'x1', label: '起点 X', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'y1', label: '起点 Y', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'x2', label: '终点 X', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'y2', label: '终点 Y', unit: 'm', defaultValue: 0),
    ],
  ),
  FormulaDef(
    id: 'coord_x',
    name: '坐标正算 X',
    category: '坐标计算',
    expression: 'x0 + D*cos(A)',
    resultUnit: 'm',
    resultDigits: 3,
    variables: [
      FormulaVarSpec(key: 'x0', label: '已知 X', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'D', label: '水平距离', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'A', label: '方位角', unit: '°', defaultValue: 0),
    ],
  ),
  FormulaDef(
    id: 'coord_y',
    name: '坐标正算 Y',
    category: '坐标计算',
    expression: 'y0 + D*sin(A)',
    resultUnit: 'm',
    resultDigits: 3,
    variables: [
      FormulaVarSpec(key: 'y0', label: '已知 Y', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'D', label: '水平距离', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'A', label: '方位角', unit: '°', defaultValue: 0),
    ],
  ),
  FormulaDef(
    id: 'stadia_distance',
    name: '视距测量水平距离',
    category: '碎部测量',
    expression: 'k*l*cos(a)^2',
    resultUnit: 'm',
    resultDigits: 3,
    description: 'k 为视距乘常数（通常 100），l 为上下丝读数差，a 为竖直角。',
    variables: [
      FormulaVarSpec(key: 'k', label: '视距乘常数 k', defaultValue: 100),
      FormulaVarSpec(key: 'l', label: '视距间隔 l', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'a', label: '竖直角 α', unit: '°', defaultValue: 0),
    ],
  ),
  FormulaDef(
    id: 'trig_leveling',
    name: '三角高程高差',
    category: '高程测量',
    expression: 'D*tan(a) + i - v',
    resultUnit: 'm',
    resultDigits: 3,
    description: 'D 为平距，i 为仪器高，v 为觇标（棱镜）高。',
    variables: [
      FormulaVarSpec(key: 'D', label: '水平距离', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'a', label: '竖直角 α', unit: '°', defaultValue: 0),
      FormulaVarSpec(key: 'i', label: '仪器高', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'v', label: '棱镜高', unit: 'm', defaultValue: 0),
    ],
  ),
  FormulaDef(
    id: 'slope_percent',
    name: '坡度（百分比）',
    category: '高程测量',
    expression: 'h/D*100',
    resultUnit: '%',
    resultDigits: 3,
    variables: [
      FormulaVarSpec(key: 'h', label: '高差', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'D', label: '水平距离', unit: 'm', defaultValue: 0),
    ],
  ),
  FormulaDef(
    id: 'slope_angle',
    name: '坡度百分比 → 倾角',
    category: '高程测量',
    expression: 'deg(atan(i/100))',
    resultUnit: '°',
    resultDigits: 5,
    variables: [
      FormulaVarSpec(key: 'i', label: '坡度', unit: '%', defaultValue: 0),
    ],
  ),
  FormulaDef(
    id: 'circle_tangent',
    name: '圆曲线切线长',
    category: '线路曲线',
    expression: 'R*tan(A/2)',
    resultUnit: 'm',
    resultDigits: 3,
    variables: [
      FormulaVarSpec(key: 'R', label: '半径 R', unit: 'm', defaultValue: 300),
      FormulaVarSpec(key: 'A', label: '转角 α', unit: '°', defaultValue: 30),
    ],
  ),
  FormulaDef(
    id: 'circle_length',
    name: '圆曲线长',
    category: '线路曲线',
    expression: 'R*A*pi/180',
    resultUnit: 'm',
    resultDigits: 3,
    variables: [
      FormulaVarSpec(key: 'R', label: '半径 R', unit: 'm', defaultValue: 300),
      FormulaVarSpec(key: 'A', label: '转角 α', unit: '°', defaultValue: 30),
    ],
  ),
  FormulaDef(
    id: 'circle_external',
    name: '圆曲线外距',
    category: '线路曲线',
    expression: 'R*(1/cos(A/2)-1)',
    resultUnit: 'm',
    resultDigits: 3,
    variables: [
      FormulaVarSpec(key: 'R', label: '半径 R', unit: 'm', defaultValue: 300),
      FormulaVarSpec(key: 'A', label: '转角 α', unit: '°', defaultValue: 30),
    ],
  ),
  FormulaDef(
    id: 'clothoid_shift',
    name: '缓和曲线内移值 p',
    category: '线路曲线',
    expression: 'ls^2/(24*R) - ls^4/(2688*R^3)',
    resultUnit: 'm',
    resultDigits: 5,
    variables: [
      FormulaVarSpec(key: 'R', label: '半径 R', unit: 'm', defaultValue: 300),
      FormulaVarSpec(key: 'ls', label: '缓和曲线长 ls', unit: 'm', defaultValue: 60),
    ],
  ),
  FormulaDef(
    id: 'vertical_tangent',
    name: '竖曲线切线长',
    category: '线路曲线',
    expression: 'R*abs(i2-i1)/2',
    resultUnit: 'm',
    resultDigits: 3,
    description: 'i1、i2 为相邻坡段的坡度（小数形式，0.03 表示 3%）。',
    variables: [
      FormulaVarSpec(key: 'R', label: '竖曲线半径 R', unit: 'm', defaultValue: 5000),
      FormulaVarSpec(key: 'i1', label: '前坡 i₁', defaultValue: 0.02),
      FormulaVarSpec(key: 'i2', label: '后坡 i₂', defaultValue: -0.015),
    ],
  ),
  FormulaDef(
    id: 'level_correction',
    name: '水准改正数分配',
    category: '平差',
    expression: '-fh*L/sumL',
    resultUnit: 'mm',
    resultDigits: 3,
    variables: [
      FormulaVarSpec(key: 'fh', label: '闭合差 fh', unit: 'mm', defaultValue: 0),
      FormulaVarSpec(key: 'L', label: '本段距离', unit: 'km', defaultValue: 1),
      FormulaVarSpec(key: 'sumL', label: '路线总长', unit: 'km', defaultValue: 1),
    ],
  ),
  FormulaDef(
    id: 'error_propagation',
    name: '误差传播 m = √(a²+b²)',
    category: '精度',
    expression: 'sqrt(a^2 + b^2)',
    resultUnit: 'mm',
    resultDigits: 3,
    variables: [
      FormulaVarSpec(key: 'a', label: '中误差 a', unit: 'mm', defaultValue: 0),
      FormulaVarSpec(key: 'b', label: '中误差 b', unit: 'mm', defaultValue: 0),
    ],
  ),
  FormulaDef(
    id: 'relative_error',
    name: '相对误差分母',
    category: '精度',
    expression: 'S/f',
    resultUnit: '1/K',
    resultDigits: 0,
    description: 'S 为边长 / 路线长，f 为闭合差（同单位）。结果表示 1/K。',
    variables: [
      FormulaVarSpec(key: 'S', label: '总长 S', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'f', label: '闭合差 f', unit: 'm', defaultValue: 0),
    ],
  ),
  FormulaDef(
    id: 'area_trapezoid',
    name: '梯形面积',
    category: '几何',
    expression: '(a+b)*h/2',
    resultUnit: 'm²',
    resultDigits: 3,
    variables: [
      FormulaVarSpec(key: 'a', label: '上底 a', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'b', label: '下底 b', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'h', label: '高 h', unit: 'm', defaultValue: 0),
    ],
  ),
  FormulaDef(
    id: 'sector_area',
    name: '扇形面积',
    category: '几何',
    expression: 'pi*R^2*A/360',
    resultUnit: 'm²',
    resultDigits: 3,
    variables: [
      FormulaVarSpec(key: 'R', label: '半径 R', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'A', label: '圆心角', unit: '°', defaultValue: 0),
    ],
  ),
  FormulaDef(
    id: 'arc_length',
    name: '圆弧长',
    category: '几何',
    expression: 'R*A*pi/180',
    resultUnit: 'm',
    resultDigits: 3,
    variables: [
      FormulaVarSpec(key: 'R', label: '半径 R', unit: 'm', defaultValue: 0),
      FormulaVarSpec(key: 'A', label: '圆心角', unit: '°', defaultValue: 0),
    ],
  ),
];

List<String> formulaCategories() {
  final seen = <String>[];
  for (final f in kFormulaLibrary) {
    if (!seen.contains(f.category)) seen.add(f.category);
  }
  return seen;
}
