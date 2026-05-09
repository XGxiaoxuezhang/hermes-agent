param(
    [int]$Port = 9119,
    [string]$TaskName = "HermesAgentDashboard"
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$startScript = Join-Path $repo "scripts\windows\start-dashboard-background.ps1"

if (-not (Test-Path $startScript)) {
    throw "Missing start script: $startScript"
}

$powershellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
$arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`" -Port $Port"
$action = New-ScheduledTaskAction -Execute $powershellPath -Argument $arguments -WorkingDirectory $repo
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Start Hermes Agent Dashboard for the current Windows user." `
    -Force | Out-Null

Write-Host "Hermes Dashboard startup task installed: $TaskName"
Write-Host "It will start after the current user logs in."
Write-Host "To start it now, run: hermes-dashboard -Port $Port"
