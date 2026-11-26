import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survey_core/survey_core.dart';

import '../l10n/survey_strings.dart';
import '../theme/ui_style.dart';

/// 长度 / 坐标输入输出量级：米、厘米、毫米。
///
/// `survey_core` 内部统一按米计算；选定厘米或毫米时，界面录入按 [toMeters]
/// 自动折算为米，推算结果与坐标图按 [fromMeters] 回显对应量级。
enum LengthUnit {
  meter(
    symbol: 'm',
    label: '米',
    metersPerUnit: 1.0,
    unitsPerMeter: 1.0,
    areaSymbol: 'm²',
    volumeSymbol: 'm³',
  ),
  centimeter(
    symbol: 'cm',
    label: '厘米',
    metersPerUnit: 0.01,
    unitsPerMeter: 100.0,
    areaSymbol: 'cm²',
    volumeSymbol: 'cm³',
  ),
  millimeter(
    symbol: 'mm',
    label: '毫米',
    metersPerUnit: 0.001,
    unitsPerMeter: 1000.0,
    areaSymbol: 'mm²',
    volumeSymbol: 'mm³',
  );

  const LengthUnit({
    required this.symbol,
    required this.label,
    required this.metersPerUnit,
    required this.unitsPerMeter,
    required this.areaSymbol,
    required this.volumeSymbol,
  });

  final String symbol;
  final String label;
  final double metersPerUnit;
  final double unitsPerMeter;
  final String areaSymbol;
  final String volumeSymbol;

  double toMeters(double value) => value * metersPerUnit;
  double fromMeters(double meters) => meters * unitsPerMeter;
  double areaFromSqMeters(double sqm) => sqm * unitsPerMeter * unitsPerMeter;
  double volumeFromCubicMeters(double cum) =>
      cum * unitsPerMeter * unitsPerMeter * unitsPerMeter;

  int displayDigits(int baseCoordDigits) => switch (this) {
        LengthUnit.meter => baseCoordDigits,
        LengthUnit.centimeter => (baseCoordDigits - 1).clamp(0, 4),
        LengthUnit.millimeter => (baseCoordDigits - 2).clamp(0, 3),
      };

  static LengthUnit parse(String? raw) => switch (raw) {
        'centimeter' || 'cm' => LengthUnit.centimeter,
        'millimeter' || 'mm' => LengthUnit.millimeter,
        _ => LengthUnit.meter,
      };
}

/// 全局设置：主题、角度输入格式、长度量级、小数位与触感反馈。
class AppSettings extends ChangeNotifier {
  static const _kTheme = 'theme_mode';
  static const _kLanguage = 'app_language';
  static const _kAngle = 'angle_mode';
  static const _kLengthUnit = 'length_unit';
  static const _kCoordDigits = 'coord_digits';
  static const _kAngleDigits = 'angle_digits';
  static const _kHaptic = 'haptic';
  static const _kLastTool = 'last_tool';
  static const _kLastDraft = 'last_draft';
  static const _kSidebar = 'sidebar_collapsed';
  static const _kWorkspaceEllipsoid = 'workspace_ellipsoid';
  static const _kUiStyle = 'ui_style';
  static const _kGlassNav = 'glass_nav';
  static const _kMonet = 'monet';
  static const _kMonetSeed = 'monet_seed';
  static const _kPinnedTools = 'pinned_tools';

  static const List<String> kDefaultPinnedTools = [
    'leveling4',
    'traverse',
    'projection',
    'earthwork',
  ];

  ThemeMode _themeMode = ThemeMode.system;
  AppLanguage _language = AppLanguage.system;
  AngleInputMode _angleMode = AngleInputMode.dmsCompact;
  LengthUnit _lengthUnit = LengthUnit.meter;
  int _coordDigits = 3;
  int _angleSecDigits = 1;
  bool _haptic = true;
  String? _lastTool;
  String? _lastDraftId;
  bool _sidebarCollapsed = true;
  String _workspaceEllipsoid = 'CGCS2000';

  UiStyle _uiStyle = UiStyle.classic;

  bool? _glassNav;

  /// 是否启用莫奈取色（用种子色生成整套 tonal 调色板）。
  bool _monet = false;
  MonetSeed _monetSeed = MonetSeed.auto;
  List<String> _pinnedTools = List<String>.of(kDefaultPinnedTools);

  ThemeMode get themeMode => _themeMode;
  AppLanguage get language => _language;
  AngleInputMode get angleMode => _angleMode;

  /// 角度输入方式的中文标签，供界面直接显示。
  String get angleModeLabel => switch (_angleMode) {
        AngleInputMode.dmsCompact => '度分秒 (度/分/秒)',
        AngleInputMode.decimalDegrees => '十进制度',
        AngleInputMode.radians => '弧度',
      };

