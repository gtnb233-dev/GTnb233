/// Structured error codes emitted by `survey_core` for UI localization.
enum SurveyErrorCode {
  // angle.dart
  angleEmpty,
  angleTooManyParts,
  angleInvalidFormat,

  // curve.dart
  curveRadiusInvalid,
  curveAngleInvalid,
  curveTransitionInvalid,
  curveValueNotFinite,

  // expression.dart
  formulaParseError,
  formulaInvalidResult,
  formulaDivisionByZero,
  formulaIncomplete,
  formulaMissingRightParen,
  formulaUnexpectedChar,
  formulaInvalidNumber,
  formulaFunctionMissingRightParen,
  formulaUnknownVariable,
  formulaInsufficientArgs,
  formulaNegativeSqrt,
  formulaUnknownFunction,

  // leveling.dart
  levelingLengthInvalid,
  levelingStationCountNegative,
  levelingLengthOrStationRequired,
  levelingBackConstantExceeded,
  levelingFrontConstantExceeded,
  levelingDistanceDiffExceeded,
  levelingCumulativeDiffExceeded,
  levelingSightLengthExceeded,
  levelingHeightDiffExceeded,
  levelingSightHeightTooLow,

  // projection.dart
  projectionLonOutOfRange,
  projectionZoneWidthInvalid,
  projectionLatOutOfRange,
  projectionGaussLatOutOfRange,
  projectionCoordNotFinite,
  projectionInverseLatOutOfRange,

  // geodesy.dart
  geodesyLatOutOfRange,
  geodesyLonOutOfRange,
  geodesyHeightNotFinite,
  geodesyEcefNotFinite,

  // intersection.dart
  intersectionPointsCoincident,
  intersectionDistanceNonPositive,
  intersectionCirclesNoOverlapSum,
  intersectionCirclesNoOverlapDiff,

  // format.dart
  toleranceExceeded,

  // traverse.dart
  traverseAngleMisclosureExceeded,
  traverseLinearMisclosureExceeded,
}

/// Structured error payload carrying a stable [code], template [args], and
/// Chinese [defaultMessage].
class SurveyStructuredError implements Exception {
  const SurveyStructuredError(
    this.code,
    this.defaultMessage, [
    this.args = const <String, Object>{},
  ]);

  final SurveyErrorCode code;
  final Map<String, Object> args;
  final String defaultMessage;

  String get message => defaultMessage;

  @override
  String toString() => defaultMessage;
}

/// [FormatException] carrying [SurveyStructuredError] metadata.
class SurveyFormatException extends FormatException
    implements SurveyStructuredError {
  const SurveyFormatException(
    this.code,
    String message, [
    this.args = const <String, Object>{},
  ]) : super(message);

  @override
  final SurveyErrorCode code;

  @override
  final Map<String, Object> args;

  @override
  String get defaultMessage => message;
}

/// [ArgumentError] carrying [SurveyStructuredError] metadata.
class SurveyArgumentError extends ArgumentError
    implements SurveyStructuredError {
  SurveyArgumentError(
    this.code,
    String message, [
    this.args = const <String, Object>{},
  ]) : super(message);

  SurveyArgumentError.value(
    super.value,
    super.name,
    this.code,
    String super.message, [
    this.args = const <String, Object>{},
  ]) : super.value();

  @override
  final SurveyErrorCode code;

  @override
  final Map<String, Object> args;

  @override
  String get message => super.message?.toString() ?? code.name;

  @override
  String get defaultMessage => message;
}
