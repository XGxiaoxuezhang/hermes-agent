param(
    [int]$Port = 9119
)

$ErrorActionPreference = "Stop"

$stateDir = Join-Path $env:LOCALAPPDATA "HermesAgent"
$pidFile = Join-Path $stateDir "dashboard.pid"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")

function Test-IsHermesProcess {
    param([int]$ProcessId)
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
    if (-not $proc) {
        return $false
    }
    $cmd = [string]$proc.CommandLine
    $exe = [string]$proc.ExecutablePath
    $repoPrefix = $repo.Path.ToLowerInvariant()
    $haystack = "$exe $cmd".ToLowerInvariant()
    return ($haystack.Contains("hermes_cli.main") -or $haystack.Contains($repoPrefix))
}

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
    if (-not (Test-IsHermesProcess $pidValue)) {
        Write-Host "Skipping PID $pidValue because it does not look like this Hermes install."
        continue
    }
    Write-Host "Stopping Hermes Dashboard process $pidValue"
    Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
}

if (Test-Path $pidFile) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

Write-Host "Hermes Dashboard stopped."
