param(
    [int]$Port = 9119,
    [switch]$Open,
    [switch]$NoTui
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$python = Join-Path $repo "venv\Scripts\python.exe"
$stateDir = Join-Path $env:LOCALAPPDATA "HermesAgent"
$pidFile = Join-Path $stateDir "dashboard.pid"
$logFile = Join-Path $stateDir "dashboard.log"
$errorLogFile = Join-Path $stateDir "dashboard-error.log"

if (-not (Test-Path $python)) {
    throw "Missing virtual environment: $python. Run scripts\windows\install-local.ps1 first."
}

if (-not (Test-Path $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir | Out-Null
}

try {
    $existing = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
} catch {
    $existing = $null
}
if ($existing -and $existing.OwningProcess) {
    Write-Host "Hermes Dashboard already appears to be listening on port $Port (PID $($existing.OwningProcess))."
    Write-Host "Open http://127.0.0.1:$Port"
    exit 0
}

$env:HERMES_DASHBOARD_TUI = if ($NoTui) { "0" } else { "1" }

$argsList = @("-m", "hermes_cli.main", "dashboard", "--port", "$Port", "--no-open")
if (-not $NoTui) {
    $argsList += "--tui"
}

$process = Start-Process `
    -FilePath $python `
    -ArgumentList $argsList `
    -WorkingDirectory $repo `
    -WindowStyle Hidden `
    -RedirectStandardOutput $logFile `
    -RedirectStandardError $errorLogFile `
    -PassThru

Set-Content -Path $pidFile -Value $process.Id -Encoding ASCII
Start-Sleep -Seconds 2

try {
    $status = (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$Port").StatusCode
} catch {
    $status = "starting"
}

Write-Host "Hermes Dashboard started in background. PID: $($process.Id), status: $status"
Write-Host "URL: http://127.0.0.1:$Port"
Write-Host "Log: $logFile"
Write-Host "Error log: $errorLogFile"

if ($Open) {
    Start-Process "http://127.0.0.1:$Port"
}
