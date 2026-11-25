import 'package:flutter/material.dart';
import 'package:survey_core/survey_core.dart';

import '../../app_info.dart';
import '../../state/drafts.dart';
import '../../state/settings.dart';
import '../../theme/tokens.dart';
import '../../theme/ui_style.dart';
import '../page_scaffold.dart';
import '../widgets/widgets.dart';

/// 设置页：主题、角度格式、小数位与反馈。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= kSidebarNavigationMinWidth;
    final drafts = DraftScope.maybeOf(context);
    final savedDraftCount = drafts?.savedCount ?? 0;
    final scheme = Theme.of(context).colorScheme;
    return PageScaffold(
      title: '设置',
      caption: '显示约定与交互偏好，全部保存在本机',
      children: [
        const SectionHeader(title: '主题与显示'),
        const SizedBox(height: Insets.s),
        SurfaceCard(
          padding: const EdgeInsets.all(Insets.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '主题模式',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: Insets.s),
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('跟随系统'),
                    icon: Icon(Icons.brightness_auto_outlined, size: 17),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('浅色'),
                    icon: Icon(Icons.light_mode_outlined, size: 17),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('深色'),
                    icon: Icon(Icons.dark_mode_outlined, size: 17),
                  ),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (v) => s.setThemeMode(v.first),
              ),
            ],
          ),
        ),
        const SizedBox(height: Insets.l),
        const SectionHeader(
          title: '外观',
          caption: '界面风格、玻璃导航与莫奈取色',
        ),
        const SizedBox(height: Insets.s),
        SurfaceCard(
          padding: const EdgeInsets.all(Insets.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'UI 风格',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: Insets.s),
              SegmentedButton<UiStyle>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(
                    TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
                segments: [
                  for (final style in UiStyle.values)
                    ButtonSegment(value: style, label: Text(style.label)),
                ],
                selected: {s.uiStyle},
                onSelectionChanged: (v) => s.setUiStyle(v.first),
              ),
              const SizedBox(height: 6),
              Text(
                s.uiStyle.description,
                style:
                    TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: Insets.m),
        SurfaceCard(
          padding: const EdgeInsets.fromLTRB(
            Insets.l,
            Insets.xs,
            Insets.l,
            Insets.s,
          ),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: wide ? s.glassNav : s.floatingGlassNav,
                onChanged: s.setGlassNav,
                title: Text(
                  wide ? '玻璃侧栏' : '液态玻璃导航',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  wide ? '在侧栏使用半透明玻璃背景' : '悬浮底栏与可滑动的玻璃胶囊',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              Divider(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
                height: 0.5,
                thickness: 0.5,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: s.monet,
                onChanged: s.setMonet,
                title: const Text(
                  '莫奈调色',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  '用种子色生成整套 tonal 调色板；Android 12+ / Windows 支持自动跟随系统强调色',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: Insets.s),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final seed in MonetSeed.values)
                      FilterChip(
                        label: Text(seed.label),
                        selected: s.monetSeed == seed,
                        visualDensity: VisualDensity.compact,
                        onSelected:
                            s.monet ? (_) => s.setMonetSeed(seed) : null,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Insets.l),
        const SectionHeader(
          title: '输入与显示',
          caption: '影响所有页面的角度录入与结果位数',
        ),
        const SizedBox(height: Insets.s),
        SurfaceCard(
          padding: const EdgeInsets.all(Insets.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '角度输入格式',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                s.angleMode == AngleInputMode.dmsCompact
                    ? '度分秒分格（度°/分′/秒″）：空格或小数点自动跳格，也支持粘贴 GG.MMSS'
                    : '十进制度：90.5 表示 90°30′00″（亦兼容空格或小数点直填度分秒）',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Insets.s),
              SegmentedButton<AngleInputMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: AngleInputMode.dmsCompact,
                    label: Text('度分秒'),
                  ),
                  ButtonSegment(
                    value: AngleInputMode.decimalDegrees,
                    label: Text('十进制度'),
                  ),
                ],
                selected: {s.angleMode},
                onSelectionChanged: (v) => s.setAngleMode(v.first),
              ),
              const SizedBox(height: Insets.l),
              const Text(
                '长度输入量级',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                '当前按 ${s.lengthUnitLabel} 录入与显示（1 m = 100 cm = 1000 mm 自动换算，默认米制）',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Insets.s),
              SegmentedButton<LengthUnit>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: LengthUnit.meter,
                    label: Text('米 (m)'),
                  ),
                  ButtonSegment(
                    value: LengthUnit.centimeter,
                    label: Text('厘米 (cm)'),
                  ),
                  ButtonSegment(
                    value: LengthUnit.millimeter,
                    label: Text('毫米 (mm)'),
                  ),
                ],
                selected: {s.lengthUnit},
                onSelectionChanged: (v) => s.setLengthUnit(v.first),
              ),
              const SizedBox(height: Insets.l),
              _Stepper(
                label: '坐标小数位',
                helper: '长度与坐标的显示位数',
                value: '${s.coordDigits}',
                onMinus: s.coordDigits > 0
                    ? () => s.setCoordDigits(s.coordDigits - 1)
                    : null,
                onPlus: s.coordDigits < 6
                    ? () => s.setCoordDigits(s.coordDigits + 1)
                    : null,
              ),
              const SizedBox(height: Insets.m),
              _Stepper(
                label: '角度秒小数位',
                helper: '秒值显示位数，0–3',
                value: '${s.angleSecDigits}',
                onMinus: s.angleSecDigits > 0
                    ? () => s.setAngleSecDigits(s.angleSecDigits - 1)
                    : null,
                onPlus: s.angleSecDigits < 3
                    ? () => s.setAngleSecDigits(s.angleSecDigits + 1)
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: Insets.l),
        const SectionHeader(title: '交互'),
        const SizedBox(height: Insets.s),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.l,
            vertical: Insets.s,
          ),
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: s.haptic,
            onChanged: s.setHaptic,
            title: const Text(
              '触感反馈',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '按钮与复制结果时给出轻微振动',
              style: TextStyle(fontSize: 11.5),
            ),
          ),
        ),
        const SizedBox(height: Insets.l),
        const SectionHeader(
          title: '数据与提示',
          caption: '五类弹出层规范预览、默认参数重置与草稿清理',
        ),
        const SizedBox(height: Insets.s),
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ChoiceTile(
                icon: Icons.layers_outlined,
                iconColor: scheme.primary,
                title: '弹出层与提示规范',
                subtitle: 'Tooltip · Toast · Alert · Modal · Popconfirm 交互演示',
                onTap: () => _showOverlayShowcase(context),
              ),
              Divider(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
                height: 0.5,
                thickness: 0.5,
                indent: Insets.l,
                endIndent: Insets.l,
              ),
              SurveyPopconfirm(
                title: '恢复默认录入参数？',
                description: '将重置为 米 (m) · 度分秒 · 坐标 3 位 · 秒 1 位',
                confirmLabel: '恢复默认',
                onConfirm: () async {
                  await s.resetInputDefaults();
                  if (!context.mounted) return;
                  SurveyToast.success(context, '已恢复默认录入参数');
                },
                builder: (ctx, open) => ChoiceTile(
                  icon: Icons.tune_rounded,
                  iconColor: IosColors.orange(scheme.brightness),
                  title: '恢复默认录入参数',
                  subtitle: '重置长度量级、角度格式与显示小数位',
                  onTap: open,
                ),
              ),
              Divider(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
                height: 0.5,
                thickness: 0.5,
                indent: Insets.l,
                endIndent: Insets.l,
              ),
              ChoiceTile(
                icon: Icons.cleaning_services_outlined,
                iconColor: IosColors.red(scheme.brightness),
                title: '清空全部本地草稿',
                subtitle: savedDraftCount == 0
                    ? '当前没有已保存的工具草稿'
                    : '当前共保存 $savedDraftCount 个工具页的草稿输入',
                onTap: () async {
                  if (drafts == null || savedDraftCount == 0) {
                    SurveyToast.info(context, '当前没有可清空的本地草稿');
                    return;
                  }
                  final confirmed = await SurveyModal.confirm(
                    context,
                    title: '清空全部本地草稿？',
                    subtitle: '不可撤销的本地清理操作',
                    message: '将删除全部 $savedDraftCount 个工具页的已保存输入，且无法恢复。',
                    confirmLabel: '确认清空',
                    destructive: true,
                  );
                  if (!confirmed || !context.mounted) return;
                  await drafts.clearAll();
                  if (!context.mounted) return;
                  SurveyToast.success(context, '已清空全部本地草稿');
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: Insets.l),
        const SectionHeader(title: '关于'),
        const SizedBox(height: Insets.s),
        SurfaceCard(
          padding: const EdgeInsets.all(Insets.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.architecture,
                      color: scheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: Insets.m),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '工程测量',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '版本 $kAppVersion · 离线计算',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  const Flexible(
                    child:
                        Pill(label: 'Android · Windows', tone: PillTone.info),
                  ),
                ],
              ),
              const SizedBox(height: Insets.m),
              Text(
                '包含 ${kFormulaLibrary.length} 条内置公式，覆盖坐标反算与放样、'
                '导线与水准平差、圆曲线与缓和曲线、竖曲线、面积与土方、'
                '精度评定与单位换算。所有计算在本地完成，不上传任何数据。'
                '计算结果用于辅助作业，正式成果请按规范复核。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> _showOverlayShowcase(BuildContext context) {
  return SurveyModal.show<void>(
    context,
    title: '弹出层与反馈组件规范',
    subtitle: '区分使用场景：文字提示 / 轻提示 / 警告 / 模态弹窗 / 气泡确认',
    icon: Icons.layers_outlined,
    tone: ModalTone.info,
    maxWidth: 500,
    child: const _OverlayShowcaseBody(),
    actionsBuilder: (dialogCtx) => [
      FilledButton(
        onPressed: () => Navigator.of(dialogCtx).pop(),
        child: const Text('完成预览'),
      ),
    ],
  );
}

