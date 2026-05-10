param(
    [string]$RepoUrl = "https://github.com/XGxiaoxuezhang/hermes-agent.git",
    [string]$Branch = "windows-dashboard-i18n",
    [string]$InstallDir = "$env:LOCALAPPDATA\HermesAgent\hermes-agent",
    [int]$Port = 9119,
    [string]$LogFile = ""
)

$ErrorActionPreference = "Stop"
$exitCode = 0
$transcriptStarted = $false

function Write-Section {
    param([string]$Message)
    Write-Host ""
    Write-Host "== $Message ==" -ForegroundColor Cyan
}

try {
    if ($LogFile) {
        $logDir = Split-Path -Parent $LogFile
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir | Out-Null
        }
        Start-Transcript -Path $LogFile -Append | Out-Null
        $transcriptStarted = $true
    }

    Write-Host ""
    Write-Host "Hermes Dashboard update" -ForegroundColor Green
    Write-Host "Repo:       $RepoUrl"
    Write-Host "Branch:     $Branch"
    Write-Host "InstallDir: $InstallDir"
    Write-Host "Port:       $Port"
    if ($LogFile) {
        Write-Host "Log:        $LogFile"
    }

    $installer = Join-Path $InstallDir "scripts\windows\install-from-github.ps1"
    if (-not (Test-Path $installer)) {
        $installer = Join-Path $PSScriptRoot "install-from-github.ps1"
    }
    if (-not (Test-Path $installer)) {
        throw "Missing installer: $installer"
    }

    Write-Section "Updating and restarting dashboard"
    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $installer `
        -RepoUrl $RepoUrl `
        -Branch $Branch `
        -InstallDir $InstallDir `
        -Port $Port `
        -NoOpen `
        -Background

    if ($LASTEXITCODE -ne 0) {
        throw "Installer failed with exit code $LASTEXITCODE"
    }

    Write-Section "Done"
    Write-Host "Hermes Dashboard has been updated and started in the background." -ForegroundColor Green
    Write-Host "Open: http://127.0.0.1:$Port"
} catch {
    $exitCode = 1
    Write-Host ""
    Write-Host "Update failed:" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
} finally {
    if ($transcriptStarted) {
        try {
            Stop-Transcript | Out-Null
        } catch {
        }
    }
    Write-Host ""
    if ($exitCode -eq 0) {
        Write-Host "Update finished. Press any key to close this window"
    } else {
        Write-Host "Update failed. Press any key to close this window"
    }
    try {
        [void][System.Console]::ReadKey($true)
    } catch {
        Read-Host "Press Enter to close this window"
    }
}

exit $exitCode
