import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:survey_core/survey_core.dart';

import '../../l10n/survey_strings.dart';
import '../../platform/native_bridge_contract.dart';
import '../../theme/tokens.dart';
import '../../theme/workspace_layout.dart';
import 'overlays.dart';
import 'workspace_commands.dart';

enum _GnssSource { clipboard, receiver }

/// Compact GNSS status pill + one-tap NMEA `$GPGGA` / `$GNGGA` sampling chip.
///
/// Calls [NativeGnssBridge.readLatestGga] -> [parseGpgga] -> [gaussForward]
/// and passes `(x, y, h)` in meters to [onSample].
class GnssSampleChip extends StatefulWidget {
  const GnssSampleChip({
    super.key,
    required this.onSample,
    this.heightOnly = false,
  });

  /// Callback receiving Gauss-Kruger `(x, y)` in meters and elevation `h` in meters.
  final void Function(double x, double y, double h) onSample;
  final bool heightOnly;

  @override
  State<GnssSampleChip> createState() => _GnssSampleChipState();
}

class _GnssSampleChipState extends State<GnssSampleChip> {
  bool _busy = false;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    unawaited(_probeStatus());
  }

  Future<void> _probeStatus() async {
    final available = await NativeGnssBridge.isAvailable();
    if (!mounted) return;
    setState(() => _connected = available);
  }

  Future<void> _sample() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final sample = await NativeGnssBridge.readLatestGga();
      if (!mounted) return;
      setState(() => _connected = sample.connected);
      final sampleText = sample.rawGga ?? await _chooseSource();
      if (!mounted || sampleText == null) return;
      final gga = sampleText
          .split(RegExp(r'[\r\n]+'))
          .reversed
          .map(parseGpgga)
          .firstWhere((fix) => fix != null && fix.fixQuality > 0,
              orElse: () => null);
      if (gga == null || (!widget.heightOnly && gga.latDeg.abs() > 84)) {
        SurveyToast.warning(
          context,
          context.tr('GNSS 定位尚未固定或数据无效'),
        );
        return;
      }
      final h = gga.altitudeM;
      if (widget.heightOnly) {
        widget.onSample(0, 0, h);
        SurveyToast.success(
          context,
          context.tr('已填入 GNSS 高程（H={h} m）', {'h': h.toStringAsFixed(3)}),
        );
      } else {
        final gp = gaussForward(latDeg: gga.latDeg, lonDeg: gga.lonDeg);
        widget.onSample(gp.x, gp.y, h);
        SurveyToast.success(
          context,
          context.tr('已填入 GNSS 坐标（X={x}, Y={y}, H={h}）', {
            'x': gp.x.toStringAsFixed(3),
            'y': gp.y.toStringAsFixed(3),
            'h': h.toStringAsFixed(3),
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _chooseSource() async {
    final android = WorkspaceHost.isAndroid(context);
    final source = await workspacePanel<_GnssSource>(
      context,
      'GNSS 数据来源',
      Builder(
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.heightOnly)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(sheetContext.tr('坐标按 CGCS2000 3°带投影')),
              ),
            ListTile(
              key: const ValueKey('gnss-source-clipboard'),
              leading: const Icon(Icons.content_paste_outlined),
              title: Text(sheetContext.tr('从剪贴板读取 NMEA')),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_GnssSource.clipboard),
            ),
            if (android)
              ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(sheetContext.tr('连接已配对的 GNSS 接收机')),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_GnssSource.receiver),
              ),
          ],
        ),
      ),
      useBottomSheet: android,
    );
    if (!mounted || source == null) return null;
    if (source == _GnssSource.clipboard) {
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        return data?.text ?? '';
      } on PlatformException {
        return '';
      } on MissingPluginException {
        return '';
      }
    }

    final devices = await NativeGnssBridge.pairedReceivers();
    if (!mounted) return null;
    if (devices.isEmpty) {
      SurveyToast.info(context, context.tr('请在系统设置中开启蓝牙、配对接收机并授权'));
      return null;
    }
    final address = await workspacePanel<String>(
      context,
      '连接已配对的 GNSS 接收机',
      Builder(
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final device in devices)
              ListTile(
                title: Text(device.name),
                subtitle: Text(device.address),
                onTap: () => Navigator.of(sheetContext).pop(device.address),
              ),
          ],
        ),
      ),
      useBottomSheet: android,
    );
    if (!mounted || address == null) return null;
    final connected = await NativeGnssBridge.connect(deviceAddress: address);
    if (!mounted) return null;
    setState(() => _connected = connected);
    SurveyToast.info(
      context,
      context.tr(connected ? 'GNSS 已连接，取得定位后可再次采点' : '无法连接 GNSS 接收机'),
    );
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusLabel = context.tr(_connected ? 'GNSS 就绪' : 'GNSS 未连接');
    final dotColor = _connected ? scheme.primary : scheme.outline;

    return Wrap(
      spacing: Insets.s,
      runSpacing: Insets.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                statusLabel,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
        ActionChip(
          key: const ValueKey('gnss-sample-btn'),
          avatar: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.satellite_alt_outlined, size: 16),
          label: Text(context.tr('NMEA 采点填入')),
          onPressed: _busy ? null : _sample,
        ),
      ],
    );
  }
}
