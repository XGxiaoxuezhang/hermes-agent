param(
    [ValidateSet("Release", "Debug")]
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64"
)

$ErrorActionPreference = "Stop"
$project = Join-Path $PSScriptRoot "HermesAgent.Gui.csproj"
$out = Join-Path $PSScriptRoot "publish\$Runtime"

dotnet publish $project `
    -c $Configuration `
    -r $Runtime `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -o $out

if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "Published:"
Write-Host (Join-Path $out "HermesAgent.Gui.exe")
