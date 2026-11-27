# Survey Pro (`survey-pro-open-source`) 工程协作红线

本文件为本仓库的 **Codex 与 Antigravity 共享工程红线（Engineering Guardrails）**。所有在本仓库中执行的界面改动、功能开发、重构与发布前验证均须严格遵守以下规范。

---

## 1. Windows 与 Android 壳层红线

- **取消重复壳层**：Windows 和 Android 禁止渲染 Flutter 自绘全局标题栏与底部悬浮指令台。Windows 使用系统原生标题栏及窗口控件。
- **Android 横屏常驻分栏**：以 `Orientation.landscape` 判定，使用 `Row + Expanded` 布局实现可折叠侧边栏与主工作区常驻分栏。
- **Android 竖屏底栏**：以 `Orientation.portrait` 判定，覆盖手机和平板。竖屏隐藏左侧栏与 Push-Aside 抽屉。一级页面底部居中展示 Liquid Glass 导航胶囊，仅包含首页、工具库、LivePlot、设置。每项触控热区至少 48dp，搜索入口放在主页或工具库。
- **Android 竖屏二级页**：进入工具页后隐藏一级底栏，保留单层悬浮液态玻璃顶栏与 260ms Cupertino 跟手边缘右滑返回。
- **Windows 常驻侧栏**：沿用 Android 横屏的分栏、侧栏搜索和自定义常用工具。在任何窗口方向保留左侧栏，宽度不足 720dp 时暂用 56dp 图标轨，拉宽后恢复用户的折叠设置。禁止切换到 Android 竖屏底部导航。宽屏 LivePlot 分屏从侧栏打开。

---

## 2. Android 性能红线

- **禁止动画期实时模糊**：Android 滚动或路由转场期间，禁止对大面积区域实时应用 `BackdropFilter(ImageFilter.blur)`。
- **轻量半透明材质替代**：悬浮顶栏、底部导航与弹窗遮罩在 Android 上应使用**轻量高不透明度半透明底色 + 1px 柔和描边**，避免高开销实时离屏模糊。
- **导航过渡**：常驻侧栏平级切换使用 220ms 顺序淡穿，前 30% 仅淡出旧页，后 70% 仅淡入新页并从 0.985 复位至 1.0。Android 竖屏底栏采用 180ms 顺序淡穿与滑动选中指示器。侧栏宽度过渡为 240ms，收起时先淡出标签，侧栏和工作区在动画期间暂停玻璃模糊。动画层使用 `RepaintBoundary`，遵循系统减少动态效果设置。
- **重型组件延迟构建与重绘隔离**：重型图表（`LivePlot` / `SurveyCharts`）与长表格（`WideTable`）须延后至路由转场动画结束后再构建，使用 `RepaintBoundary` 严格隔离，并收紧自定义画笔的 `shouldRepaint` 判断条件。

---

## 3. 顶栏与「更多操作」红线

- **共用测量页头**：Windows 和 Android 使用同一层工具页头，包含标题、行内草稿状态、两段直切单位、自定义置顶动作与纵向「更多操作」。极窄 Windows 工作区可在同一页头内将控件下移一行。从首页或工具库进入工具及点击返回时使用 260ms 不透明方向转场，宽屏偏移 12%，Android 竖屏全幅滑动并保留跟手边缘返回，底层工作区带视差与最多 12% 压暗。
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
