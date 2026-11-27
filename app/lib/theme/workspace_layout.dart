import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

bool workspaceUsesCompactLayout(BuildContext context) =>
    WorkspaceHost.isAndroid(context) &&
    MediaQuery.orientationOf(context) == Orientation.portrait;

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