class _OverlayShowcaseBody extends StatefulWidget {
  const _OverlayShowcaseBody();

  @override
  State<_OverlayShowcaseBody> createState() => _OverlayShowcaseBodyState();
}

class _OverlayShowcaseBodyState extends State<_OverlayShowcaseBody> {
  bool _showClosableAlert = true;

  Widget _sectionLabel(String name, String badge, Color color, String desc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Insets.s,
          runSpacing: Insets.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              name,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          desc,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.45,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sectionLabel(
          '1. Tooltip · 文字提示',
          '文字提示',
          IosColors.green(Theme.of(context).brightness),
          '鼠标悬停或点击问号图标展示补充说明，不打断当前测量录入。',
        ),
        const SizedBox(height: Insets.s),
        Wrap(
          spacing: Insets.s,
          runSpacing: Insets.s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('限差公式说明', style: TextStyle(fontSize: 12.5)),
                SizedBox(width: 4),
                InfoHintTooltip(
                  message: '四等水准限差 ±20√L mm；视距差单站 ≤ 5 m，累计 ≤ 10 m。',
                ),
              ],
            ),
            SurveyTooltip(
              message: '快捷键 Ctrl + K 可打开全局工具速搜',
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.touch_app_outlined, size: 15),
                label: const Text('悬停 / 长按触发', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.l),
        _sectionLabel(
          '2. Toast · 轻提示',
          '轻提示',
          IosColors.blue(Theme.of(context).brightness),
          '底部居中自动消失，计算成功与操作结果统一在底部轻量反馈。',
        ),
        const SizedBox(height: Insets.s),
        Wrap(
          spacing: Insets.xs,
          runSpacing: Insets.xs,
          children: [
            FilledButton.tonal(
              onPressed: () => SurveyToast.info(context, '已切换输入量级为 厘米 (cm)'),
              style:
                  FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('信息 Toast', style: TextStyle(fontSize: 12)),
            ),
            FilledButton.tonal(
              onPressed: () => SurveyToast.success(context, '成果表已复制到剪贴板'),
              style:
                  FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('成功 Toast', style: TextStyle(fontSize: 12)),
            ),
            FilledButton.tonal(
              onPressed: () => SurveyToast.warning(context, '请先填满至少一组完整测站'),
              style:
                  FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('警告 Toast', style: TextStyle(fontSize: 12)),
            ),
            FilledButton.tonal(
              onPressed: () => SurveyToast.error(context, '导出失败：无目标写入权限'),
              style:
                  FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('错误 Toast', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: Insets.l),
        _sectionLabel(
          '3. Alert · 警告提示',
          '警告提示',
          IosColors.orange(Theme.of(context).brightness),
          '页面内嵌常驻横幅，清晰交代超限原因或参数缺失，可选择关闭。',
        ),
        const SizedBox(height: Insets.s),
        if (_showClosableAlert)
          SurveyAlert(
            tone: AlertTone.warning,
            title: '闭合差超限提醒',
            message: '当前路线实测闭合差超出规范限差，请复核前后视黑红面读数。',
            closable: true,
            onClose: () => setState(() => _showClosableAlert = false),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showClosableAlert = true),
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('重新展示 Alert 横幅'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
        const SizedBox(height: Insets.l),
        _sectionLabel(
          '4. Modal · 模态弹窗',
          '模态弹窗',
          IosColors.red(Theme.of(context).brightness),
          '居中遮罩阻塞后台操作，用于复杂编辑或不可逆的高危二次确认。',
        ),
        const SizedBox(height: Insets.s),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () async {
              final ok = await SurveyModal.confirm(
                context,
                title: '确认覆盖现有手簿数据？',
                subtitle: '模态二次确认示例',
                message: '点击确认后将继续执行不可逆重置动作，点击取消则安全返回。',
                confirmLabel: '确认执行',
                destructive: true,
              );
              if (!context.mounted) return;
              SurveyToast.info(context, ok ? '模态框选择了：确认执行' : '模态框已取消');
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 15),
            label: const Text('触发确认 Modal'),
            style:
                OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ),
        const SizedBox(height: Insets.l),
        _sectionLabel(
          '5. Popconfirm · 气泡确认框',
          '气泡确认框',
          IosColors.indigo(Theme.of(context).brightness),
          '就近贴附在触发按钮旁进行轻量确认，无需全屏黑幕打断视域。',
        ),
        const SizedBox(height: Insets.s),
        Align(
          alignment: Alignment.centerLeft,
          child: SurveyPopconfirm(
            title: '删除此测站记录？',
            description: '就近轻量确认，点击空白处也可取消',
            confirmLabel: '删除',
            destructive: true,
            onConfirm: () => SurveyToast.success(context, '已通过 Popconfirm 确认'),
            builder: (ctx, open) => FilledButton.tonalIcon(
              onPressed: open,
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('测试 Popconfirm'),
              style:
                  FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    this.helper,
    this.onMinus,
    this.onPlus,
  });

  final String label;
  final String value;
  final String? helper;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (helper != null)
                Text(
                  helper!,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: onMinus,
          icon: const Icon(Icons.remove_circle_outline, size: 20),
        ),
        SizedBox(
          width: 28,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        IconButton(
          onPressed: onPlus,
          icon: const Icon(Icons.add_circle_outline, size: 20),
        ),
      ],
    );
  }
}
