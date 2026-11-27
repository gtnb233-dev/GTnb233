import 'package:flutter/material.dart';

/// Line symbols shared by the sidebar, bottom bar and main actions.
class OutlineSymbol extends StatelessWidget {
  const OutlineSymbol(this.icon, {super.key, this.size, this.color});

  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    final ink = color ?? theme.color ?? Theme.of(context).colorScheme.onSurface;
    final shape = switch (icon) {
      Icons.dashboard_outlined || Icons.dashboard => _Symbol.grid,
      Icons.place_outlined || Icons.place => _Symbol.pin,
      Icons.calculate_outlined || Icons.calculate => _Symbol.calculator,
      Icons.widgets_outlined || Icons.widgets => _Symbol.library,
      Icons.settings_outlined || Icons.settings => _Symbol.settings,
      Icons.search || Icons.search_rounded => _Symbol.search,
      Icons.functions => _Symbol.formula,
      Icons.architecture => _Symbol.compass,
      Icons.menu_open ||
      Icons.menu_open_rounded ||
      Icons.first_page =>
        _Symbol.panel,
      Icons.menu || Icons.menu_rounded => _Symbol.menu,
      _ => null,
    };
    if (shape == null) return Icon(icon, size: size, color: color);

    return SizedBox.square(
      dimension: side,
      child: CustomPaint(
        painter: _OutlinePainter(
            shape,
            ink.withValues(
              alpha: ink.a * (theme.opacity ?? 1),
            )),
      ),
    );
  }
}

enum _Symbol {
  grid,
  pin,
  calculator,
  library,
  settings,
  search,
  formula,
  compass,
  panel,
  menu
}

class _OutlinePainter extends CustomPainter {
  const _OutlinePainter(this.symbol, this.color);

  final _Symbol symbol;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.scale(scale);
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 / scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), ink);
    void circle(double x, double y, double radius) =>
        canvas.drawCircle(Offset(x, y), radius, ink);
    void box(double x, double y, double width, double height,
            [double radius = 2]) =>
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x, y, width, height), Radius.circular(radius)),
          ink,
        );

    switch (symbol) {
      case _Symbol.grid:
        for (final x in [3.0, 13.0]) {
          for (final y in [3.0, 13.0]) {
            box(x, y, 8, 8, 1.5);
          }
        }
      case _Symbol.pin:
        canvas.drawPath(
          Path()
            ..moveTo(12, 22)
            ..cubicTo(9, 18, 5, 14, 5, 10)
            ..arcToPoint(const Offset(19, 10), radius: const Radius.circular(7))
            ..cubicTo(19, 14, 15, 18, 12, 22)
            ..close(),
          ink,
        );
        circle(12, 10, 2.5);
      case _Symbol.calculator:
        box(5, 2.5, 14, 19);
        line(8.5, 7.5, 15.5, 7.5);
        for (final y in [12.0, 16.0]) {
          line(8.5, y, 9.5, y);
          line(14.5, y, 15.5, y);
        }
      case _Symbol.library:
        box(3, 4, 4.5, 16, 1);
        box(9.5, 4, 4.5, 16, 1);
        line(16.5, 5, 21, 19.5);
      case _Symbol.settings:
        for (final x in [6.0, 12.0, 18.0]) {
          final y = x == 12 ? 15.0 : 8.0;
          line(x, 3, x, y - 2.25);
          circle(x, y, 2.25);
          line(x, y + 2.25, x, 21);
        }
      case _Symbol.search:
        circle(10.5, 10.5, 6.25);
        line(15, 15, 20.5, 20.5);
      case _Symbol.formula:
        canvas.drawPath(
          Path()
            ..moveTo(19, 4)
            ..lineTo(6, 4)
            ..lineTo(12, 12)
            ..lineTo(6, 20)
            ..lineTo(19, 20),
          ink,
        );
      case _Symbol.compass:
        circle(12, 5.5, 2.5);
        line(10.8, 7.7, 4, 21);
        line(13.2, 7.7, 20, 21);
        line(7, 15.5, 17, 15.5);
      case _Symbol.panel:
        box(3, 4, 18, 16);
        line(9, 4, 9, 20);
        canvas.drawPath(
          Path()
            ..moveTo(16, 9)
            ..lineTo(13, 12)
            ..lineTo(16, 15),
          ink,
        );
      case _Symbol.menu:
        line(4, 7, 20, 7);
        line(4, 12, 20, 12);
        line(4, 17, 20, 17);
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter oldDelegate) =>
      symbol != oldDelegate.symbol || color != oldDelegate.color;
}
