import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/survey_strings.dart';
import '../../platform/native_bridge_contract.dart';
import '../../state/control_points.dart';
import '../../state/drafts.dart';
import '../../state/live_plot_controller.dart';
import '../../theme/tokens.dart';
import '../../theme/workspace_layout.dart';
import 'overlays.dart';
import 'workspace_commands.dart';

/// 导入写入模式：覆盖现有控制点或追加到末尾。
enum SmartImportMode { overwrite, append }

/// 智能导入解析出的单个测量坐标点（X 北向、Y 东向、可选高程 Z/H）。
class SmartImportPoint {
  const SmartImportPoint({
    required this.name,
    required this.x,
    required this.y,
    this.z,
    this.layer,
  });

  final String name;
  final double x;
  final double y;
  final double? z;
  final String? layer;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'x': x,
        'y': y,
        if (z != null) 'z': z,
        if (layer != null && layer!.isNotEmpty) 'layer': layer,
      };
}

/// 从 ASCII DXF 解析出的图形实体（POINT / LINE / LWPOLYLINE）。
class SmartImportDxfEntity {
  const SmartImportDxfEntity({
    required this.type,
    required this.layer,
    required this.vertices,
  });

  final String type;
  final String layer;
  final List<SmartImportPoint> vertices;
}

/// [SmartImportParser.parse] 的结构化解析结果。
class SmartImportResult {
  const SmartImportResult({
    required this.points,
    this.dxfEntities = const [],
    this.isDxf = false,
    this.skippedLines = 0,
  });

  final List<SmartImportPoint> points;
  final List<SmartImportDxfEntity> dxfEntities;
  final bool isDxf;
  final int skippedLines;

  bool get isEmpty => points.isEmpty && dxfEntities.isEmpty;
}

/// 智能坐标与 DXF 文本解析器。
///
/// 支持逗号、空格、Tab、分号、微信/QQ 聊天片段、Excel 多行粘贴、南方 CASS
/// 格式以及 ASCII DXF (`POINT` / `LINE` / `LWPOLYLINE`) 实体。
abstract final class SmartImportParser {
  static final RegExp _chatPrefixPattern = RegExp(
    r'^(?:\[[^\]]+\]\s*)?(?:[\d]{4}[-/][\d]{1,2}[-/][\d]{1,2}\s+)?(?:\d{1,2}:\d{2}(?::\d{2})?\s+)?[^:：\d\-\+\s][^:：\n]{0,24}[:：]\s*',
  );
  static final RegExp _timestampOnlyPattern = RegExp(
    r'^(?:\d{4}[-/]\d{1,2}[-/]\d{1,2}\s*)?\d{1,2}:\d{2}(?::\d{2})?(?:\s+\S+)?$',
  );
  static final RegExp _labeledCoordPattern = RegExp(
    r'([XYNEHZxynehz])\s*[:=：]\s*([-+]?\d+(?:\.\d+)?)',
  );
  static final RegExp _structuredDelimiterPattern = RegExp(r'[,，;\t；]');
  static final RegExp _whitespaceDelimiterPattern = RegExp(r'[\s|]+');

