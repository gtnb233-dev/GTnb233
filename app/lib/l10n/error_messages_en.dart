/// English templates for structured [SurveyErrorCode] errors from `survey_core`.
const errorEnglishMessages = <String, String>{
  // angle.dart
  'angleEmpty': 'Angle is empty',
  'angleTooManyParts':
      'Invalid angle format: "{text}" (at most three DMS parts)',
  'angleInvalidFormat': 'Invalid angle format: "{text}"',

  // expression.dart
  'formulaParseError':
      'Unparseable content at character {pos}: "{trailing}"',
  'formulaInvalidResult': 'Invalid calculation result ({value})',
  'formulaDivisionByZero': 'Division by zero',
  'formulaIncomplete': 'Incomplete expression',
  'formulaMissingRightParen': 'Missing closing parenthesis ")"',
  'formulaUnexpectedChar': 'Unrecognized character "{char}"',
  'formulaInvalidNumber': 'Invalid number "{text}"',
  'formulaFunctionMissingRightParen':
      'Function {name} is missing a closing parenthesis ")"',
  'formulaUnknownVariable': 'Unknown variable "{name}"',
  'formulaInsufficientArgs': 'Insufficient arguments for function {name}',
  'formulaNegativeSqrt': 'Argument of sqrt cannot be negative',
  'formulaUnknownFunction': 'Unknown function "{name}"',

  // leveling.dart
  'levelingLengthInvalid':
      'Route length must be a non-negative finite number',
  'levelingStationCountNegative': 'Station count cannot be negative',
  'levelingLengthOrStationRequired':
      'Either lengthKm or stationCount must be provided',
  'levelingBackConstantExceeded':
      'Backsight staff K+black−red exceeds limit ({diff} mm)',
  'levelingFrontConstantExceeded':
      'Foresight staff K+black−red exceeds limit ({diff} mm)',
  'levelingDistanceDiffExceeded':
      'Stadia distance difference exceeds limit ({diff} m)',
  'levelingCumulativeDiffExceeded':
      'Cumulative stadia difference exceeds limit ({diff} m)',
  'levelingSightLengthExceeded':
      'Sight length exceeds limit (BS {back} m, FS {front} m)',
  'levelingHeightDiffExceeded':
      'Black/red face height difference exceeds limit',
  'levelingSightHeightTooLow': 'Sight height ≤ 0.2 m',

  // projection.dart
  'projectionLonOutOfRange': 'Longitude is outside [-180°, 180°]',
  'projectionZoneWidthInvalid': 'Only 3° and 6° zones are supported',
  'projectionLatOutOfRange': 'Latitude is outside [-90°, 90°]',
  'projectionGaussLatOutOfRange':
      'Latitude exceeds Gauss projection range |B| ≤ 84°',
  'projectionCoordNotFinite': 'Plane coordinates must be finite numbers',
  'projectionInverseLatOutOfRange': 'Inverse latitude exceeds |B| ≤ 84°',

  // geodesy.dart
  'geodesyLatOutOfRange': 'Latitude is outside [-90°, 90°]',
  'geodesyLonOutOfRange': 'Longitude is outside [-180°, 180°]',
  'geodesyHeightNotFinite': 'Ellipsoidal height must be a finite number',
  'geodesyEcefNotFinite': 'ECEF coordinates must be finite numbers',

  // intersection.dart
  'intersectionPointsCoincident': 'Known points coincide',
  'intersectionDistanceNonPositive': 'Distance must be greater than 0',
  'intersectionCirclesNoOverlapSum':
      'Circles do not intersect: d1 + d2 is less than baseline',
  'intersectionCirclesNoOverlapDiff':
      'Circles do not intersect: |d1 − d2| exceeds baseline',

  // format.dart
  'toleranceExceeded': 'Exceeds tolerance ({value} > {limit})',

  // traverse.dart
  'traverseAngleMisclosureExceeded':
      'Angular misclosure exceeds limit ({misclosure}″ > ±{limit}″)',
  'traverseLinearMisclosureExceeded':
      'Relative linear misclosure exceeds limit (1/{denominator} > 1/{limitDenominator})',
};
