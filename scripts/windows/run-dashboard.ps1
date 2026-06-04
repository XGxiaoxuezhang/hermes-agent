param(
    [int]$Port = 9119,
    [switch]$Open,
    [switch]$NoTui
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$python = Join-Path $repo "venv\Scripts\python.exe"

function Resolve-HermesHome {
    if ($env:HERMES_HOME) {
        return $env:HERMES_HOME
    }
    $legacy = Join-Path $env:USERPROFILE ".hermes"
    foreach ($marker in @("state.db", "config.yaml", ".env", "auth.json")) {
        if (Test-Path (Join-Path $legacy $marker)) {
            return $legacy
        }
    }
    return (Join-Path $env:LOCALAPPDATA "hermes")
}

$env:HERMES_HOME = Resolve-HermesHome

if (-not (Test-Path $python)) {
    throw "Missing virtual environment: $python. Run scripts\windows\install-local.ps1 first."
}

$env:HERMES_DASHBOARD_TUI = if ($NoTui) { "0" } else { "1" }

$argsList = @("-m", "hermes_cli.main", "dashboard", "--port", "$Port")
if (-not $Open) {
    $argsList += "--no-open"
}
if (-not $NoTui) {
    $argsList += "--tui"
}

Push-Location $repo
try {
    & $python @argsList
} finally {
    Pop-Location
}
