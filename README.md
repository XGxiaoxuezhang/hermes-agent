<p align="center">
  <img src="assets/banner.png" alt="Hermes Agent" width="100%">
</p>

# Hermes Agent 中文 Windows 二开版

这是基于 [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) 的中文二开分支，重点面向 **原生 Windows** 使用场景，不再要求必须跑在 WSL 里。

当前二开分支：`windows-dashboard-i18n`  
默认网页入口：`http://127.0.0.1:9119`

## 本分支改动

- **中文化优先**：网页控制台、聊天页、配置页、插件页等主要界面已做中文化处理。
- **原生 Windows 适配**：修复网关停止/重启、PID 检测、编码、路径识别等 Windows 问题。
- **不再误判 WSL**：Agent 会明确知道自己运行在 native Windows；`/f/code` 是 Git Bash 的 Windows 盘符路径，不是 `/mnt/f` WSL 路径。
- **网页聊天可用**：Dashboard 内置终端风格聊天界面，可以直接在网页里对话。
- **网页配置模型和 Key**：模型、Provider、API Key、基础配置尽量在网页里完成，不再强制手改配置文件。
- **Windows 一键安装脚本**：新机器可以从 GitHub 直接拉取本分支并安装。
- **Dashboard 成品模式**：日常只需要 `9119`，不需要同时开 Vite 的 `5173`。

## 新机器一键安装

Hermes 本身运行不要求管理员权限。脚本会自动检查这些依赖；缺失时会优先使用 `winget --scope user` 做用户级安装：

- Git for Windows: https://git-scm.com/download/win
- Node.js 22 或更高版本: https://nodejs.org/
- Python 3.11-3.14；脚本会优先使用 `py -3.14`，没有时再退到 `py -3.13` 或 `py -3.11` 创建虚拟环境

如果依赖包不支持用户级安装，`winget` 可能弹出管理员/UAC 请求。接受即可继续；如果你取消了，需要手动安装对应依赖后重跑。没有 `winget` 时脚本也会提示手动安装地址。

然后在 PowerShell 里运行：

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/XGxiaoxuezhang/hermes-agent/windows-dashboard-i18n/scripts/windows/install-from-github.ps1 | iex"
```

默认安装到：

```text
%LOCALAPPDATA%\HermesAgent\hermes-agent
```

通常是：

```text
C:\Users\<你的用户名>\AppData\Local\HermesAgent\hermes-agent
```

指定安装目录，例如安装到 `F:\code\hermes-agent`：

```powershell
powershell -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/XGxiaoxuezhang/hermes-agent/windows-dashboard-i18n/scripts/windows/install-from-github.ps1))) -InstallDir 'F:\code\hermes-agent'"
```

安装完成后打开：

```text
http://127.0.0.1:9119
```

## 已有源码目录的安装

如果你已经 clone 了仓库：

```powershell
cd F:\code\hermes-agent
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install-local.ps1
```

这个脚本会：

- 检查并尽量自动安装 Git、Node.js、Python 3.14
- 创建或修复 `venv`
- 使用支持 Python 3.14 的 `pywinpty 3.x`，旧环境不兼容时会自动修复
- 安装 `.[web,pty]`
- 安装前端依赖
- 构建网页资源
- 启动 Dashboard

## 日常启动

```powershell
cd F:\code\hermes-agent
powershell -ExecutionPolicy Bypass -File .\scripts\windows\run-dashboard.ps1
```

默认启动：

```text
http://127.0.0.1:9119
```

如果只是前端开发，需要热更新，才使用开发模式：

```powershell
cd F:\code\hermes-agent
powershell -ExecutionPolicy Bypass -File .\scripts\windows\dev-dashboard.ps1
```

开发模式会同时使用：

- `9119`：FastAPI 后端和成品 Dashboard
- `5173`：Vite 前端开发服务器，仅用于热更新

日常使用只需要 `9119`。

## 模型和 API Key 配置

进入 Dashboard 后，在网页里配置：

- 模型 Provider
- 模型名称
- API Key
- Base URL
- 终端后端
- 插件和工具

如果你仍想用命令行，也可以：

```powershell
.\venv\Scripts\python.exe -m hermes_cli.main model
.\venv\Scripts\python.exe -m hermes_cli.main setup
```

## 更新本二开分支

如果只是更新你 fork 里的最新二开版本：

```powershell
cd F:\code\hermes-agent
git pull origin windows-dashboard-i18n
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install-local.ps1
```

如果要同步上游 NousResearch 的更新，同时保留本分支二开改动：

```powershell
cd F:\code\hermes-agent
git remote add upstream https://github.com/NousResearch/hermes-agent.git
git fetch upstream
git checkout windows-dashboard-i18n
git rebase upstream/main
git push --force-with-lease origin windows-dashboard-i18n
```

如果已经添加过 `upstream`，第一行 `git remote add upstream ...` 不需要重复执行。

更新前建议打一个备份分支：

```powershell
git branch backup-before-upstream-update
```

## 二次开发

本分支推荐继续在源码目录开发：

```powershell
cd F:\code\hermes-agent
```

Python 代码是 editable install，改完重启 Dashboard 即可生效。

前端代码在：

```text
web/
```

改前端后构建：

```powershell
cd F:\code\hermes-agent\web
npm run build
```

然后重启：

```powershell
cd F:\code\hermes-agent
powershell -ExecutionPolicy Bypass -File .\scripts\windows\run-dashboard.ps1
```

## 常见问题

### 9119 和 5173 分别是什么？

- `9119` 是 Hermes Dashboard 后端和成品网页入口，日常使用访问它。
- `5173` 是 Vite 前端开发服务器，只在做前端开发热更新时使用。

### 为什么聊天里显示 `/f/code`？

这是 Git Bash 在 Windows 下表示 `F:\code` 的方式，不是 WSL。  
本分支已修复 `/mnt/f` 误判问题，Agent 会把 `/f/code/hermes-agent` 理解为 `F:\code\hermes-agent`。

### 网页打不开怎么办？

检查端口：

```powershell
Get-NetTCPConnection -LocalPort 9119 -State Listen
```

重新启动：

```powershell
cd F:\code\hermes-agent
powershell -ExecutionPolicy Bypass -File .\scripts\windows\run-dashboard.ps1
```

### 安装时 Python / pywinpty 报错怎么办？

直接重新跑：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install-local.ps1 -RecreateVenv
```

脚本会重建 Python 3.11-3.14 的虚拟环境，并安装兼容的 Windows PTY 依赖。

## 上游 Hermes Agent 能力简介

Hermes Agent 是 Nous Research 开源的自进化 AI Agent，支持：

- 多模型 Provider：Nous Portal、OpenRouter、OpenAI、Anthropic、Google、Kimi、MiniMax、z.ai/GLM、自定义 OpenAI 兼容端点等
- 终端工具、文件工具、网页搜索、浏览器工具、MCP、定时任务
- 记忆系统、技能系统、会话搜索
- CLI/TUI、网页 Dashboard、消息网关
- Telegram、Discord、Slack、WhatsApp、Signal 等平台网关
- Docker、SSH、Modal、Daytona、Singularity 等终端后端

上游文档：

```text
https://hermes-agent.nousresearch.com/docs/
```

## 许可证

MIT，详见 [LICENSE](LICENSE)。

本分支为个人二开版本；原始项目由 [Nous Research](https://nousresearch.com) 构建。
