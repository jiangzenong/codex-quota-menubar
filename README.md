# Codex 额度菜单栏

macOS 原生菜单栏工具，用于查看 Codex 当前的 5 小时与本周剩余额度。

## 如何运作

应用启动后会从本机 Codex 登录状态中读取已有凭据，并请求 Codex 的额度接口。结果以 `5h 72% · 7d 54%` 的形式显示在菜单栏中。

- 左键菜单栏额度：刷新并打开详情面板。
- 右键菜单栏额度：打开刷新、显示或隐藏面板、悬浮球、开机启动和退出等操作。
- 详情面板展示套餐、额度进度与重置时间；可拖动到合适位置。
- 收起详情面板后可切换为悬浮球，再次点击即可展开。

应用不会要求再次输入账号密码。首次使用前，请先在 Codex Desktop 或 Codex CLI 中完成登录。

## 下载

请从 [Releases](https://github.com/jiangzenong/codex-quota-menubar/releases/latest) 下载最新版本，无需克隆仓库或自行构建。

- Apple 芯片 Mac：`CodexQuotaMenuBar-macos-apple-silicon.zip`
- Intel 芯片 Mac：`CodexQuotaMenuBar-macos-intel.zip`

## 构建与启动

需要 macOS 和 Swift 6。

```bash
./Scripts/build-app.sh
open dist/CodexQuotaMenuBar.app
```

构建产物为 `dist/CodexQuotaMenuBar.app`。打包脚本会同时生成并写入应用图标。

## 安全与隐私

应用只读取已有的 Codex 登录凭据（`~/.codex/auth.json` 或 `CODEX_HOME/auth.json`），并仅向 `chatgpt.com` 的 Codex 额度端点发送该登录 token。它不会保存 token、聊天内容或原始接口响应。

## 常见问题

### 菜单栏没有显示额度

确认已登录 Codex Desktop 或 Codex CLI，然后在菜单栏图标上右键选择“立即刷新”。若仍没有数据，请重新登录 Codex 后重试。

### macOS 阻止打开应用

该应用为本地未签名应用。请在 Finder 中按住 Control 点击应用并选择“打开”，或前往“系统设置 → 隐私与安全性”允许打开。

### Finder 仍显示通用图标

重新运行 `./Scripts/build-app.sh`，并使用新生成的 `dist/CodexQuotaMenuBar.app` 替换旧文件。若 Finder 仍显示旧缓存，请关闭并重新打开对应 Finder 窗口。

### 找不到 Swift 或构建失败

安装 Xcode Command Line Tools 后重试：

```bash
xcode-select --install
```
