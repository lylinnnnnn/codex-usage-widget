<div align="center">

<p>
<img src="Assets/simple-app-icon.png" alt="Simple App 图标" width="96">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
<img src="Assets/detailed-app-icon.png" alt="Detailed App 图标" width="96">
</p>

# Codex Usage Widgets

**一个仓库 · 两个 macOS App**

[English](README.md) | **简体中文**

两个原生 macOS 小工具，让你无需打开网页，也能把 Codex 使用额度直接放在桌面上查看。

一个保持极简，只显示最核心的使用情况；另一个会展示本地 Codex 服务实际返回的使用周期与 Credits 数据。

</div>

---

## APP 01

# Simple App

极简桌面组件：一条竖向使用进度条，上方显示百分比，下方显示“Codex”。

<table>
<tr>
<td width="56%" align="center">
<img src="Assets/codex-simple-app.jpg" alt="Simple App 截图" width="100%">
</td>
<td width="44%" valign="top">

### 安静、简单的一版。

适合只想快速看一眼 Codex 剩余使用情况的人。

- 单条竖向使用进度条
- 进度条上方显示百分比
- 下方显示“Codex”标签
- 尽可能少占用桌面空间

</td>
</tr>
</table>

---

## APP 02

# Detailed App

更完整的 Codex 使用情况组件，内置两种显示模式：自适应的桌面胶囊模式，以及轻量的菜单栏 Notch Compact。

<table>
<tr>
<td width="56%" align="center">
<img src="Assets/codex-detailed-app.jpg" alt="Detailed App 截图" width="100%">
</td>
<td width="44%" valign="top">

### 需要更多信息时，就看这一版。

在胶囊模式下，Detailed App 会根据当前账户实际可用的数据自动改变布局。

- 可用时显示 5 小时和 Weekly 使用情况
- 账户返回 Monthly 数据时显示月度使用情况
- 只有存在 Credits 余额时才显示 Credits
- 菜单栏可切换显示模式、查看使用详情、刷新；在胶囊模式下显示/隐藏组件，以及退出

</td>
</tr>
</table>

---

## 显示模式

# 两种方式，让使用情况保持可见

`CodexUsageCapsuleWidget` 有两种互斥的显示模式。可从菜单栏选择，选择结果会在 App 重启后保留。

<table>
<tr>
<td width="50%" valign="top">

### 胶囊模式

原有的自适应悬浮胶囊显示会根据可用数据调整，包含 5 小时和 Weekly 使用情况，以及可用时的 Monthly 使用情况和 Credits。

</td>
<td width="50%" valign="top">

### Notch Compact

v0.2.0 新增的轻量标准 macOS 菜单栏模式。紧凑的 Micro Pill 会显示 `5h 25% · W 88%`；悬停可看到最近更新时间，点击可访问现有的使用详情和刷新操作。

<img src="Assets/notch-compact-mode.jpg" alt="Notch Compact 菜单栏截图" width="100%">

</td>
</tr>
</table>

---

## DETAILED APP · 三种状态

# 胶囊模式的自适应数据状态

以下是胶囊模式的自适应数据状态，不是额外的显示模式。

<table>
<tr>
<td width="33%" align="center">

### 5-hour + Weekly

<img src="Assets/codex-state-5h-weekly.jpg" alt="5-hour 和 Weekly 状态" width="100%">

当两个使用周期都可用时，同时显示两个使用指标。

</td>
<td width="33%" align="center">

### 5-hour + Weekly + Credits

<img src="Assets/codex-state-5h-weekly-credits.jpg" alt="5-hour Weekly 和 Credits 状态" width="100%">

只有账户存在可用余额时，才会显示 Credits。

</td>
<td width="33%" align="center">

### Monthly + Credits

<img src="Assets/codex-state-monthly.jpg" alt="Monthly 状态" width="100%">

显示 Monthly 使用情况；有 Credits 时同时显示余额。

