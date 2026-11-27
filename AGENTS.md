# Survey Pro (`survey-pro-open-source`) 工程协作红线

本文件为本仓库的 **Codex 与 Antigravity 共享工程红线（Engineering Guardrails）**。所有在本仓库中执行的界面改动、功能开发、重构与发布前验证均须严格遵守以下规范。

---

## 1. Android 壳层红线

- **严禁桌面端壳层**：Android 端严禁渲染桌面式全局顶栏（`_DesktopTopBar`）与底部悬浮指令台。
- **宽屏常驻分栏**：当满足 `width >= 720dp` 或 `landscape && width >= 640dp` 时，必须使用真 `Row + Expanded` 布局实现侧边栏与主工作区常驻分栏。
- **竖屏窄屏布局**：当竖屏宽度 `< 640dp` 时，必须使用 **Push-Aside 侧推抽屉** + **单层悬浮液态玻璃顶栏**，并保留 **Cupertino 跟手边缘右滑返回**。

---

## 2. Android 性能红线

- **禁止动画期实时模糊**：Android 滚动或路由转场期间，禁止对大面积区域实时应用 `BackdropFilter(ImageFilter.blur)`。
- **轻量半透明材质替代**：悬浮顶栏、侧推抽屉与弹窗遮罩在 Android 上应使用**轻量高不透明度半透明底色 + 1px 柔和描边**，避免高开销实时离屏模糊。
- **重型组件延迟构建与重绘隔离**：重型图表（`LivePlot` / `SurveyCharts`）与长表格（`WideTable`）须延后至路由转场动画结束后再构建，使用 `RepaintBoundary` 严格隔离，并收紧自定义画笔的 `shouldRepaint` 判断条件。

---

## 3. 顶栏与「更多操作」红线

- **禁止重复教程钮**：测量页右上角严禁显示重复的 `?` 教程按钮。
- **草稿状态位置**：草稿保存状态（如 `已保存 HH:mm` / `草稿未保存` + 状态圆点）必须展示在**主功能标题右侧同行**。
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
