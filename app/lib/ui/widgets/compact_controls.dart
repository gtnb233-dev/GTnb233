import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'workspace_commands.dart';

bool usesCompactWorkspaceControls(BuildContext context) =>
    WorkspaceCommandsEnabled.of(context) &&
    MediaQuery.sizeOf(context).width < kSidebarNavigationMinWidth;

/// Keep the same selection contract across compact and desktop controls.
class SurveySegmentedControl<T> extends StatelessWidget {
  const SurveySegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.showSelectedIcon = true,
    this.style,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final bool showSelectedIcon;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    if (!usesCompactWorkspaceControls(context)) {
      return SegmentedButton<T>(
        segments: segments,
        selected: selected,
        onSelectionChanged: onSelectionChanged,
        showSelectedIcon: showSelectedIcon,
        style: style,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final currentIndex = segments.indexWhere(
      (segment) => selected.contains(segment.value),
    );
    return CupertinoSlidingSegmentedControl<int>(
      groupValue: currentIndex < 0 ? null : currentIndex,
      backgroundColor: scheme.brightness == Brightness.dark
          ? const Color(0xFF2C2C2E)
          : const Color(0xFFEFEFF4),
      thumbColor: scheme.brightness == Brightness.dark
          ? const Color(0xFF3A3A3C)
          : Colors.white,
      disabledChildren: {
        for (var i = 0; i < segments.length; i++)
          if (!segments[i].enabled || onSelectionChanged == null) i,
      },
      onValueChanged: (index) {
        if (index != null) onSelectionChanged?.call({segments[index].value});
      },
      children: {
        for (final (index, segment) in segments.indexed)
          index: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 42),
            child: Center(
              widthFactor: 1,
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected.contains(segment.value)
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: scheme.onSurface,
                ),
                child: segment.label ?? segment.icon ?? const SizedBox(),
              ),
            ),
          ),
      },
    );
  }
}

class SurveySwitchTile extends StatelessWidget {
  const SurveySwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.contentPadding,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget title;
  final Widget? subtitle;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    if (!usesCompactWorkspaceControls(context)) {
      return SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        title: title,
        subtitle: subtitle,
        contentPadding: contentPadding,
      );
    }
    return MergeSemantics(
      child: ListTile(
        contentPadding: contentPadding,
        title: title,
        subtitle: subtitle,
        onTap: () => onChanged(!value),
        trailing: CupertinoSwitch(
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
