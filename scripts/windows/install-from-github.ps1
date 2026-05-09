param(
    [string]$RepoUrl = "https://github.com/XGxiaoxuezhang/hermes-agent.git",
    [string]$Branch = "windows-dashboard-i18n",
    [string]$InstallDir = "$env:LOCALAPPDATA\HermesAgent\hermes-agent",
    [int]$Port = 9119,
    [switch]$NoStart,
    [switch]$NoOpen,
    [switch]$SkipWebBuild,
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

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
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
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "$Name user-scope install failed or is not supported. Trying default installer scope; this may show an administrator/UAC prompt."
        & winget install --id $WingetId --exact --accept-package-agreements --accept-source-agreements
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

function Test-CompatiblePython {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        & py -3.13 -c "import sys" 2>$null
        if ($LASTEXITCODE -eq 0) { return $true }
        & py -3.11 -c "import sys" 2>$null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $version = (& python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null).Trim()
        if ($version -and [version]$version -ge [version]"3.11" -and [version]$version -le [version]"3.13") {
            return $true
        }
    }
    return $false
}

Write-Host ""
Write-Host "Hermes Agent fork installer" -ForegroundColor Green
Write-Host "Repo:       $RepoUrl"
Write-Host "Branch:     $Branch"
Write-Host "InstallDir: $InstallDir"
Write-Host ""

Ensure-Command "git" "Git.Git" "https://git-scm.com/download/win"
Ensure-Command "node" "OpenJS.NodeJS.LTS" "https://nodejs.org/"

if (-not (Test-CompatiblePython)) {
    Install-WithWinget "Python 3.13" "Python.Python.3.13" "https://www.python.org/downloads/"
}

$parent = Split-Path -Parent $InstallDir
if (-not (Test-Path $parent)) {
    New-Item -ItemType Directory -Path $parent | Out-Null
}

if (Test-Path (Join-Path $InstallDir ".git")) {
    Write-Step "Updating existing checkout"
    Push-Location $InstallDir
    try {
        Invoke-Checked "git" "remote" "set-url" "origin" $RepoUrl
        Invoke-Checked "git" "fetch" "origin" $Branch
        Invoke-Checked "git" "checkout" $Branch
        Invoke-Checked "git" "pull" "--ff-only" "origin" $Branch
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
if ($NoStart) {
    $installerArgs += "-NoStart"
}
if ($NoOpen) {
    $installerArgs += "-NoOpen"
}
if ($SkipWebBuild) {
    $installerArgs += "-SkipWebBuild"
}

Invoke-Checked "powershell" @installerArgs
