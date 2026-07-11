# Codex Quota Menu Bar

macOS 原生菜单栏工具：显示 Codex 的 5 小时与本周剩余额度。

运行 `./Scripts/build-app.sh` 后，在 `dist/CodexQuotaMenuBar.app` 得到本地未签名应用。首次运行前，请在 Codex Desktop 或 CLI 完成登录。应用仅读取 `~/.codex/auth.json`（或 `CODEX_HOME/auth.json`），并只向 `chatgpt.com` 的额度端点发送既有登录 token；不会保存 token、聊天内容或原始接口响应。

左键点击菜单栏项目会刷新并打开详情；右键提供立即刷新、显示/隐藏详情、打开 Codex 用量页面和退出。详情窗口可拖动且始终置顶。
