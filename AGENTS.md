# Survey Pro (`survey-pro-open-source`) 工程协作红线

本文件为本仓库的 **Codex 与 Antigravity 共享工程红线（Engineering Guardrails）**。所有在本仓库中执行的界面改动、功能开发、重构与发布前验证均须严格遵守以下规范。

---

## 1. Windows 与 Android 壳层红线

- **窗口与主工作区**：Windows 使用系统原生标题栏及窗口控件。Windows 和 Android 的工作区使用单层页头，侧栏关闭时占宽 0dp。
- **统一侧栏**：Windows 与 Android 横竖屏从页面左上圆钮展开或隐藏侧栏。宽屏展开时使用 280dp 分栏，手机竖屏和窄窗使用覆盖式侧栏。点击 Survey Pro 返回首页，顶部提供全局搜索与坐标预设气泡，底部固定「新建测量」与「设置」。
- **首页入口**：顶部「继续上次」与「工具库」使用两张等高卡片。宽屏 LivePlot 分屏从首页操作区打开。
- **Android 竖屏底栏**：手机和平板默认隐藏底栏。开启「设置 → 外观与导航」中的竖屏选项后，一级页面显示四项 Liquid Glass 底栏。工具页支持系统返回、260ms Cupertino 跟手右滑和「更多操作 → 返回」。

---

## 2. Android 性能红线

- **禁止动画期实时模糊**：Android 滚动或路由转场期间，禁止对大面积区域实时应用 `BackdropFilter(ImageFilter.blur)`。
- **轻量半透明材质替代**：悬浮顶栏、底部导航与弹窗遮罩在 Android 上应使用**轻量高不透明度半透明底色 + 1px 柔和描边**，避免高开销实时离屏模糊。
- **导航过渡**：常驻侧栏平级切换使用 220ms 顺序淡穿，前 30% 仅淡出旧页，后 70% 仅淡入新页并从 0.985 复位至 1.0。Android 竖屏底栏采用 180ms 顺序淡穿与滑动选中指示器。侧栏用 240ms 和 Cubic(0.22, 1.0, 0.36, 1.0) 在 0dp 和完整宽度间过渡。侧栏和工作区在动画期间暂停玻璃模糊。动画层使用 `RepaintBoundary`，遵循系统减少动态效果设置。
- **重型组件延迟构建与重绘隔离**：重型图表（`LivePlot` / `SurveyCharts`）与长表格（`WideTable`）须延后至路由或缓存工具页切换结束后再构建。双栏工具从首帧保留完整表单与图表列，图表在等尺寸静态占位上通过 140ms 淡入。使用 `RepaintBoundary` 严格隔离，并收紧自定义画笔的 `shouldRepaint` 判断条件。

---

## 3. 顶栏与「更多操作」红线

- **共用测量页头**：Windows 和 Android 使用同一层工具页头，包含左上圆形侧栏开关、标题、行内草稿状态、两段直切单位、自定义置顶动作与纵向「更多操作」。极窄 Windows 工作区可在同一页头内将控件下移一行。从首页或工具库进入工具及点击返回时使用 260ms 不透明方向转场，宽屏偏移 12%，Android 竖屏全幅滑动并保留跟手边缘返回，底层工作区带视差与最多 12% 压暗。
- **禁止重复教程钮**：测量页右上角严禁显示重复的 `?` 教程按钮。
- **草稿状态位置**：草稿保存状态（如 `已保存 HH:mm` / `草稿未保存` + 状态圆点）必须展示在**主功能标题右侧同行**。
- **单位快捷胶囊**：左段直接循环 `m → cm → mm → m`，右段直接循环 `DMS → DD → RAD → DMS`。同步 `AppSettings`，提供短提示并遵循触感反馈设置。小数位精度在设置页调整。
- **精简「更多操作」**：
  - 「更多操作」菜单中**不得包含** Undo / Redo。
  - 重复的 `Export / Excel / Image` 等导出项必须合并为**唯一「导出」入口**。
- **可自定义顶栏快捷动作**：支持配置 **1–3 个**可自定义顶栏快捷动作并持久化至 `AppSettings`；已置顶到顶栏的动作，应避免在「更多操作」中重复出现。

---

## 4. 全量本地化红线

- **100% 走 `l10n`**：全部 UI 文案、`Tooltip`、`InputDecoration.hintText`、`TextEditingController` 默认值、`ToolDef.subtitle`、结构化错误提示，以及 **PNG / XLSX / CSV / TXT** 离屏导出物均须 100% 通过 `l10n` 获取。
- **回退策略**：小语种缺失译文统一回退至英文（`en`）。
- **Zero-CJK 巡检**：在 `Locale('en')` 下严禁残留任何 CJK 汉字（正则 `[\u4e00-\u9fff]`），覆盖范围包括全部页面组件与上述四种离屏导出格式。

---

## 5. 外业人性化与验证门禁

- **外业交互体验**：
  - 核心成果读数支持点击复制，并触发 `HapticFeedback.selectionClick()` 触觉反馈。
  - 提供「外业保持屏幕常亮」开关，满足外业连续测量场景。
- **提交前强制门禁**（在 `app/` 目录执行）：
  每次提交前必须全部通过以下三项检查：
  1. `flutter analyze --no-version-check`
  2. `flutter test --no-version-check`
  3. `flutter build apk --debug --no-version-check`

---

## 6. 视觉光学对齐红线（Optical Alignment Guardrails）

- **中英混排与等宽数字垂直居中**：全局通过 `DefaultTextHeightBehavior(textHeightBehavior: kSurveyTextHeightBehavior)`（`applyHeightToFirstAscent: false`、`applyHeightToLastDescent: false`、`leadingDistribution: TextLeadingDistribution.even`）与 `TextTheme` / `monoNumber` 的 `TextLeadingDistribution.even` 消除 CJK、Latin 与等宽数字的基线上下偏移；禁止在按钮、胶囊、列表行内使用硬编码顶部/底部不对称补丁偏置文字。
- **顶栏水平中线对齐**：测量页与主工作区悬浮顶栏统一使用冻结常量 `kTopBarTopInset = 12`、`kTopBarHeight = 44`、`kTopBarButtonSize = 40`；同一水平行内按钮、标题、状态圆点与单位胶囊中心 Y 偏差须 `<= 1.0px`。
- **侧栏图标槽与底部操作栏对齐**：侧栏导航项与快捷入口图标统一包裹在 `kSidebarIconSlotWidth = 24`（`24dp`）居中槽位内；侧栏底部「新建测量」与「设置」操作按钮保持中心 Y 与底边齐平。
- **加宽侧栏与弹性字号缩放**：桌面/横屏展开侧栏宽度保持 `276–288dp`（冻结基线 `kSidebarExpandedWidth = 280`），竖屏抽屉宽度取 `80–82%`（上限 `320dp`）；系统 DPI 与字体缩放遵循 `0.85x–1.35x` 区间，标签与按钮采用弹性 `minHeight` 搭配 `maxLines: 1` + `TextOverflow.ellipsis`，并保持首页/工具卡片与输入框上下左右内边距对称对齐。
