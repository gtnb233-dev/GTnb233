import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

bool workspaceUsesCompactLayout(BuildContext context) {
  if (WorkspaceHost.isAndroid(context)) {
    return MediaQuery.orientationOf(context) == Orientation.portrait;
  }
  final size = MediaQuery.sizeOf(context);
  final wide = size.width >= kSidebarNavigationMinWidth ||
      (size.width > size.height && size.width >= 640);
  return !wide;
}

/// Android chrome differs from the desktop shell at the same window size.
class WorkspaceHost extends InheritedWidget {
  const WorkspaceHost({super.key, required this.android, required super.child});

  final bool android;

  static bool isAndroid(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceHost>()?.android ??
      (!kIsWeb && Platform.isAndroid);

  @override
  bool updateShouldNotify(WorkspaceHost oldWidget) =>
      android != oldWidget.android;
}
