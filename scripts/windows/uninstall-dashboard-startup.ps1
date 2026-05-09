param(
    [string]$TaskName = "HermesAgentDashboard"
)

$ErrorActionPreference = "Stop"

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Host "Hermes Dashboard startup task is not installed: $TaskName"
    exit 0
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
Write-Host "Hermes Dashboard startup task removed: $TaskName"
