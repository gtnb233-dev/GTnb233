import 'package:flutter/widgets.dart';

import 'tokens.dart';

bool workspaceUsesCompactLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final wide = size.width >= kSidebarNavigationMinWidth ||
      (size.width > size.height && size.width >= 640);
  return !wide;
}
