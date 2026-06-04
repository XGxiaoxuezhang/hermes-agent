param(
    [string]$RepoUrl = "https://github.com/XGxiaoxuezhang/hermes-agent.git",
    [string]$Branch = "windows-dashboard-i18n",
    [string]$InstallDir = "$env:LOCALAPPDATA\HermesAgent\hermes-agent",
    [int]$Port = 9119,
    [switch]$NoStart,
    [switch]$NoOpen,
    [switch]$SkipWebBuild,
    [switch]$Background,
    [switch]$Force
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

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $FilePath $($Arguments -join ' ')"
    }
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

function Stop-RepoPythonProcesses {
    param([string]$RepoPath)
    $resolved = Resolve-Path $RepoPath -ErrorAction SilentlyContinue
    if (-not $resolved) {
        return
    }
    $prefix = $resolved.Path.ToLowerInvariant()
    $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "python*.exe" -or $_.Name -eq "node.exe" -or $_.Name -eq "cmd.exe" }
    foreach ($proc in $processes) {
        $cmd = [string]$proc.CommandLine
        $exe = [string]$proc.ExecutablePath
        $haystack = "$exe $cmd".ToLowerInvariant()
        if ($haystack.Contains($prefix)) {
            Write-Step "Stopping repo process $($proc.ProcessId) ($($proc.Name))"
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
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
    if (Get-Command py -ErrorAction SilentlyContinue) {
        if (Test-CommandExitZero "py" @("-3.13", "-c", "import sys")) { return $true }
        if (Test-CommandExitZero "py" @("-3.11", "-c", "import sys")) { return $true }
    }
    if (Get-Command python3.13 -ErrorAction SilentlyContinue) {
        if (Test-CommandExitZero "python3.13" @("-c", "import sys")) { return $true }
    }
    if (Get-Command python3.11 -ErrorAction SilentlyContinue) {
        if (Test-CommandExitZero "python3.11" @("-c", "import sys")) { return $true }
    }
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $version = ""
        try {
            $version = (& python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null).Trim()
        } catch {
            $version = ""
        }
        if ($version -and [version]$version -ge [version]"3.11" -and [version]$version -le [version]"3.13") {
            return $true
        }
    }
    return $false
}

function Get-CompatiblePythonCommand {
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

Write-Host ""
Write-Host "Hermes Agent fork installer" -ForegroundColor Green
Write-Host "Repo:       $RepoUrl"
Write-Host "Branch:     $Branch"
Write-Host "InstallDir: $InstallDir"
$env:HERMES_HOME = Resolve-HermesHome
Write-Host "HermesHome: $env:HERMES_HOME"
Write-Host ""

Ensure-Command "git" "Git.Git" "https://git-scm.com/download/win"
Ensure-Command "node" "OpenJS.NodeJS.LTS" "https://nodejs.org/"

if (-not (Test-CompatiblePython)) {
    Write-Step "Python 3.11/3.13 not found; installing Python 3.13"
    Install-WithWinget "Python 3.13" "Python.Python.3.13" "https://www.python.org/downloads/"
}

$pythonCommand = Get-CompatiblePythonCommand
if (-not $pythonCommand) {
    throw "Python 3.11/3.13 is required but Hermes cannot find it. Disable Windows Store python aliases or reinstall Python 3.13, then retry."
}
Write-Step "Python is ready: $pythonCommand"

$parent = Split-Path -Parent $InstallDir
if (-not (Test-Path $parent)) {
    New-Item -ItemType Directory -Path $parent | Out-Null
}

if (Test-Path (Join-Path $InstallDir ".git")) {
    Write-Step "Updating existing checkout"
    Stop-DashboardPort $Port $InstallDir
    Stop-RepoPythonProcesses $InstallDir
    Push-Location $InstallDir
    try {
        Invoke-Checked "git" "remote" "set-url" "origin" $RepoUrl
        Invoke-Checked "git" "fetch" "origin" $Branch
        Invoke-Checked "git" "checkout" "-B" $Branch "origin/$Branch"
        Invoke-Checked "git" "reset" "--hard" "origin/$Branch"
    } finally {
        Pop-Location
    }
} elseif (Test-Path $InstallDir) {
    if (-not $Force) {
        throw "InstallDir already exists but is not a git checkout: $InstallDir. Re-run with -Force to replace it, or choose another -InstallDir."
    }
    Write-Step "Replacing existing non-git directory"
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Invoke-Checked "git" "clone" "--branch" $Branch "--single-branch" $RepoUrl $InstallDir
} else {
    Write-Step "Cloning repository"
    Invoke-Checked "git" "clone" "--branch" $Branch "--single-branch" $RepoUrl $InstallDir
}

$localInstaller = Join-Path $InstallDir "scripts\windows\install-local.ps1"
if (-not (Test-Path $localInstaller)) {
    throw "Missing local installer: $localInstaller"
}

Write-Step "Running local installer"
$installerArgs = @("-ExecutionPolicy", "Bypass", "-File", $localInstaller, "-Port", "$Port")
$installerArgs += "-PythonCommand"
$installerArgs += $pythonCommand
if ($NoStart) {
    $installerArgs += "-NoStart"
}
if ($Background) {
    $installerArgs += "-NoStart"
}
if ($NoOpen) {
    $installerArgs += "-NoOpen"
}
if ($SkipWebBuild) {
    $installerArgs += "-SkipWebBuild"
}

Invoke-Checked "powershell" @installerArgs

if ($Background -and -not $NoStart) {
    Write-Step "Starting dashboard in background"
    $backgroundScript = Join-Path $InstallDir "scripts\windows\start-dashboard-background.ps1"
    Invoke-Checked "powershell" "-ExecutionPolicy" "Bypass" "-File" $backgroundScript "-Port" "$Port"
}
