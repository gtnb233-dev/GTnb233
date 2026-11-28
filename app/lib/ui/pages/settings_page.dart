import 'package:flutter/material.dart';
import '../widgets/compact_controls.dart';
import 'package:survey_core/survey_core.dart';

import '../../l10n/survey_strings.dart';
import '../../app_info.dart';
import '../../state/drafts.dart';
import '../../state/settings.dart';
import '../../theme/tokens.dart';
import '../../theme/workspace_layout.dart';
import '../../theme/ui_style.dart';
import '../page_scaffold.dart';
import '../widgets/widgets.dart';

/// 设置页：主题、角度格式、小数位与反馈。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.fullscreen = false});

  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final drafts = DraftScope.maybeOf(context);
    final savedDraftCount = drafts?.savedCount ?? 0;
    final scheme = Theme.of(context).colorScheme;
    return PageScaffold(
      fullscreen: fullscreen,
      title: '设置',
      caption: '显示约定与交互偏好，全部保存在本机',
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(Insets.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InputDecorator(
                decoration: InputDecoration(labelText: context.tr('语言')),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AppLanguage>(
                    key: const ValueKey('app-language'),
                    value: s.language,
                    isExpanded: true,
                    isDense: true,
                    items: [
                      for (final language in AppLanguage.values)
                        DropdownMenuItem(
                          value: language,
                          child:
                              Text(language.nativeName ?? context.tr('跟随系统')),
                        ),
                    ],
                    onChanged: (language) {
                      if (language != null) s.setLanguage(language);
                    },
                  ),
                ),
              ),
              const SizedBox(height: Insets.s),
              const LocalText(
                '界面语言已覆盖菜单、工具库、设置与主要计算页面。',
                style: TextStyle(fontSize: 11.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: Insets.l),
        const SectionHeader(title: '主题与显示'),
        const SizedBox(height: Insets.s),
        SurfaceCard(
          padding: const EdgeInsets.all(Insets.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LocalText(
                '主题模式',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: Insets.s),
              SurveySegmentedControl<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: LocalText('跟随系统'),
                    icon: Icon(Icons.brightness_auto_outlined, size: 17),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: LocalText('浅色'),
                    icon: Icon(Icons.light_mode_outlined, size: 17),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: LocalText('深色'),
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
          title: '外观与导航',
          caption: 'Unslop Graphite 哑光界面与液态玻璃效果',
        ),
        const SizedBox(height: Insets.s),
        SurfaceCard(
          padding: const EdgeInsets.fromLTRB(
            Insets.l,
            Insets.xs,
            Insets.l,
            Insets.xs,
          ),
          child: Column(
            children: [
              SurveySwitchTile(
                key: const ValueKey('skip-startup-animation'),
                contentPadding: EdgeInsets.zero,
                value: s.skipStartupAnimation,
                onChanged: s.setSkipStartupAnimation,
                title: const LocalText('跳过开屏动画（极速启动）'),
              ),
              const Divider(height: 1),
              if (WorkspaceHost.isAndroid(context)) ...[
                SurveySwitchTile(
                  key: const ValueKey('android-portrait-glass-nav-setting'),
                  contentPadding: EdgeInsets.zero,
                  value: s.portraitGlassNav,
                  onChanged: s.setPortraitGlassNav,
                  title: const LocalText('竖屏启用液态玻璃底部导航栏'),
                ),
                const Divider(height: 1),
              ],
              SurveySwitchTile(
                contentPadding: EdgeInsets.zero,
                value: s.floatingGlassNav,
                onChanged: s.setGlassNav,
                title: Text(
                  context.tr('液态玻璃'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  context.tr('弹层使用半透明背景'),
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              Divider(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
                height: 0.5,
                thickness: 0.5,
              ),
              Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                ),
                child: ExpansionTile(
                  key: const ValueKey('settings-advanced-appearance'),
                  initiallyExpanded: false,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: Insets.s),
                  title: const LocalText(
                    '高级外观',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    context.tr('传统 UI 风格与莫奈取色'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: Insets.xs),
                          const LocalText(
                            'UI 风格',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: Insets.s),
                          SurveySegmentedControl<UiStyle>(
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              textStyle: WidgetStatePropertyAll(
                                TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            segments: [
                              for (final style in UiStyle.values)
                                ButtonSegment(
                                    value: style,
                                    label: Text(context.tr(style.label))),
                            ],
                            selected: {s.uiStyle},
                            onSelectionChanged: (v) => s.setUiStyle(v.first),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            context.tr(s.uiStyle.description),
                            style: TextStyle(
                                fontSize: 11.5, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Insets.s),
                    Divider(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                      height: 0.5,
                      thickness: 0.5,
                    ),
                    SurveySwitchTile(
                      contentPadding: EdgeInsets.zero,
                      value: s.monet,
                      onChanged: s.setMonet,
                      title: const LocalText(
                        '莫奈调色',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      subtitle: const LocalText(
                        '用种子色生成整套 tonal 调色板；Android 12+ / Windows 支持自动跟随系统强调色',
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final seed in MonetSeed.values)
                            FilterChip(
                              label: Text(context.tr(seed.label)),
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
              const LocalText(
                '角度输入格式',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                context.tr(switch (s.angleMode) {
                  AngleInputMode.dmsCompact =>
                    '度分秒分格（度°/分′/秒″）：空格或小数点自动跳格，也支持粘贴 GG.MMSS',
                  AngleInputMode.decimalDegrees =>
                    '十进制度：90.5 表示 90°30′00″（亦兼容空格或小数点直填度分秒）',
                  AngleInputMode.radians => '弧度：π rad = 180°，请输入数值',
                }),
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Insets.s),
              SurveySegmentedControl<AngleInputMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: AngleInputMode.dmsCompact,
                    label: LocalText('度分秒'),
                  ),
                  ButtonSegment(
                    value: AngleInputMode.decimalDegrees,
                    label: LocalText('十进制度'),
                  ),
                  ButtonSegment(
                      value: AngleInputMode.radians, label: LocalText('弧度')),
                ],
                selected: {s.angleMode},
                onSelectionChanged: (v) => s.setAngleMode(v.first),
              ),
              const SizedBox(height: Insets.l),
              const LocalText(
                '长度输入量级',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                context.tr(
                    '当前按 {unit} 录入与显示（1 m = 100 cm = 1000 mm 自动换算，默认米制）', {
                  'unit':
                      '${context.tr(s.lengthUnit.label)} (${s.lengthUnit.symbol})'
                }),
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Insets.s),
              SurveySegmentedControl<LengthUnit>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: LengthUnit.meter,
                    label: LocalText('米 (m)'),
                  ),
                  ButtonSegment(
                    value: LengthUnit.centimeter,
                    label: LocalText('厘米 (cm)'),
                  ),
                  ButtonSegment(
                    value: LengthUnit.millimeter,
                    label: LocalText('毫米 (mm)'),
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
          child: Column(
            children: [
              SurveySwitchTile(
                contentPadding: EdgeInsets.zero,
                value: s.haptic,
                onChanged: s.setHaptic,
                title: const LocalText(
                  '触感反馈',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: const LocalText(
                  '按钮与复制结果时给出轻微振动',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
              Divider(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
                height: 0.5,
                thickness: 0.5,
              ),
              SurveySwitchTile(
                contentPadding: EdgeInsets.zero,
                value: s.keepScreenOn,
                onChanged: s.setKeepScreenOn,
                title: const LocalText(
                  '外业保持屏幕常亮',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: const LocalText(
                  '保持屏幕常亮，方便外业连续录数',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
            ],
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
                    : context.tr(
                        '当前共保存 {count} 个工具页的草稿输入', {'count': savedDraftCount}),
                onTap: () async {
                  if (drafts == null || savedDraftCount == 0) {
                    SurveyToast.info(context, '当前没有可清空的本地草稿');
                    return;
                  }
                  final confirmed = await SurveyModal.confirm(
                    context,
                    title: '清空全部本地草稿？',
                    subtitle: '不可撤销的本地清理操作',
                    message: context.tr('将删除全部 {count} 个工具页的已保存输入，且无法恢复。',
                        {'count': savedDraftCount}),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const LocalText(
                          '工程测量',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.tr(
                              '版本 {version} · 离线计算', {'version': kAppVersion}),
                          style: const TextStyle(fontSize: 11.5),
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
              Row(
                children: [
                  Flexible(
                    child: Text(
                      context.tr('计算核心引擎'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: Insets.s),
                  Expanded(
                    child: Text(
                      'SurveyCore · Rust FFI',
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.m),
              Text(
                context.tr(
                  '包含 {count} 条内置公式，覆盖坐标反算与放样、导线与水准平差、圆曲线与缓和曲线、竖曲线、面积与土方、精度评定与单位换算。所有计算在本地完成，不上传任何数据。计算结果用于辅助作业，正式成果请按规范复核。',
                  {'count': kFormulaLibrary.length},
                ),
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
        child: const LocalText('完成预览'),
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
              context.tr(name),
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
                context.tr(badge),
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
          context.tr(desc),
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LocalText('限差公式说明', style: TextStyle(fontSize: 12.5)),
                const SizedBox(width: 4),
                InfoHintTooltip(
                  message: context.tr('四等水准限差 ±20√L mm；视距差单站 ≤ 5 m，累计 ≤ 10 m。'),
                ),
              ],
            ),
            SurveyTooltip(
              message: context.tr('快捷键 Ctrl + K 可打开全局工具速搜'),
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.touch_app_outlined, size: 15),
                label: const LocalText('悬停 / 长按触发',
                    style: TextStyle(fontSize: 12)),
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
              child:
                  const LocalText('信息 Toast', style: TextStyle(fontSize: 12)),
            ),
            FilledButton.tonal(
              onPressed: () => SurveyToast.success(context, '成果表已复制到剪贴板'),
              style:
                  FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              child:
                  const LocalText('成功 Toast', style: TextStyle(fontSize: 12)),
            ),
            FilledButton.tonal(
              onPressed: () => SurveyToast.warning(context, '请先填满至少一组完整测站'),
              style:
                  FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              child:
                  const LocalText('警告 Toast', style: TextStyle(fontSize: 12)),
            ),
            FilledButton.tonal(
              onPressed: () => SurveyToast.error(context, '导出失败：无目标写入权限'),
              style:
                  FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              child:
                  const LocalText('错误 Toast', style: TextStyle(fontSize: 12)),
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
              label: const LocalText('重新展示 Alert 横幅'),
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
            label: const LocalText('触发确认 Modal'),
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
              label: const LocalText('测试 Popconfirm'),
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
                context.tr(label),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (helper != null)
                Text(
                  context.tr(helper!),
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