  /// 角度输入方式的短标签（胶囊/徽标用，避免窄屏被长标签撑爆）。
  String get angleModeShortLabel => switch (_angleMode) {
        AngleInputMode.dmsCompact => '度分秒',
        AngleInputMode.decimalDegrees => '十进制',
        AngleInputMode.radians => '弧度',
      };

  /// 当前长度/坐标输入量级。
  LengthUnit get lengthUnit => _lengthUnit;
  String get lengthUnitLabel => '${_lengthUnit.label} (${_lengthUnit.symbol})';
  String get lengthUnitShortLabel =>
      '${_lengthUnit.label} ${_lengthUnit.symbol}';

  /// 坐标与长度的显示小数位。
  int get coordDigits => _coordDigits;

  /// 角度秒的显示小数位。
  int get angleSecDigits => _angleSecDigits;

  bool get haptic => _haptic;
  String? get lastTool => _lastTool;
  String? get lastDraftId => _lastDraftId;
  bool get sidebarCollapsed => _sidebarCollapsed;
  String get workspaceEllipsoid => _workspaceEllipsoid;

  /// 当前界面风格。
  UiStyle get uiStyle => _uiStyle;

  /// 宽屏侧栏默认使用实色，窄屏默认使用悬浮液态玻璃。
  bool get glassNav => _glassNav ?? false;
  bool get floatingGlassNav => _glassNav ?? true;

  /// 莫奈取色开关与种子来源。
  bool get monet => _monet;
  MonetSeed get monetSeed => _monetSeed;

