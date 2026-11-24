import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'state/drafts.dart';
import 'state/settings.dart';
import 'theme/app_theme.dart';
import 'theme/monet.dart';
import 'theme/ui_style.dart';
import 'ui/shell.dart';

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
  await drafts.load();
  runApp(SurveyApp(settings: settings, drafts: drafts));
}

class SurveyApp extends StatefulWidget {
  const SurveyApp({super.key, required this.settings, required this.drafts});

  final AppSettings settings;
  final DraftStore drafts;

  @override
  State<SurveyApp> createState() => _SurveyAppState();
}

class _SurveyAppState extends State<SurveyApp> with WidgetsBindingObserver {
  /// Android 12+ / Windows 的系统强调色；取不到时为 null。
  Color? _systemAccent;
  bool? _lastWindowDark;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    widget.settings.addListener(_onSettingsChanged);
    _syncAccent();
    _syncWindowBrightness();
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    _lifecycle.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    _syncWindowBrightness();
  }

  void _onSettingsChanged() {
    _syncAccent();
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
    return DraftScope(
      store: widget.drafts,
      child: SettingsScope(
        settings: settings,
        child: AnimatedBuilder(
          animation: settings,
          builder: (context, _) {
            final style = settings.uiStyle;
            final seed = settings.monet
                ? Monet.resolveSeed(settings.monetSeed, _systemAccent)
                : kSeed;
            return MaterialApp(
              title: '工程测量',
              debugShowCheckedModeBanner: false,
              scrollBehavior: const _AppScrollBehavior(),
              theme: buildAppTheme(Brightness.light, seed: seed, style: style),
              darkTheme:
                  buildAppTheme(Brightness.dark, seed: seed, style: style),
              themeMode: settings.themeMode,
              // Material 内置控件（复制/粘贴、返回提示、日期选择等）用简体中文，
              // 避免中文界面里混入英文系统文案。
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const AppShell(),
              builder: (context, child) {
                // 统一限制系统字体缩放上限，避免超大字号把测量结果挤坏版式。
                final mq = MediaQuery.of(context);
                return MediaQuery(
                  data: mq.copyWith(
                    textScaler: mq.textScaler.clamp(
                      minScaleFactor: 0.9,
                      maxScaleFactor: 1.3,
                    ),
                  ),
                  child: child ?? const SizedBox.shrink(),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
