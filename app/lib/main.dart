import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_info.dart';
import 'l10n/survey_strings.dart';
import 'platform/native_bridge_contract.dart';
import 'state/control_points.dart';
import 'state/drafts.dart';
import 'state/live_plot_controller.dart';
import 'state/settings.dart';
import 'theme/app_theme.dart';
import 'theme/compact_workspace_theme.dart';
import 'theme/monet.dart';
import 'theme/tokens.dart';
import 'theme/ui_style.dart';
import 'ui/shell.dart';
import 'ui/widgets/startup_reveal.dart';
import 'ui/widgets/workspace_commands.dart';

/// 允许 Windows 鼠标左键拖拽横向表格/手簿（与触屏行为一致）。
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final (name, licenseFile) in [
      ('Noto Sans SC', 'NotoSansSC-OFL.txt'),
      ('JetBrains Mono', 'JetBrainsMono-OFL.txt'),
    ]) {
      final license =
          await rootBundle.loadString('assets/fonts/survey/$licenseFile');
      yield LicenseEntryWithLineBreaks([name], license);
    }
  });
  final settings = AppSettings();
  await settings.load();
  final drafts = DraftStore();
  final controlPoints = ControlPointStore();
  final livePlot = LivePlotController();
  runApp(SurveyApp(
    settings: settings,
    drafts: drafts,
    controlPoints: controlPoints,
    livePlot: livePlot,
    coldStart: Future.wait<void>([drafts.load(), controlPoints.load()]),
  ));
}

class SurveyApp extends StatefulWidget {
  const SurveyApp({
    super.key,
    required this.settings,
    required this.drafts,
    this.controlPoints,
    this.livePlot,
    this.coldStart,
  });

  final AppSettings settings;
  final DraftStore drafts;
  final ControlPointStore? controlPoints;
  final LivePlotController? livePlot;
  final Future<void>? coldStart;

  @override
  State<SurveyApp> createState() => _SurveyAppState();
}

class _SurveyAppState extends State<SurveyApp> with WidgetsBindingObserver {
  /// Android 12+ / Windows 的系统强调色；取不到时为 null。
  Color? _systemAccent;
  bool? _lastWindowDark;
  late (ThemeMode, UiStyle, bool, MonetSeed, AppLanguage) _appearance;
  (ThemeMode, UiStyle, bool, MonetSeed, AppLanguage) get _currentAppearance {
    final settings = widget.settings;
    return (
      settings.themeMode,
      settings.uiStyle,
      settings.monet,
      settings.monetSeed,
      settings.language
    );
  }

  late final AppLifecycleListener _lifecycle;
  late final ControlPointStore _controlPoints =
      widget.controlPoints ?? ControlPointStore();
  late final LivePlotController _livePlot =
      widget.livePlot ?? LivePlotController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.controlPoints == null) {
      unawaited(_controlPoints.load());
    }
    _lifecycle = AppLifecycleListener(
      onInactive: () => unawaited(widget.drafts.flushAll()),
      onHide: () => unawaited(widget.drafts.flushAll()),
      onPause: () => unawaited(widget.drafts.flushAll()),
      onDetach: () => unawaited(widget.drafts.flushAll()),
      onExitRequested: () async {
        await widget.drafts.flushAll();
        return AppExitResponse.exit;
      },
    );
    _appearance = _currentAppearance;
    widget.settings.addListener(_onSettingsChanged);
    unawaited(NativeWindowBridge.setStartupTheme(_appearance.$1.name));
    _syncAccent();
    _syncWindowBrightness();
    unawaited(NativeWindowBridge.setWindowTitle(kAppName));
  }

  @override
  void didUpdateWidget(covariant SurveyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings == widget.settings) return;
    oldWidget.settings.removeListener(_onSettingsChanged);
    widget.settings.addListener(_onSettingsChanged);
    _onSettingsChanged();
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    _lifecycle.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controlPoints == null) _controlPoints.dispose();
    if (widget.livePlot == null) _livePlot.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    _syncWindowBrightness();
  }

  void _onSettingsChanged() {
    final next = _currentAppearance;
    if (_appearance == next) return;
    final themeChanged = _appearance.$1 != next.$1;
    final accentChanged =
        _appearance.$3 != next.$3 || _appearance.$4 != next.$4;
    setState(() => _appearance = next);
    if (themeChanged) {
      unawaited(NativeWindowBridge.setStartupTheme(next.$1.name));
    }
    if (accentChanged) _syncAccent();
    _syncWindowBrightness();
  }

  void _syncWindowBrightness() {
    final mode = widget.settings.themeMode;
    final isDark = switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        PlatformDispatcher.instance.platformBrightness == Brightness.dark,
    };
    if (_lastWindowDark == isDark) return;
    _lastWindowDark = isDark;
    unawaited(Monet.setWindowBrightness(isDark));
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: const Color(0x00000000),
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Color(isDark ? 0xFF000000 : 0xFFF2F2F7),
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ));
  }

  /// 开了莫奈且种子选「自动」时，去读一次系统强调色；其余情况不用读。
  Future<void> _syncAccent() async {
    final s = widget.settings;
    final wantSystem = s.monet && s.monetSeed == MonetSeed.auto;
    if (!wantSystem) {
      if (_systemAccent != null) setState(() => _systemAccent = null);
      return;
    }
    final accent = await Monet.systemAccent();
    if (!mounted || accent == _systemAccent) return;
    setState(() => _systemAccent = accent);
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final style = settings.uiStyle;
    final seed = settings.monet
        ? Monet.resolveSeed(settings.monetSeed, _systemAccent)
        : kSeed;
    return DraftScope(
      store: widget.drafts,
      child: ControlPointScope(
        store: _controlPoints,
        child: LivePlotScope(
          controller: _livePlot,
          child: SettingsScope(
            settings: settings,
            child: MaterialApp(
              title: kAppName,
              debugShowCheckedModeBanner: false,
              scrollBehavior: const _AppScrollBehavior(),
              theme: workspaceTheme(
                  buildAppTheme(Brightness.light, seed: seed, style: style)),
              darkTheme: workspaceTheme(
                  buildAppTheme(Brightness.dark, seed: seed, style: style)),
              themeMode: settings.themeMode,
              locale: settings.language.locale,
              localeListResolutionCallback: (locales, _) =>
                  AppLanguage.resolve(locales),
              supportedLocales: AppLanguage.supportedLocales,
              localizationsDelegates: SurveyStrings.delegates,
              home: const AppShell(),
              builder: (context, child) {
                // 统一限制系统字体缩放范围（0.85x–1.35x），兼顾高/低 DPI 与字号缩放，同时避免极端字号挤坏版式。
                final mq = MediaQuery.of(context);
                return MediaQuery(
                  data: mq.copyWith(
                    textScaler: mq.textScaler.clamp(
                      minScaleFactor: 0.85,
                      maxScaleFactor: 1.35,
                    ),
                  ),
                  child: DefaultTextHeightBehavior(
                    textHeightBehavior: kSurveyTextHeightBehavior,
                    child: WorkspaceCommandsEnabled(
                      child: widget.coldStart == null
                          ? child ?? const SizedBox.shrink()
                          : StartupReveal(
                              ready: widget.coldStart!,
                              skip: settings.skipStartupAnimation,
                              child: child ?? const SizedBox.shrink(),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
