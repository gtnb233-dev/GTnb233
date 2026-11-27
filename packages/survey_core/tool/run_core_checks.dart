import 'dart:io';

import '../test/core_cases.dart';
import '../test/harness.dart' as harness;

void main() {
  registerCoreChecks(group: harness.group, test: harness.test);
  exitCode = harness.finish();
}
