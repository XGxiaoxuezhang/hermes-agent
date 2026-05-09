param(
    [int]$Port = 9119
)

$ErrorActionPreference = "Stop"

$stateDir = Join-Path $env:LOCALAPPDATA "HermesAgent"
$pidFile = Join-Path $stateDir "dashboard.pid"

$pids = @()
if (Test-Path $pidFile) {
    $raw = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($raw -match "^\d+$") {
        $pids += [int]$raw
    }
}

try {
    $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    foreach ($conn in $connections) {
        if ($conn.OwningProcess) {
            $pids += [int]$conn.OwningProcess
        }
    }
} catch {
}

$pids = $pids | Sort-Object -Unique
if (-not $pids) {
    Write-Host "Hermes Dashboard is not running on port $Port."
    if (Test-Path $pidFile) {
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

foreach ($pidValue in $pids) {
    Write-Host "Stopping Hermes Dashboard process $pidValue"
    Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
}

if (Test-Path $pidFile) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

Write-Host "Hermes Dashboard stopped."