  static SmartImportResult parse(String raw, {bool isDxfHint = false}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const SmartImportResult(points: []);
    }
    if (isDxfHint || _looksLikeDxf(trimmed)) {
      final dxf = _parseDxf(trimmed);
      if (!dxf.isEmpty) return dxf;
    }
    return _parseTabularOrChat(trimmed);
  }

  static bool _looksLikeDxf(String text) {
    final upper = text.toUpperCase();
    return upper.contains('\nSECTION') ||
        upper.contains('\r\nSECTION') ||
        upper.startsWith('0\nSECTION') ||
        upper.startsWith('0\r\nSECTION') ||
        upper.contains('\nENTITIES') ||
        upper.contains('\r\nENTITIES');
  }

  static SmartImportResult _parseDxf(String content) {
    final lines = const LineSplitter().convert(content);
    final points = <SmartImportPoint>[];
    final entities = <SmartImportDxfEntity>[];

    String? currentType;
    var layer = '0';
    double? x1, y1, z1;
    double? x2, y2, z2;
    final polyVertices = <SmartImportPoint>[];
    double? polyX;
    double? polyElev;

    void flushEntity() {
      switch (currentType) {
        case 'POINT':
          if (x1 != null && y1 != null && x1!.isFinite && y1!.isFinite) {
            final pt = SmartImportPoint(
              name: 'DXF${points.length + 1}',
              x: y1!, // CAD Y(N) -> Survey X(N)
              y: x1!, // CAD X(E) -> Survey Y(E)
              z: z1 != null && z1!.isFinite ? z1 : null,
              layer: layer,
            );
            points.add(pt);
            entities.add(SmartImportDxfEntity(
              type: 'POINT',
              layer: layer,
              vertices: [pt],
            ));
          }
        case 'LINE':
          if (x1 != null &&
              y1 != null &&
              x2 != null &&
              y2 != null &&
              x1!.isFinite &&
              y1!.isFinite &&
              x2!.isFinite &&
              y2!.isFinite) {
            final p1 = SmartImportPoint(
              name: 'L${points.length + 1}',
              x: y1!,
              y: x1!,
              z: z1 != null && z1!.isFinite ? z1 : null,
              layer: layer,
            );
            final p2 = SmartImportPoint(
              name: 'L${points.length + 2}',
              x: y2!,
              y: x2!,
              z: z2 != null && z2!.isFinite ? z2 : null,
              layer: layer,
            );
            points
              ..add(p1)
              ..add(p2);
            entities.add(SmartImportDxfEntity(
              type: 'LINE',
              layer: layer,
              vertices: [p1, p2],
            ));
          }
        case 'LWPOLYLINE':
          if (polyVertices.isNotEmpty) {
            points.addAll(polyVertices);
            entities.add(SmartImportDxfEntity(
              type: 'LWPOLYLINE',
              layer: layer,
              vertices: List<SmartImportPoint>.of(polyVertices),
            ));
          }
      }
      currentType = null;
      layer = '0';
      x1 = y1 = z1 = null;
      x2 = y2 = z2 = null;
      polyX = null;
      polyElev = null;
      polyVertices.clear();
    }

    for (var i = 0; i + 1 < lines.length; i += 2) {
      final code = lines[i].trim();
      final value = lines[i + 1].trim();
      if (code == '0') {
        flushEntity();
        final upper = value.toUpperCase();
        if (upper == 'POINT' || upper == 'LINE' || upper == 'LWPOLYLINE') {
          currentType = upper;
        }
        continue;
      }
      if (currentType == null) continue;
      if (code == '8' && value.isNotEmpty) {
        layer = value;
        continue;
      }
      if (currentType == 'LWPOLYLINE') {
        switch (code) {
          case '38':
            polyElev = double.tryParse(value);
          case '10':
            polyX = double.tryParse(value);
          case '20':
            final py = double.tryParse(value);
            if (polyX != null && py != null && polyX!.isFinite && py.isFinite) {
              final idx = points.length + polyVertices.length + 1;
              polyVertices.add(SmartImportPoint(
                name: 'V$idx',
                x: py,
                y: polyX!,
                z: polyElev != null && polyElev!.isFinite ? polyElev : null,
                layer: layer,
              ));
            }
            polyX = null;
        }
      } else {
        switch (code) {
          case '10':
            x1 = double.tryParse(value);
          case '20':
            y1 = double.tryParse(value);
          case '30':
            z1 = double.tryParse(value);
          case '11':
            x2 = double.tryParse(value);
          case '21':
            y2 = double.tryParse(value);
          case '31':
            z2 = double.tryParse(value);
        }
      }
    }
    flushEntity();

    return SmartImportResult(
      points: points,
      dxfEntities: entities,
      isDxf: true,
    );
  }

  static SmartImportResult _parseTabularOrChat(String content) {
    final lines = const LineSplitter().convert(content);
    final points = <SmartImportPoint>[];
    var skipped = 0;

    for (final rawLine in lines) {
      var line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) {
        continue;
      }
      if (_timestampOnlyPattern.hasMatch(line)) {
        skipped++;
        continue;
      }

      // 优先尝试解析带标签的坐标（如微信/QQ 聊天中的 "P1: X=3456789.1, Y=512345.2, H=12.3"）。
      final labeled = _tryParseLabeledLine(line, points.length + 1);
      if (labeled != null) {
        points.add(labeled);
        continue;
      }

      // 剥离聊天前缀（如 "[14:20] 张三: ..."）。
      final stripped = line.replaceFirst(_chatPrefixPattern, '').trim();
      if (stripped.isNotEmpty) {
        line = stripped;
      }

      final parsed = _tryParseDelimitedLine(line, points.length + 1);
      if (parsed != null) {
        points.add(parsed);
      } else {
        skipped++;
      }
    }

    return SmartImportResult(
      points: points,
      skippedLines: skipped,
    );
  }

  static SmartImportPoint? _tryParseLabeledLine(String line, int index) {
    final matches = _labeledCoordPattern.allMatches(line).toList();
    if (matches.length < 2) return null;

    double? x;
    double? y;
    double? z;
    for (final m in matches) {
      final key = m.group(1)!.toUpperCase();
      final val = double.tryParse(m.group(2)!);
      if (val == null || !val.isFinite) continue;
      switch (key) {
        case 'X':
        case 'N':
          x ??= val;
        case 'Y':
        case 'E':
          y ??= val;
        case 'H':
        case 'Z':
          z ??= val;
      }
    }
    if (x == null || y == null) return null;

    // 从第一个坐标标签之前的文本提取点名（剥离聊天时间戳前缀）。
    var prefix = line.substring(0, matches.first.start).trim();
    prefix = prefix.replaceFirst(_chatPrefixPattern, '').trim();
    prefix = prefix.replaceAll(RegExp(r'[,，:：;；\s]+$'), '').trim();
    final name = prefix.isEmpty || prefix.length > 24 ? 'P$index' : prefix;
    return SmartImportPoint(name: name, x: x, y: y, z: z);
  }

  static SmartImportPoint? _tryParseDelimitedLine(String line, int index) {
    final hasStructuredDelimiter = _structuredDelimiterPattern.hasMatch(line);
    final parts = hasStructuredDelimiter
        ? line.split(_structuredDelimiterPattern).map((e) => e.trim()).toList()
        : line
            .split(_whitespaceDelimiterPattern)
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
    if (parts.length < 2) return null;

    // 1) 纯数字行：X, Y[, Z]
    final d0 = double.tryParse(parts[0]);
    final d1 = double.tryParse(parts[1]);
    if (d0 != null && d1 != null && d0.isFinite && d1.isFinite) {
      // 检查是否为 "序号, 点名, X, Y[, Z]"（parts[0] 为整数且 parts[1] 不是坐标？这里 d1 非空说明 parts[1] 也是数字）。
      final d2 = parts.length >= 3 ? double.tryParse(parts[2]) : null;
      final d3 = parts.length >= 4 ? double.tryParse(parts[3]) : null;
      if (parts.length >= 4 &&
          int.tryParse(parts[0]) != null &&
          d2 != null &&
          d3 != null &&
          d2.isFinite &&
          d3.isFinite) {
        // 如 "1  201  3456789.1  512345.2  12.3" -> 序号 1，点名 201
        final d4 = parts.length >= 5 ? double.tryParse(parts[4]) : null;
        return SmartImportPoint(
          name: parts[1],
          x: d2,
          y: d3,
          z: d4 != null && d4.isFinite ? d4 : null,
        );
      }
      return SmartImportPoint(
        name: 'P$index',
        x: d0,
        y: d1,
        z: d2 != null && d2.isFinite ? d2 : null,
      );
    }

    // 2) 标准行：Name, X, Y[, Z]
    if (parts.length >= 3) {
      final x = double.tryParse(parts[1]);
      final y = double.tryParse(parts[2]);
      if (x != null && y != null && x.isFinite && y.isFinite) {
        // 若 parts[0] 为小序号且后面还有 2 个数值（如 "1, P1, 100, 200"），在上面已拦截纯数字；
        // 这里 parts[1] 是数字，说明 parts[0] 是点名。
        final z = parts.length >= 4 ? double.tryParse(parts[3]) : null;
        return SmartImportPoint(
          name: parts[0].isEmpty ? 'P$index' : parts[0],
          x: x,
          y: y,
          z: z != null && z.isFinite ? z : null,
        );
      }

      // 3) Excel 带序号行：No, Name, X, Y[, Z] 或 CASS：Name, Code, Y, X[, H]
      if (parts.length >= 4) {
        final v2 = double.tryParse(parts[2]);
        final v3 = double.tryParse(parts[3]);
        if (v2 != null && v3 != null && v2.isFinite && v3.isFinite) {
          final v4 = parts.length >= 5 ? double.tryParse(parts[4]) : null;
          final isRowIndex = int.tryParse(parts[0]) != null;
          if (isRowIndex) {
            return SmartImportPoint(
              name: parts[1].isEmpty ? 'P$index' : parts[1],
              x: v2,
              y: v3,
              z: v4 != null && v4.isFinite ? v4 : null,
            );
          }
          // 南方 CASS：Name, Code, Y(东), X(北)[, H]
          return SmartImportPoint(
            name: parts[0].isEmpty ? 'P$index' : parts[0],
            x: v3,
            y: v2,
            z: v4 != null && v4.isFinite ? v4 : null,
          );
        }
      }
    }

    return null;
  }
}

