# Hermes Agent Windows GUI

Native WPF control panel for the local Hermes Agent install. It is intentionally
not a WebView: the GUI controls the existing Hermes Python backend through local
HTTP endpoints and the existing Windows scripts.

## First version

- Polls `http://127.0.0.1:9119/api/status`
- Starts and stops the local dashboard backend
- Restarts the gateway through `/api/gateway/restart`
- Opens the visible Windows update terminal through `update-dashboard-visible.ps1`
- Tails dashboard, gateway, update, and restart logs

## Build

Install the .NET 6 SDK or newer Windows Desktop SDK, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

The current runtime-only Windows install can run a published app, but it cannot
compile this project without the SDK.

## Runtime assumptions

- Default repository path is discovered by walking upward from the executable.
- Set `HERMES_REPO_DIR` to force a specific repo checkout.
- Default dashboard port is `9119`; it can be changed in the UI.
- Local secrets remain in Hermes' normal config/env files. The GUI reads paths
  and status only; it does not print secret values.
