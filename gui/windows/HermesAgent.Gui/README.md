# Hermes Agent Windows 原生控制台

这是 Hermes Agent 的 Windows WPF 桌面控制台，不是 WebView。它复用现有
Hermes Python 后端和 Windows 脚本，用来处理本机安装、更新、网关和日志。

## 当前功能

- 中文原生界面
- 控制台后端状态轮询
- 消息网关运行状态、PID、活跃会话数
- 启动 / 停止控制台后端
- 重启消息网关
- 打开可见终端执行更新，方便观察更新日志
- 查看控制台日志、网关日志、更新日志、重启日志
- 打开仓库目录、配置文件、密钥文件和日志目录
- 复制本地控制台地址
- 自动刷新开关

## 构建

需要 .NET 6 SDK 或更新的 Windows Desktop SDK：

```powershell
cd gui\windows\HermesAgent.Gui
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

输出文件：

```text
bin\Release\net6.0-windows\HermesAgent.Gui.exe
```

## 运行说明

- 默认端口：`9119`
- 默认仓库目录会自动从程序所在位置向上查找
- 可用环境变量 `HERMES_REPO_DIR` 指定仓库目录
- 密钥仍由 Hermes 写入原有 env 文件；控制台只显示路径，不展示密钥值
