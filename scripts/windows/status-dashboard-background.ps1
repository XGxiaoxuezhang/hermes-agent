param(
    [int]$Port = 9119
)

$ErrorActionPreference = "Stop"

$stateDir = Join-Path $env:LOCALAPPDATA "HermesAgent"
$pidFile = Join-Path $stateDir "dashboard.pid"
$logFile = Join-Path $stateDir "dashboard.log"
$errorLogFile = Join-Path $stateDir "dashboard-error.log"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")

function Get-ProcessDescription {
    param([int]$ProcessId)
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
    if (-not $proc) {
        return @{ LooksLikeHermes = $false; CommandLine = ""; ExecutablePath = "" }
    }
    $cmd = [string]$proc.CommandLine
    $exe = [string]$proc.ExecutablePath
    $repoPrefix = $repo.Path.ToLowerInvariant()
    $haystack = "$exe $cmd".ToLowerInvariant()
    return @{
        LooksLikeHermes = ($haystack.Contains("hermes_cli.main") -or $haystack.Contains($repoPrefix))
        CommandLine = $cmd
        ExecutablePath = $exe
    }
}

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
    $desc = Get-ProcessDescription ([int]$connection.OwningProcess)
    if (-not $desc.LooksLikeHermes) {
        Write-Host "Hermes Dashboard: port occupied by another process"
        Write-Host "PID: $($connection.OwningProcess)"
        Write-Host "Expected URL: http://127.0.0.1:$Port"
        Write-Host "PID file: $pidText"
        exit 2
    }
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
