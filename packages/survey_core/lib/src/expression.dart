import 'dart:math' as math;

import 'errors.dart';

/// 三角函数输入单位。
enum TrigUnit { degrees, radians }

/// 表达式解析 / 求值错误。
class FormulaException implements Exception, SurveyStructuredError {
  FormulaException(
    this.message, {
    this.code = SurveyErrorCode.formulaParseError,
    this.args = const <String, Object>{},
  });

  @override
  final String message;

  @override
  final SurveyErrorCode code;

  @override
  final Map<String, Object> args;

  @override
  String get defaultMessage => message;

  @override
  String toString() => message;
}

/// 轻量表达式求值器。
///
/// 支持：`+ - * / ^ ( )`、一元负号、数字、变量、函数调用与逗号分隔参数。
/// 函数：sin cos tan asin acos atan atan2 sqrt cbrt abs ln log log10 exp
///       round floor ceil min max pow hypot deg rad
/// 常量：pi e
///
/// 三角函数按 [TrigUnit] 解释输入；反三角函数（asin/acos/atan/atan2）
/// 一律返回弧度，需要度数时用 `deg(...)` 包裹。
class ExpressionEvaluator {
  ExpressionEvaluator._(this._source, this._variables, this._unit);

  final String _source;
  final Map<String, double> _variables;
  final TrigUnit _unit;

  int _pos = 0;

  /// 对 [expression] 求值。
  ///
  /// 变量名区分大小写；未定义的标识符会抛出 [FormulaException]。
  static double evaluate(
    String expression, {
    Map<String, double> variables = const {},
    TrigUnit unit = TrigUnit.degrees,
  }) {
    final src = expression.trim();
    if (src.isEmpty) return 0;
    final parser = ExpressionEvaluator._(src, variables, unit);
    final value = parser._parseExpression();
    parser._skipSpaces();
    if (parser._pos < src.length) {
      throw FormulaException(
        '第 ${parser._pos + 1} 个字符处存在无法解析的内容：“${src.substring(parser._pos)}”',
        code: SurveyErrorCode.formulaParseError,
        args: {
          'pos': parser._pos + 1,
          'trailing': src.substring(parser._pos),
        },
      );
    }
    if (value.isNaN || value.isInfinite) {
      throw FormulaException(
        '计算结果无效（$value）',
        code: SurveyErrorCode.formulaInvalidResult,
        args: {'value': value.toString()},
      );
    }
    return value;
  }

  /// 校验表达式语法（不要求变量有值，未知标识符按 0 代入）。
  static String? validate(String expression, {List<String> variables = const []}) {
    final vars = {for (final v in variables) v: 1.0};
    try {
      evaluate(expression, variables: vars);
      return null;
    } on FormulaException catch (e) {
      if (e.message.contains('未知变量')) return null;
      return e.message;
    } catch (_) {
      return null;
    }
  }

  void _skipSpaces() {
    while (_pos < _source.length && ' \t\r\n'.contains(_source[_pos])) {
      _pos++;
    }
  }

  String? _peekToken() {
    _skipSpaces();
    if (_pos >= _source.length) return null;
    return _source[_pos];
  }

  double _parseExpression() {
    var value = _parseTerm();
    while (true) {
      final t = _peekToken();
      if (t == '+') {
        _pos++;
        value += _parseTerm();
      } else if (t == '-') {
        _pos++;
        value -= _parseTerm();
      } else {
        return value;
      }
    }
  }

  double _parseTerm() {
    var value = _parseUnary();
    while (true) {
      final t = _peekToken();
      if (t == '*') {
        _pos++;
        value *= _parseUnary();
      } else if (t == '/') {
        _pos++;
        final d = _parseUnary();
        if (d == 0) {
          throw FormulaException(
            '除数为 0',
            code: SurveyErrorCode.formulaDivisionByZero,
          );
        }
        value /= d;
      } else {
        return value;
      }
    }
  }

  double _parseUnary() {
    final t = _peekToken();
    if (t == '-') {
      _pos++;
      return -_parseUnary();
    }
    if (t == '+') {
      _pos++;
      return _parseUnary();
    }
    return _parsePower();
  }

  double _parsePower() {
    final base = _parsePrimary();
    if (_peekToken() == '^') {
      _pos++;
      final exp = _parseUnary(); // 右结合
      return math.pow(base, exp).toDouble();
    }
    return base;
  }

  double _parsePrimary() {
    final t = _peekToken();
    if (t == null) {
      throw FormulaException(
        '表达式不完整',
        code: SurveyErrorCode.formulaIncomplete,
      );
    }
    if (t == '(') {
      _pos++;
      final v = _parseExpression();
      if (_peekToken() != ')') {
        throw FormulaException(
          '缺少右括号',
          code: SurveyErrorCode.formulaMissingRightParen,
        );
      }
      _pos++;
      return v;
    }
    final code = t.codeUnitAt(0);
    final isDigit = code >= 48 && code <= 57;
    if (isDigit || t == '.') return _parseNumber();
    if (_isIdentStart(t)) return _parseIdentifier();
    throw FormulaException(
      '无法识别的字符 “$t”',
      code: SurveyErrorCode.formulaUnexpectedChar,
      args: {'char': t},
    );
  }

