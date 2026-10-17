# ProxyPin 首页改版 · 实现简报（交接给实现方）

## 设计依据
高保真设计稿 + 每区块实现备注：`docs/design/homepage.html`（浏览器打开，共 6 节：桌面首页 / 设置菜单+规则页 / 快捷工具栏 / 桌面详情 4Tab / 手机端 3 屏 / 手机详情 4Tab）。**实现前先通读该文件。**

## 任务清单（按顺序，每步独立提交）

### ① 桌面详情面板 Overview（`lib/ui/content/panel.dart`）
- 顶部加标题栏：Method + 完整 URL + 快捷操作（复制 / 重发 / 收藏），仅桌面嵌入模式加，不影响手机端与独立窗口模式（`widget.title != null` 时保持现状）。
- 首 Tab `General` 改名并重做为 **Overview**：聚合卡（状态码 / 协议 / 耗时 / 大小 / 远程地址 / 请求时间 / App）+ 响应体预览卡（JSON/Raw/Preview 切换）。原 General 字段不丢。
- 请求 / 响应 / Cookies / WebSocket / SSE / MQTT 逻辑不动。

### ② 设置菜单瘦身 + 左侧「规则」页（桌面）
- `lib/ui/desktop/setting/setting.dart`：`menuChildren` 从 13 项减到 7 项：代理▸ / 域名过滤 / Hosts / 外部代理 / 弱网 / MCP 服务 / 关于，加分组标签与图标。
- `lib/ui/desktop/left_menus/navigation.dart` + `desktop.dart`：NavigationRail 在 历史 与 工具箱 之间加「规则」；`navigationView` 对应加一页。
- 新建规则页（参考 `docs/design/homepage.html` 规则页 mock）：请求屏蔽 / 重写 / 映射 / 加密 / 脚本 / 断点 6 行，每行显示 启用状态 + 规则数，点击复用 `setting.dart` 里现有的打开逻辑（MultiWindow.openWindow / dialog），**被打开的页面零改动**。

### ③ 快捷工具栏（桌面，`lib/ui/desktop/toolbar/toolbar.dart`）
- 功能注册表：id / 图标 / 名称 / 启动动作（动作复用现有 openWindow/dialog 调用）。
- `AppConfiguration` 持久化有序 id 列表（默认：重写/映射/脚本）。
- 工具栏 SSL 图标后渲染已固定的纯图标按钮（样式与其他 IconButton 一致，名称用 tooltip）。
- 末尾 ⋯ 弹流量控制菜单（6 项，行尾 📌 固定/取消固定），底部「自定义快捷工具栏…」打开排序面板（chip 拖拽排序 + 恢复默认）。
- **注意**：项目用定制 Flutter SDK，`ReorderableListView` 的 `onReorderItem` 回调 newIndex **已减过 1**，业务代码不要再减。
- 可固定范围：流量控制 6 项 + 设置菜单项；工具箱功能不参与。

### ④ 手机端（`lib/ui/mobile/`）
- `mobile.dart` 底部导航 4 项不变，「配置」换成「规则」：请求 / 规则 / 工具箱 / 设置。
- 规则 tab = 桌面规则页的移动版（`Navigator.push` 复用现有页面）。
- 原「配置」页（`menu/bottom_navigation.dart` ConfigPage）分流：流量控制 6 项 → 规则 tab；收藏 / 历史 → 请求页 ⋮ MoreMenu；其余（代理 / 过滤 / Hosts / 外部代理 / 弱网 / 环境变量 / MCP / 关于）并入「设置」tab 页面。

## 硬性约束
1. **不准动** `lib/ui/desktop/request/domains.dart` 的数据结构（此前重构被否，只允许最小改动）。
2. 文案走国际化：`lib/l10n/app_zh.arb` + `app_en.arb` 等，用 `AppLocalizations`，不要硬编码中文。
3. 视觉规范：主色 #4A6CF7、圆角 8–10px、语义色 GET 绿 / POST 橙 / PUT 蓝 / DELETE 红 / WS 紫；代码与数值用等宽字体。
4. 代理开关样式（用户拍板）：浅色边框胶囊 = 电源图标 + 绿点 +「运行中 · :9099」，停止时灰点 +「已停止」；运行中带淡绿底 #F0F8F2 + 绿色描边。
5. 每步 `flutter analyze` 无新增警告后再提交。
