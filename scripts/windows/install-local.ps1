param(
    [int]$Port = 9119,
    [switch]$NoStart,
    [switch]$NoOpen,
    [switch]$SkipWebBuild,
    [switch]$RecreateVenv,
    [string]$PythonCommand = ""
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "=> $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host "!! $Message" -ForegroundColor Yellow
}

function Require-Command {
    param(
        [string]$Name,
        [string]$InstallHint
    )
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name not found. $InstallHint"
    }
}

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

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

function Install-WithWinget {
    param(
        [string]$Name,
        [string]$WingetId,
        [string]$ManualUrl
    )

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "$Name not found, and winget is unavailable. Install manually: $ManualUrl"
    }

    Write-Step "Installing $Name with winget (user scope first)"
    & winget install --id $WingetId --exact --scope user --accept-package-agreements --accept-source-agreements
    Refresh-Path
    if (Get-Command $Name -ErrorAction SilentlyContinue) {
        return
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "$Name user-scope install failed or is not supported. Trying default installer scope; this may show an administrator/UAC prompt."
        & winget install --id $WingetId --exact --accept-package-agreements --accept-source-agreements
        Refresh-Path
        if (Get-Command $Name -ErrorAction SilentlyContinue) {
            return
        }
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install $Name with winget. If an administrator/UAC prompt appeared and was cancelled, accept it or install manually: $ManualUrl"
    }
    Refresh-Path
}

function Ensure-Command {
    param(
        [string]$Name,
        [string]$WingetId,
        [string]$ManualUrl
    )
    if (Get-Command $Name -ErrorAction SilentlyContinue) {
        return
    }
    Install-WithWinget $Name $WingetId $ManualUrl
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name was installed but is not visible on PATH yet. Restart PowerShell and re-run this installer."
    }
}

function Test-CommandExitZero {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $FilePath
        foreach ($arg in $Arguments) {
            $psi.ArgumentList.Add($arg)
        }
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $process = [System.Diagnostics.Process]::Start($psi)
        $process.WaitForExit()
        return $process.ExitCode -eq 0
    } catch {
        return $false
    }
}

function Test-CompatiblePython {
    return [bool](Get-CompatiblePythonCommand)
}

function Test-PythonCommand {
    param([string]$Command)
    if (-not $Command) {
        return $false
    }
    try {
        $version = Get-PythonCommandVersion $Command
        return $version -and [version]$version -ge [version]"3.11" -and [version]$version -le [version]"3.13"
    } catch {
        return $false
    }
}

function Get-PythonCommandVersion {
    param([string]$Command)
    $parts = Split-PythonCommand $Command
    $script = "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
    $output = & $parts.File @($parts.Args + @("-c", $script)) 2>$null
    if ($LASTEXITCODE -ne 0) {
        return ""
    }
    return ([string]$output).Trim()
}

function Split-PythonCommand {
    param([string]$Command)
    $trimmed = $Command.Trim()
    if ($trimmed.StartsWith('"')) {
        $end = $trimmed.IndexOf('"', 1)
        if ($end -gt 0) {
            $file = $trimmed.Substring(1, $end - 1)
            $rest = $trimmed.Substring($end + 1).Trim()
            return @{ File = $file; Args = @($rest -split " " | Where-Object { $_ }) }
        }
    }
    $parts = $trimmed -split " "
    return @{ File = $parts[0]; Args = @($parts | Select-Object -Skip 1) }
}

function Get-CompatiblePythonCommand {
    if ($PythonCommand -and (Test-PythonCommand $PythonCommand)) {
        return $PythonCommand
    }
    $candidates = @()
    if (Get-Command py -ErrorAction SilentlyContinue) {
        if (Test-CommandExitZero "py" @("-3.13", "-c", "import sys")) { return "py -3.13" }
        if (Test-CommandExitZero "py" @("-3.11", "-c", "import sys")) { return "py -3.11" }
    }
    if (Get-Command python3.13 -ErrorAction SilentlyContinue) {
        if (Test-CommandExitZero "python3.13" @("-c", "import sys")) { return "python3.13" }
    }
    if (Get-Command python3.11 -ErrorAction SilentlyContinue) {
        if (Test-CommandExitZero "python3.11" @("-c", "import sys")) { return "python3.11" }
    }
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        $candidates += $pythonCmd.Source
    }
    $candidates += @(
        "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "$env:ProgramFiles\Python313\python.exe",
        "$env:ProgramFiles\Python311\python.exe",
        "${env:ProgramFiles(x86)}\Python313\python.exe",
        "${env:ProgramFiles(x86)}\Python311\python.exe"
    )
    foreach ($searchRoot in @("$env:LOCALAPPDATA\Programs\Python", "$env:ProgramFiles", "${env:ProgramFiles(x86)}")) {
        if (Test-Path $searchRoot) {
            $candidates += Get-ChildItem -Path $searchRoot -Filter python.exe -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match "Python(311|313)" } |
                ForEach-Object { $_.FullName }
        }
    }
    foreach ($candidate in $candidates) {
        if (-not $candidate -or -not (Test-Path $candidate)) {
            continue
        }
        try {
            $version = (& $candidate -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null).Trim()
            if ($version -and [version]$version -ge [version]"3.11" -and [version]$version -le [version]"3.13") {
                return $candidate
            }
        } catch {
        }
    }
    return ""
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$Arguments
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $FilePath $($Arguments -join ' ')"
    }
}

