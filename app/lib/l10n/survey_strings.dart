import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'messages.dart';
import 'survey_terms.dart';
import 'tool_messages_en.dart';

enum AppLanguage {
  chinese('中文（简体）', Locale('zh', 'CN')),
  english('English', Locale('en')),
  shona('ChiShona', Locale('sn', 'ZW')),
  ndebele('isiNdebele', Locale('nd', 'ZW')),
  french('Français', Locale('fr')),
  portuguese('Português', Locale('pt')),
  spanish('Español', Locale('es')),
  system(null, null);

  const AppLanguage(this.nativeName, this.locale);

  final String? nativeName;
  final Locale? locale;

  static final supportedLocales = [
    for (final language in values)
      if (language.locale case final locale?) locale,
  ];

  static AppLanguage fromPreference(String? value) {
    for (final language in values) {
      if (language.name == value) return language;
    }
    return system;
  }

  static Locale resolve(List<Locale>? preferences) {
    for (final preferred in preferences ?? const <Locale>[]) {
      for (final supported in supportedLocales) {
        if (supported.languageCode == preferred.languageCode) return supported;
      }
    }
    return english.locale!;
  }
}

/// Text belonging to the app. Framework controls fall back to UK English for
/// Zimbabwean languages absent from Flutter's framework translations.
class SurveyStrings {
  const SurveyStrings(this.languageCode);

  final String languageCode;

  static const delegates = <LocalizationsDelegate<dynamic>>[
    _SurveyStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    _ZimbabweFrameworkFallback<MaterialLocalizations>(
      GlobalMaterialLocalizations.delegate,
    ),
    _ZimbabweFrameworkFallback<WidgetsLocalizations>(
      GlobalWidgetsLocalizations.delegate,
    ),
    _ZimbabweFrameworkFallback<CupertinoLocalizations>(
      GlobalCupertinoLocalizations.delegate,
    ),
  ];

  static SurveyStrings of(BuildContext context) =>
      Localizations.of<SurveyStrings>(context, SurveyStrings) ??
      const SurveyStrings('zh');

  String translate(String source, [Map<String, Object> arguments = const {}]) {
    final message = languageCode == 'zh'
        ? source
        : regionalMessages[languageCode]?[source] ??
            localizedSurveyTerm(languageCode, source) ??
            englishMessages[source] ??
            toolEnglishMessages[source] ??
            _translateDynamic(source);
    if (arguments.isEmpty) return message;
    return message.replaceAllMapped(
      _argument,
      (match) => arguments[match[1]]?.toString() ?? match[0]!,
    );
  }

  String _translateDynamic(String source) {
    if (source.startsWith('已保存 ')) {
      return 'Saved ${source.substring(4)}';
    }
    if (source.startsWith('占用 ') && source.endsWith('%')) {
      return '${source.substring(3)} used';
    }
    if (source.startsWith('超限 ') && source.endsWith('%')) {
      return '${source.substring(3)} over';
    }
    if (source.startsWith('限差 ')) {
      return 'Limit ${source.substring(3)}';
    }
    if (source.startsWith('限值 ')) {
      return 'Limit ${source.substring(3)}';
    }
    if (source.startsWith('教程 · ')) {
      final rest = source.substring(5);
      return 'Guide · ${translate(rest)}';
    }
    if (source.startsWith('X(北) ') && source.contains(' · Y(东) ')) {
      return source
          .replaceFirst('X(北) ', 'X(N) ')
          .replaceFirst(' · Y(东) ', ' · Y(E) ');
    }
    if (source.startsWith('判定：')) {
      return source
          .replaceFirst('判定：', 'Mode: ')
          .replaceAll('内角和', 'Interior angles')
          .replaceAll('外角和', 'Exterior angles')
          .replaceAll('自动', 'Auto');
    }
    if (source.contains('推算，角度闭合差按角数平均改正，坐标闭合差')) {
      final angle = source.startsWith('按左角') ? 'left angles' : 'right angles';
      final dist = source.contains('按边长') ? 'by side length' : 'by ΔX/ΔY';
      return 'Computed via $angle; angular misclosure distributed equally, coordinate misclosure $dist';
    }
    final limitDesc = RegExp(r'^按限差 (±\d+″√n) 判定测角精度等级$').firstMatch(source);
    if (limitDesc != null) {
      return 'Check angular misclosure against ${limitDesc.group(1)}';
    }
    if (source.startsWith('+ 新增')) {
      return '+ Add ${translate(source.substring(2))}';
    }
    if (source.startsWith('新增')) {
      return 'Add ${translate(source.substring(2))}';
    }
    return source;
  }

  static final _argument = RegExp(r'\{(\w+)\}');
}

class _SurveyStringsDelegate extends LocalizationsDelegate<SurveyStrings> {
  const _SurveyStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLanguage.supportedLocales.contains(locale);

  @override
  Future<SurveyStrings> load(Locale locale) =>
      SynchronousFuture(SurveyStrings(locale.languageCode));

  @override
  bool shouldReload(_SurveyStringsDelegate old) => false;
}

class _ZimbabweFrameworkFallback<T> extends LocalizationsDelegate<T> {
  const _ZimbabweFrameworkFallback(this.delegate);
  final LocalizationsDelegate<T> delegate;

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'sn' || locale.languageCode == 'nd';

  @override
  Future<T> load(Locale locale) => delegate.load(const Locale('en', 'GB'));

  @override
  bool shouldReload(_ZimbabweFrameworkFallback<T> old) => false;
}

extension TranslatedContext on BuildContext {
  String tr(String source, [Map<String, Object> arguments = const {}]) =>
      SurveyStrings.of(this).translate(source, arguments);
}

/// Allows static text to keep a const widget tree while the locale changes.
class LocalText extends StatelessWidget {
  const LocalText(this.source,
      {super.key, this.style, this.maxLines, this.overflow});

  final String source;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => Text(context.tr(source),
      style: style, maxLines: maxLines, overflow: overflow);
}
