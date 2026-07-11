# Codex 额度菜单栏

[English](README_EN.md)

macOS 原生菜单栏工具，实时显示 Codex 的 5 小时与本周剩余额度。

### 功能

- 菜单栏显示：`5h 72% · W 54%`
- 左键刷新并打开详情窗口
- 右键菜单：立即刷新、显示/隐藏详情、打开 Codex 用量页、开机启动、退出
- 详情窗口显示套餐、两类额度进度、重置时间和可用重置额度（服务端提供时）
- 详情窗口可拖动且始终置顶

### 构建与运行

首次使用前，请在 Codex Desktop 或 CLI 中完成登录。

```bash
./Scripts/build-app.sh
open dist/CodexQuotaMenuBar.app
```

构建产物位于 `dist/CodexQuotaMenuBar.app`，是本地未签名应用。应用只读取 `~/.codex/auth.json`（或 `CODEX_HOME/auth.json`），仅向 `chatgpt.com` 的 Codex 额度端点发送现有登录 token；不会保存 token、聊天内容或原始接口响应。
