param(
    [int]$Port = 9119
)

$ErrorActionPreference = "Stop"

$stateDir = Join-Path $env:LOCALAPPDATA "HermesAgent"
$pidFile = Join-Path $stateDir "dashboard.pid"
$logFile = Join-Path $stateDir "dashboard.log"
$errorLogFile = Join-Path $stateDir "dashboard-error.log"

$pidText = ""
if (Test-Path $pidFile) {
    $pidText = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
}

try {
    $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
} catch {
    $connection = $null
}

if ($connection -and $connection.OwningProcess) {
    Write-Host "Hermes Dashboard: running"
    Write-Host "PID: $($connection.OwningProcess)"
    Write-Host "URL: http://127.0.0.1:$Port"
    Write-Host "PID file: $pidText"
    Write-Host "Log: $logFile"
    Write-Host "Error log: $errorLogFile"
} else {
    Write-Host "Hermes Dashboard: stopped"
    Write-Host "Expected URL: http://127.0.0.1:$Port"
    if ($pidText) {
        Write-Host "Stale PID file: $pidText"
    }
}