enum _ImportSourceChoice { file, clipboard }

/// 打开全局「数据导入」流程：选择文件或剪贴板 -> 智能解析 -> 预览确认 -> 写入存储与实时画布。
Future<bool> showSmartImportFlow(
  BuildContext context, {
  String? targetPageId,
  VoidCallback? onImported,
}) async {
  final android = WorkspaceHost.isAndroid(context);
  final choice = await workspacePanel<_ImportSourceChoice>(
    context,
    '数据导入',
    Builder(
      builder: (sheetCtx) {
        void pick(_ImportSourceChoice c) {
          if (ModalRoute.of(sheetCtx)?.isCurrent ?? false) {
            Navigator.of(sheetCtx).pop(c);
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              sheetCtx.tr('选择坐标或 DXF 数据的导入来源，导入前将展示预览确认表'),
              style: Theme.of(sheetCtx).textTheme.bodySmall,
            ),
            const SizedBox(height: Insets.m),
            ListTile(
              key: const ValueKey('smart-import-file'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(sheetCtx.tr('从文件导入（SAF / 系统文件）')),
              subtitle: Text(sheetCtx.tr('支持 DXF、CSV、DAT、TXT 坐标文件')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => pick(_ImportSourceChoice.file),
            ),
            const Divider(height: 1),
            ListTile(
              key: const ValueKey('smart-import-clipboard'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.content_paste_go_rounded),
              title: Text(sheetCtx.tr('从剪贴板智能识别')),
              subtitle: Text(sheetCtx.tr('自动清洗微信/QQ聊天、Excel多行及逗号/空格坐标')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => pick(_ImportSourceChoice.clipboard),
            ),
          ],
        );
      },
    ),
    useBottomSheet: android,
  );

  if (choice == null || !context.mounted) return false;

  SmartImportResult parsed;
  var sourceName = context.tr('剪贴板');

  if (choice == _ImportSourceChoice.file) {
    try {
      final doc = await NativeFilesBridge.pickDocument();
      if (!context.mounted) return false;
      if (doc == null) return false;
      sourceName = doc.name;
      parsed = SmartImportParser.parse(
        doc.text,
        isDxfHint: doc.name.toLowerCase().endsWith('.dxf'),
      );
    } on FormatException catch (e) {
      if (context.mounted) {
        SurveyToast.error(
          context,
          context.tr('文件读取失败：{error}', {'error': e.message}),
        );
      }
      return false;
    } catch (e) {
      if (context.mounted) {
        SurveyToast.error(
          context,
          context.tr('文件读取失败：{error}', {'error': e.toString()}),
        );
      }
      return false;
    }
  } else {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return false;
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      SurveyToast.info(context, '剪贴板为空，请先复制坐标或 DXF 文本');
      return false;
    }
    parsed = SmartImportParser.parse(text);
  }

  if (!context.mounted) return false;
  if (parsed.isEmpty) {
    SurveyToast.warning(context, '未识别到有效坐标或 DXF 实体');
    return false;
  }

  final confirmed = await _showImportPreviewDialog(
    context,
    result: parsed,
    sourceName: sourceName,
  );
  if (confirmed == null || !context.mounted) return false;

  await _applySmartImport(
    context,
    result: parsed,
    mode: confirmed,
    sourceName: sourceName,
    targetPageId: targetPageId,
  );
  onImported?.call();

  if (context.mounted) {
    LivePlotScope.maybeRead(context)?.revealRoutes();
    SurveyToast.success(
      context,
      context.tr(
        '已导入 {count} 个坐标点',
        {'count': '${parsed.points.length}'},
      ),
    );
  }
  return true;
}

Future<SmartImportMode?> _showImportPreviewDialog(
  BuildContext context, {
  required SmartImportResult result,
  required String sourceName,
}) {
  var mode = SmartImportMode.append;
  return SurveyModal.show<SmartImportMode>(
    context,
    title: '导入预览确认',
    subtitle: context.tr(
      '来源：{source} · 共识别 {count} 个点',
      {'source': sourceName, 'count': '${result.points.length}'},
    ),
    icon: Icons.table_view_rounded,
    maxWidth: 560,
    child: StatefulBuilder(
      builder: (ctx, setState) {
        final scheme = Theme.of(ctx).colorScheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<SmartImportMode>(
              segments: [
                ButtonSegment(
                  value: SmartImportMode.append,
                  icon: const Icon(Icons.playlist_add_rounded, size: 16),
                  label: Text(ctx.tr('追加')),
                ),
                ButtonSegment(
                  value: SmartImportMode.overwrite,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                  label: Text(ctx.tr('覆盖')),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (v) => setState(() => mode = v.single),
            ),
            if (result.isDxf && result.dxfEntities.isNotEmpty) ...[
              const SizedBox(height: Insets.s),
              Text(
                ctx.tr(
                  '已解析 DXF 实体：{count} 个',
                  {'count': '${result.dxfEntities.length}'},
                ),
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                    ),
              ),
            ],
            const SizedBox(height: Insets.m),
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: BoxDecoration(
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
                borderRadius: BorderRadius.circular(Radii.field),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.field),
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 16,
                      horizontalMargin: 12,
                      headingRowHeight: 36,
                      dataRowMinHeight: 34,
                      dataRowMaxHeight: 40,
                      columns: [
                        DataColumn(label: Text(ctx.tr('点名'))),
                        const DataColumn(label: Text('X (N)'), numeric: true),
                        const DataColumn(label: Text('Y (E)'), numeric: true),
                        const DataColumn(label: Text('Z / H'), numeric: true),
                      ],
                      rows: [
                        for (final pt in result.points.take(100))
                          DataRow(
                            cells: [
                              DataCell(Text(pt.name)),
                              DataCell(Text(pt.x.toStringAsFixed(3))),
                              DataCell(Text(pt.y.toStringAsFixed(3))),
                              DataCell(
                                Text(
                                  pt.z != null ? pt.z!.toStringAsFixed(3) : '—',
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (result.points.length > 100) ...[
              const SizedBox(height: Insets.xs),
              Text(
                ctx.tr('仅预览前 100 个点，确认后将全部导入'),
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        );
      },
    ),
    actionsBuilder: (dialogCtx) => [
      TextButton(
        onPressed: () => Navigator.of(dialogCtx).pop(),
        child: Text(dialogCtx.tr('取消')),
      ),
      FilledButton(
        key: const ValueKey('smart-import-confirm-btn'),
        onPressed: () => Navigator.of(dialogCtx).pop(mode),
        child: Text(dialogCtx.tr('确认导入')),
      ),
    ],
  );
}

Future<void> _applySmartImport(
  BuildContext context, {
  required SmartImportResult result,
  required SmartImportMode mode,
  required String sourceName,
  String? targetPageId,
}) async {
  final cpStore = ControlPointScope.maybeRead(context);
  if (cpStore != null && result.points.isNotEmpty) {
    if (mode == SmartImportMode.overwrite) {
      await cpStore.clear();
    }
    var stamp = DateTime.now().microsecondsSinceEpoch;
    final items = <ControlPoint>[
      for (final pt in result.points)
        ControlPoint(
          id: 'cp_${stamp++}',
          name: pt.name,
          x: pt.x,
          y: pt.y,
          h: pt.z,
          group: pt.layer ?? (result.isDxf ? 'DXF' : '导入'),
        ),
    ];
    await cpStore.addAll(items);
  }

  if (!context.mounted) return;
  final drafts = DraftScope.maybeRead(context);
  if (drafts != null && targetPageId != null) {
    drafts.putAll(targetPageId, {
      'imported_source': sourceName,
      'imported_count': '${result.points.length}',
      'imported_points': json.encode([
        for (final pt in result.points) pt.toJson(),
      ]),
    });
  }

  final livePlot = LivePlotScope.maybeRead(context);
  if (livePlot != null && result.points.isNotEmpty) {
    final plotPoints = [
      for (final pt in result.points)
        LivePlotPointData(x: pt.x, y: pt.y, label: pt.name),
    ];
    final plotPaths = <LivePlotPathData>[
      for (final ent in result.dxfEntities)
        if (ent.vertices.length >= 2)
          LivePlotPathData(
            points: [
              for (final v in ent.vertices)
                LivePlotPointData(x: v.x, y: v.y, label: v.name),
            ],
            label: ent.layer,
          ),
    ];
    livePlot.updateSnapshot(
      LivePlotSnapshot(
        title: sourceName,
        sourceToolId: targetPageId ?? 'smart_import',
        sourceLabel: sourceName,
        sourceKind: LivePlotSourceKind.importedFile,
        points: plotPoints,
        paths: plotPaths,
      ),
      sourceKind: LivePlotSourceKind.importedFile,
    );
  }
}