</td>
</tr>
</table>

---

## 菜单栏

# 常用控制就在手边

可在 Capsules 和 Notch Compact 之间切换，查看使用详情、刷新；适用时显示或隐藏胶囊组件，或退出。

<p align="center">
<img src="Assets/codex-menu-bar.jpg" alt="菜单栏控制" width="100%">
</p>

---

## 特点

# 原生、轻量、本地优先

<table>
<tr>
<td width="33%"><strong>桌面优先</strong><br>不用打开网页，也能随时看到 Codex 使用情况。</td>
<td width="33%"><strong>自适应数据</strong><br>Detailed App 只显示本地服务实际返回的使用数据。</td>
<td width="33%"><strong>菜单栏控制</strong><br>可切换显示模式、刷新，适用时显示/隐藏胶囊组件，或退出 App。</td>
</tr>
<tr>
<td><strong>本地优先隐私</strong><br>App 不读取浏览器 Cookie、不抓取凭据、不收集遥测数据，也不会上传账户数据。</td>
<td><strong>可靠刷新</strong><br>会在本地 Codex 事件发生时、每 60 秒、Mac 唤醒后以及手动操作时更新。</td>
<td><strong>原生 macOS</strong><br>使用 SwiftUI 和 AppKit 构建。</td>
</tr>
</table>

---

## 安装

# 下载 Release

预构建 ZIP 可以直接从 [GitHub Releases](https://github.com/lylinnnnnn/codex-usage-widget/releases) 下载。根据你想看到的信息多少，选择对应 App：

- **CodexUsageWidget** — 极简的单进度条组件
- **CodexUsageCapsuleWidget** — 可在胶囊模式和 Notch Compact 之间切换的自适应详细组件

当前 v0.2.0 安装包适用于运行 macOS 13 Ventura 或更高版本的 Apple Silicon（arm64）Mac。下载对应 ZIP，解压后即可得到相应的 `.app`，也可以将它移动到 `/Applications`。

v0.2.0 使用 ad-hoc 签名，目前还没有经过 Apple 公证，因此首次打开时 macOS 可能会要求你确认。可以在 Finder 中右键 App 并选择 **打开**，或者前往 **系统设置 → 隐私与安全性** 允许打开。

<table>
<tr>
<td width="50%" valign="top">

### 系统要求

- macOS 13 Ventura 或更高版本
- 当前预构建安装包需要 Apple Silicon（arm64）
- 从源码构建需要 Swift 6
- 本机已安装 Codex
- 已登录 Codex / ChatGPT 账户

</td>
<td width="50%" valign="top">

### 日常使用

在本机已安装 Codex 并登录账户的情况下，启动任意一个 App 即可。

你可以在桌面上移动组件位置，并通过菜单栏进行常用操作。

两个 App 可以单独运行，也可以同时运行。

</td>
</tr>
</table>

---

## 从源码构建

# 本地构建

```bash
git clone https://github.com/lylinnnnnn/codex-usage-widget.git
cd codex-usage-widget
swift test
```

### Simple App · CodexUsageWidget

```bash
swift build --product CodexUsageWidget
./Scripts/build-app.sh CodexUsageWidget
open build/CodexUsageWidget.app
```

### Detailed App · CodexUsageCapsuleWidget

```bash
swift build --product CodexUsageCapsuleWidget
./Scripts/build-app.sh CodexUsageCapsuleWidget
open build/CodexUsageCapsuleWidget.app
```

---

## 许可证与声明

# 项目信息

**许可证：** MIT。详见 [LICENSE](LICENSE)。

**声明：** 本项目为非官方项目，与 OpenAI 无隶属关系，也未获得 OpenAI 官方背书。

Codex、ChatGPT、OpenAI 及相关名称和商标归其各自权利人所有。

---

<p align="center">
© 2026 lylinnnnnn. 保留所有权利。<br>
Logo 与 App 图标不授权他人重复使用或再分发。
</p>
