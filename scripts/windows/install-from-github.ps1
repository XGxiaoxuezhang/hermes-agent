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

function Require-Command {
    param(
        [string]$Name,
        [string]$InstallHint
    )
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name not found. $InstallHint"
    }
}

Write-Host ""
Write-Host "Hermes Agent fork installer" -ForegroundColor Green
Write-Host "Repo:       $RepoUrl"
Write-Host "Branch:     $Branch"
Write-Host "InstallDir: $InstallDir"
Write-Host ""

Require-Command "git" "Install Git for Windows first: https://git-scm.com/download/win"
Require-Command "node" "Install Node.js 22+ first: https://nodejs.org/"

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