function Get-PythonVersionText {
    param([string]$PythonPath)
    if (-not (Test-Path $PythonPath)) {
        return ""
    }
    try {
        return (& $PythonPath -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')").Trim()
    } catch {
        return ""
    }
}

function New-HermesVenv {
    param([string]$VenvPath)

    $command = Get-CompatiblePythonCommand
    if (-not $command) {
        throw "Python 3.11/3.13 is required but Hermes cannot find it. Disable Windows Store python aliases or reinstall Python 3.13, then retry."
    }
    $parts = Split-PythonCommand $command
    Invoke-Checked -FilePath $parts.File -Arguments ($parts.Args + @("-m", "venv", $VenvPath))
}

function Stop-DashboardPort {
    param(
        [int]$ListenPort,
        [string]$RepoPath = ""
    )
    $repoPrefix = ""
    if ($RepoPath) {
        $resolvedRepo = Resolve-Path $RepoPath -ErrorAction SilentlyContinue
        if ($resolvedRepo) {
            $repoPrefix = $resolvedRepo.Path.ToLowerInvariant()
        }
    }
    try {
        $connections = Get-NetTCPConnection -LocalPort $ListenPort -State Listen -ErrorAction SilentlyContinue
    } catch {
        $connections = @()
    }
    foreach ($conn in $connections) {
        if ($conn.OwningProcess) {
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $($conn.OwningProcess)" -ErrorAction SilentlyContinue
            $cmd = [string]$proc.CommandLine
            $exe = [string]$proc.ExecutablePath
            $haystack = "$exe $cmd".ToLowerInvariant()
            $looksLikeHermes = $haystack.Contains("hermes_cli.main") -or ($repoPrefix -and $haystack.Contains($repoPrefix))
            if (-not $looksLikeHermes) {
                Write-Warn "Port $ListenPort is used by process $($conn.OwningProcess), but it does not look like this Hermes install. Leaving it running."
                continue
            }
            Write-Step "Stopping process $($conn.OwningProcess) on port $ListenPort"
            Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
        }
    }
}

function Stop-VenvPython {
    param([string]$VenvPath)
    $venvRoot = (Resolve-Path $VenvPath -ErrorAction SilentlyContinue)
    if (-not $venvRoot) {
        return
    }
    $prefix = $venvRoot.Path.ToLowerInvariant()
    $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "python*.exe" }
    foreach ($proc in $processes) {
        $exe = [string]$proc.ExecutablePath
        $cmd = [string]$proc.CommandLine
        $haystack = "$exe $cmd".ToLowerInvariant()
        if ($haystack.Contains($prefix)) {
            Write-Step "Stopping venv Python process $($proc.ProcessId)"
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
}

function Remove-DirectoryWithRetry {
    param([string]$Path)
    for ($i = 1; $i -le 8; $i++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($i -eq 8) {
                throw
            }
            Start-Sleep -Milliseconds (300 * $i)
        }
    }
}

function Add-UserPathEntry {
    param([string]$PathEntry)
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($current) {
        $parts = $current -split ";" | Where-Object { $_ }
    }
    $normalized = $PathEntry.TrimEnd("\")
    $parts = @($parts | Where-Object { $_.TrimEnd("\") -ine $normalized })
    $newPath = (@($PathEntry) + $parts) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")

    $processParts = @()
    if ($env:Path) {
        $processParts = $env:Path -split ";" | Where-Object { $_ }
    }
    $processParts = @($processParts | Where-Object { $_.TrimEnd("\") -ine $normalized })
    $env:Path = (@($PathEntry) + $processParts) -join ";"
}

function Install-CommandShims {
    param(
        [string]$RepoPath,
        [string]$PythonPath,
        [string]$HermesHome
    )

    $binDir = Join-Path $env:LOCALAPPDATA "HermesAgent\bin"
    if (-not (Test-Path $binDir)) {
        New-Item -ItemType Directory -Path $binDir | Out-Null
    }

    $hermesCmd = Join-Path $binDir "hermes.cmd"
    $dashboardCmd = Join-Path $binDir "hermes-dashboard.cmd"

$hermesContent = @"
@echo off
set "HERMES_REPO=$RepoPath"
set "HERMES_HOME=$HermesHome"
"$PythonPath" -m hermes_cli.main %*
"@
    Set-Content -Path $hermesCmd -Value $hermesContent -Encoding ASCII

$dashboardContent = @"
@echo off
set "HERMES_REPO=$RepoPath"
set "HERMES_HOME=$HermesHome"
powershell -ExecutionPolicy Bypass -File "$RepoPath\scripts\windows\start-dashboard-background.ps1" %*
"@
    Set-Content -Path $dashboardCmd -Value $dashboardContent -Encoding ASCII

    Add-UserPathEntry $binDir
    Write-Step "Installed command shims: hermes, hermes-dashboard"
    Write-Host "   Current PowerShell can use them now; already-open terminals may need restart."
}

$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$venv = Join-Path $repo "venv"
$python = Join-Path $venv "Scripts\python.exe"
$webDir = Join-Path $repo "web"
$env:HERMES_HOME = Resolve-HermesHome

Write-Host ""
Write-Host "Hermes Agent local Windows install" -ForegroundColor Green
Write-Host "Repo: $repo"
Write-Host "HermesHome: $env:HERMES_HOME"
Write-Host ""

Ensure-Command "git" "Git.Git" "https://git-scm.com/download/win"
Ensure-Command "node" "OpenJS.NodeJS.LTS" "https://nodejs.org/"

if (-not (Test-CompatiblePython)) {
    Install-WithWinget "Python 3.13" "Python.Python.3.13" "https://www.python.org/downloads/"
}

$resolvedPythonCommand = Get-CompatiblePythonCommand
if (-not $resolvedPythonCommand) {
    throw "Python 3.11/3.13 is required but Hermes cannot find it. Disable Windows Store python aliases or reinstall Python 3.13, then retry."
}
Write-Step "Python is ready: $resolvedPythonCommand"

if ($RecreateVenv -and (Test-Path $venv)) {
    Stop-DashboardPort $Port $repo
    Stop-VenvPython $venv
    Write-Step "Removing existing virtual environment"
    Remove-DirectoryWithRetry $venv
}

if ((Test-Path $python) -and -not $RecreateVenv) {
    $version = Get-PythonVersionText $python
    if ($version -and ([version]$version -lt [version]"3.11" -or [version]$version -gt [version]"3.13")) {
        Write-Step "Existing venv uses Python $version; recreating with Python 3.11/3.13 to avoid source builds"
        Stop-DashboardPort $Port $repo
        Stop-VenvPython $venv
        Remove-DirectoryWithRetry $venv
    }
}

if (-not (Test-Path $python)) {
    Write-Step "Creating Python virtual environment"
    New-HermesVenv $venv
}

if (-not (Test-Path $python)) {
    throw "Failed to create virtual environment at $venv"
}

Stop-DashboardPort $Port $repo

Write-Step "Upgrading pip"
Invoke-Checked -FilePath $python -Arguments @("-m", "pip", "install", "--upgrade", "pip")

Write-Step "Installing Hermes in editable mode with Web UI and PTY support"
Push-Location $repo
try {
    Invoke-Checked -FilePath $python -Arguments @("-m", "pip", "install", "--only-binary=:all:", "-e", ".[web,pty]")
} finally {
    Pop-Location
}

if (-not $SkipWebBuild) {
    Write-Step "Installing dashboard npm dependencies"
    Push-Location $webDir
    try {
        Invoke-Checked -FilePath "npm" -Arguments @("install")
        Write-Step "Building dashboard assets for port $Port production mode"
        Invoke-Checked -FilePath "npm" -Arguments @("run", "build")
    } finally {
        Pop-Location
    }
}

Write-Step "Checking Hermes CLI"
Invoke-Checked -FilePath $python -Arguments @("-m", "hermes_cli.main", "--help") | Select-Object -First 1 | Out-Null
Install-CommandShims (Resolve-Path $repo).Path (Resolve-Path $python).Path $env:HERMES_HOME

Write-Host ""
Write-Host "Install complete." -ForegroundColor Green
Write-Host "Start command:"
Write-Host "  powershell -ExecutionPolicy Bypass -File .\scripts\windows\run-dashboard.ps1 -Port $Port" -ForegroundColor Yellow
Write-Host "Background command:"
Write-Host "  hermes-dashboard -Port $Port" -ForegroundColor Yellow
Write-Host "CLI command:"
Write-Host "  hermes" -ForegroundColor Yellow
Write-Host ""

if (-not $NoStart) {
    Write-Step "Starting dashboard"
    $runScript = Join-Path $repo "scripts\windows\run-dashboard.ps1"
    if (-not $NoOpen) {
        Start-Process "http://127.0.0.1:$Port"
    }
    & powershell -ExecutionPolicy Bypass -File $runScript -Port $Port
}