  static bool _isIdentStart(String c) {
    final code = c.codeUnitAt(0);
    final isUpper = code >= 65 && code <= 90;
    final isLower = code >= 97 && code <= 122;
    return isUpper || isLower || c == '_';
  }

  static bool _isIdentPart(String c) {
    if (_isIdentStart(c)) return true;
    final code = c.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  double _parseNumber() {
    final start = _pos;
    var seenDot = false;
    while (_pos < _source.length) {
      final c = _source[_pos];
      if (c == '.') {
        if (seenDot) break;
        seenDot = true;
        _pos++;
      } else if (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) {
        _pos++;
      } else {
        break;
      }
    }
    final text = _source.substring(start, _pos);
    final v = double.tryParse(text);
    if (v == null) {
      throw FormulaException(
        '无效数字 “$text”',
        code: SurveyErrorCode.formulaInvalidNumber,
        args: {'text': text},
      );
    }
    return v;
  }

  double _parseIdentifier() {
    final start = _pos;
    while (_pos < _source.length && _isIdentPart(_source[_pos])) {
      _pos++;
    }
    final name = _source.substring(start, _pos);
    final lower = name.toLowerCase();
    if (_peekToken() == '(') {
      _pos++;
      final args = <double>[];
      if (_peekToken() != ')') {
        args.add(_parseExpression());
        while (_peekToken() == ',') {
          _pos++;
          args.add(_parseExpression());
        }
      }
      if (_peekToken() != ')') {
        throw FormulaException(
          '函数 $name 缺少右括号',
          code: SurveyErrorCode.formulaFunctionMissingRightParen,
          args: {'name': name},
        );
      }
      _pos++;
      return _applyFunction(lower, args, name);
    }
    switch (lower) {
      case 'pi':
        return math.pi;
      case 'e':
        return math.e;
      case 'true':
        return 1;
      case 'false':
        return 0;
    }
    final v = _variables[name] ?? _variables[lower];
    if (v == null) {
      throw FormulaException(
        '未知变量 “$name”',
        code: SurveyErrorCode.formulaUnknownVariable,
        args: {'name': name},
      );
    }
    return v;
  }

  double _toRad(double v) =>
      _unit == TrigUnit.degrees ? v * math.pi / 180.0 : v;

  double _applyFunction(String name, List<double> args, String raw) {
    double at(int i) {
      if (i >= args.length) {
        throw FormulaException(
          '函数 $raw 参数不足',
          code: SurveyErrorCode.formulaInsufficientArgs,
          args: {'name': raw},
        );
      }
      return args[i];
    }

    switch (name) {
      case 'sin':
        return math.sin(_toRad(at(0)));
      case 'cos':
        return math.cos(_toRad(at(0)));
      case 'tan':
        return math.tan(_toRad(at(0)));
      case 'asin':
        return math.asin(at(0));
      case 'acos':
        return math.acos(at(0));
      case 'atan':
        return math.atan(at(0));
      case 'atan2':
        return math.atan2(at(0), at(1));
      case 'sqrt':
        final v = at(0);
        if (v < 0) {
          throw FormulaException(
            'sqrt 的参数不能为负数',
            code: SurveyErrorCode.formulaNegativeSqrt,
          );
        }
        return math.sqrt(v);
      case 'cbrt':
        return math.pow(at(0), 1 / 3).toDouble();
      case 'abs':
        return at(0).abs();
      case 'ln':
        return math.log(at(0));
      case 'log':
      case 'log10':
        return math.log(at(0)) / math.ln10;
      case 'log2':
        return math.log(at(0)) / math.ln2;
      case 'exp':
        return math.exp(at(0));
      case 'round':
        return at(0).roundToDouble();
      case 'floor':
        return at(0).floorToDouble();
      case 'ceil':
        return at(0).ceilToDouble();
      case 'min':
        if (args.isEmpty) {
          throw FormulaException(
            '函数 $raw 参数不足',
            code: SurveyErrorCode.formulaInsufficientArgs,
            args: {'name': raw},
          );
        }
        return args.reduce(math.min);
      case 'max':
        if (args.isEmpty) {
          throw FormulaException(
            '函数 $raw 参数不足',
            code: SurveyErrorCode.formulaInsufficientArgs,
            args: {'name': raw},
          );
        }
        return args.reduce(math.max);
      case 'pow':
        return math.pow(at(0), at(1)).toDouble();
      case 'hypot':
        return math.sqrt(at(0) * at(0) + at(1) * at(1));
      case 'deg':
        return at(0) * 180 / math.pi;
      case 'rad':
        return at(0) * math.pi / 180;
      case 'norm360':
        final v = at(0) % 360;
        return v < 0 ? v + 360 : v;
      case 'norm180':
        final v = (at(0) + 180) % 360;
        return (v < 0 ? v + 360 : v) - 180;
    }
    throw FormulaException(
      '未知函数 “$raw”',
      code: SurveyErrorCode.formulaUnknownFunction,
      args: {'name': raw},
    );
  }
}
