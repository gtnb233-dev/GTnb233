import 'package:flutter/material.dart';

ThemeData workspaceTheme(ThemeData theme) {
  final dark = theme.brightness == Brightness.dark;
  final canvas = dark ? Colors.black : const Color(0xFFF2F2F7);
  final group = dark ? const Color(0xFF1C1C1E) : Colors.white;
  final fill = dark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide.none,
  );
  return theme.copyWith(
    scaffoldBackgroundColor: canvas,
    colorScheme: theme.colorScheme.copyWith(
      surface: group,
      surfaceContainerLow: group,
      surfaceContainer: fill,
    ),
    cardTheme: theme.cardTheme.copyWith(color: group, elevation: 0),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: fill,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
      ),
    ),
  );
}