  /// 首页「常用工具」固定列表。
  List<String> get pinnedTools => List.unmodifiable(_pinnedTools);
  List<String> get pinnedToolIds => pinnedTools;
  bool isPinned(String toolId) => _pinnedTools.contains(toolId);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final t = p.getString(_kTheme);
    _language = AppLanguage.fromPreference(p.getString(_kLanguage));
    _themeMode = switch (t) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.system,
    };
    _angleMode = switch (p.getString(_kAngle)) {
      'decimal' => AngleInputMode.decimalDegrees,
      'rad' => AngleInputMode.radians,
      _ => AngleInputMode.dmsCompact,
    };
    _lengthUnit = LengthUnit.parse(p.getString(_kLengthUnit));
    _coordDigits = p.getInt(_kCoordDigits) ?? 3;
    _angleSecDigits = p.getInt(_kAngleDigits) ?? 1;
    _haptic = p.getBool(_kHaptic) ?? true;
    _lastTool = p.getString(_kLastTool);
    _lastDraftId = p.getString(_kLastDraft);
    _sidebarCollapsed = p.getBool(_kSidebar) ?? true;
    _workspaceEllipsoid = p.getString(_kWorkspaceEllipsoid) ?? 'CGCS2000';
    _uiStyle = UiStyle.parse(p.getString(_kUiStyle));
    _glassNav = p.getBool(_kGlassNav);
    _monet = p.getBool(_kMonet) ?? false;
    _monetSeed = MonetSeed.parse(p.getString(_kMonetSeed));
    final pinned = p.getStringList(_kPinnedTools);
    if (pinned != null && pinned.isNotEmpty) {
      _pinnedTools = List<String>.of(pinned);
    }
    notifyListeners();
  }

  Future<void> _persist(Future<void> Function(SharedPreferences) fn) async {
    final p = await SharedPreferences.getInstance();
    await fn(p);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _persist((p) => p.setString(_kTheme, mode.name));
  }

  Future<void> setAngleMode(AngleInputMode mode) async {
    if (_angleMode == mode) return;
    _angleMode = mode;
    notifyListeners();
    await _persist(
      (p) => p.setString(
        _kAngle,
        switch (mode) {
          AngleInputMode.dmsCompact => 'dms',
          AngleInputMode.decimalDegrees => 'decimal',
          AngleInputMode.radians => 'rad',
        },
      ),
    );
  }

  Future<void> setLengthUnit(LengthUnit unit) async {
    if (_lengthUnit == unit) return;
    _lengthUnit = unit;
    notifyListeners();
    await _persist((p) => p.setString(_kLengthUnit, unit.symbol));
  }

  Future<void> setCoordDigits(int digits) async {
    if (_coordDigits == digits) return;
    _coordDigits = digits.clamp(0, 6);
    notifyListeners();
    await _persist((p) => p.setInt(_kCoordDigits, _coordDigits));
  }

  Future<void> setAngleSecDigits(int digits) async {
    if (_angleSecDigits == digits) return;
    _angleSecDigits = digits.clamp(0, 3);
    notifyListeners();
    await _persist((p) => p.setInt(_kAngleDigits, _angleSecDigits));
  }

  Future<void> setHaptic(bool value) async {
    if (_haptic == value) return;
    _haptic = value;
    notifyListeners();
    await _persist((p) => p.setBool(_kHaptic, value));
  }

  Future<void> setUiStyle(UiStyle style) async {
    if (_uiStyle == style) return;
    _uiStyle = style;
    notifyListeners();
    await _persist((p) => p.setString(_kUiStyle, style.name));
  }

  Future<void> setLanguage(AppLanguage value) async {
    if (_language == value) return;
    _language = value;
    notifyListeners();
    await _persist((p) => p.setString(_kLanguage, value.name));
  }

  Future<void> setGlassNav(bool value) async {
    if (_glassNav == value) return;
    _glassNav = value;
    notifyListeners();
    await _persist((p) => p.setBool(_kGlassNav, value));
  }

  Future<void> setMonet(bool value) async {
    if (_monet == value) return;
    _monet = value;
    notifyListeners();
    await _persist((p) => p.setBool(_kMonet, value));
  }

  Future<void> setMonetSeed(MonetSeed seed) async {
    if (_monetSeed == seed) return;
    _monetSeed = seed;
    notifyListeners();
    await _persist((p) => p.setString(_kMonetSeed, seed.name));
  }

  Future<void> setLastTool(String key, {String? draftId}) async {
    _lastTool = key;
    _lastDraftId = draftId;
    notifyListeners();
    await _persist((p) async {
      await p.setString(_kLastTool, key);
      if (draftId == null) {
        await p.remove(_kLastDraft);
      } else {
        await p.setString(_kLastDraft, draftId);
      }
    });
  }

  Future<void> setSidebarCollapsed(bool collapsed) async {
    _sidebarCollapsed = collapsed;
    notifyListeners();
    await _persist((p) => p.setBool(_kSidebar, collapsed));
  }

  Future<void> setWorkspaceEllipsoid(String ellipsoid) async {
    if (_workspaceEllipsoid == ellipsoid) return;
    _workspaceEllipsoid = ellipsoid;
    notifyListeners();
    await _persist((p) => p.setString(_kWorkspaceEllipsoid, ellipsoid));
  }

  /// 切换首页「常用工具」固定状态（至少保留 1 个工具）。
  Future<bool> togglePinnedTool(String toolId) async {
    if (_pinnedTools.contains(toolId)) {
      if (_pinnedTools.length <= 1) return false;
      _pinnedTools.remove(toolId);
    } else {
      _pinnedTools.add(toolId);
    }
    notifyListeners();
    await _persist((p) => p.setStringList(_kPinnedTools, _pinnedTools));
    return true;
  }

  /// 更新「常用工具」选中集合与排序（至少保留 1 个工具）。
  Future<void> setPinnedToolIds(List<String> ids) async {
    final next = <String>[];
    for (final id in ids) {
      if (id.isNotEmpty && !next.contains(id)) next.add(id);
    }
    if (next.isEmpty) return;
    _pinnedTools = next;
    notifyListeners();
    await _persist((p) => p.setStringList(_kPinnedTools, _pinnedTools));
  }

  /// 恢复默认「常用工具」列表。
  Future<void> resetPinnedTools() async {
    _pinnedTools = List<String>.of(kDefaultPinnedTools);
    notifyListeners();
    await _persist((p) => p.setStringList(_kPinnedTools, _pinnedTools));
  }

  /// 恢复默认录入与显示参数（米制 · 度分秒 · 坐标 3 位 · 秒 1 位）。
  Future<void> resetInputDefaults() async {
    _angleMode = AngleInputMode.dmsCompact;
    _lengthUnit = LengthUnit.meter;
    _coordDigits = 3;
    _angleSecDigits = 1;
    notifyListeners();
    await _persist((p) async {
      await p.setString(_kAngle, 'dms');
      await p.setString(_kLengthUnit, LengthUnit.meter.symbol);
      await p.setInt(_kCoordDigits, _coordDigits);
      await p.setInt(_kAngleDigits, _angleSecDigits);
    });
  }
}

/// 把 [AppSettings] 注入 widget 树。
class SettingsScope extends InheritedNotifier<AppSettings> {
  const SettingsScope({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AppSettings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'SettingsScope 未挂载');
    return scope!.notifier!;
  }

  /// 不订阅变更（放在 initState / 回调里用）。
  static AppSettings read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'SettingsScope 未挂载');
    return scope!.notifier!;
  }
}
