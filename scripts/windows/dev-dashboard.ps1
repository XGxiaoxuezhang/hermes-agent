param(
    [int]$Port = 9119,
    [int]$VitePort = 5173,
    [switch]$NoInstall,
    [switch]$NoOpen,
    [switch]$Tui
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$webDir = Join-Path $repo "web"
$python = Join-Path $repo "venv\Scripts\python.exe"

if (-not (Test-Path $python)) {
    $python = "python"
}

if (-not $NoInstall) {
    Push-Location $repo
    try {
        & $python -m pip install -e ".[web,pty]"
    } finally {
        Pop-Location
    }

    Push-Location $webDir
    try {
        npm install
    } finally {
        Pop-Location
    }
}

$env:HERMES_DASHBOARD_TUI = if ($Tui) { "1" } else { $env:HERMES_DASHBOARD_TUI }

$backendArgs = @("-m", "hermes_cli.main", "dashboard", "--port", "$Port", "--no-open")
if ($Tui) {
    $backendArgs += "--tui"
}

Start-Process -WindowStyle Hidden -FilePath $python -ArgumentList $backendArgs -WorkingDirectory $repo

Push-Location $webDir
try {
    $env:HERMES_DASHBOARD_URL = "http://127.0.0.1:$Port"
    $viteArgs = @("run", "dev", "--", "--host", "127.0.0.1", "--port", "$VitePort", "--force")
    if ($NoOpen) {
        & npm @viteArgs
    } else {
        Start-Process "http://127.0.0.1:$VitePort"
        & npm @viteArgs
    }
} finally {
    Pop-Location
}
