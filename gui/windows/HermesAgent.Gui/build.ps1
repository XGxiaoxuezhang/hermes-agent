param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$project = Join-Path $PSScriptRoot "HermesAgent.Gui.csproj"

$info = dotnet --info
if ($info -match "No SDKs were found") {
    throw ".NET SDK is not installed. Install the .NET 6 SDK or newer Windows Desktop SDK, then rerun this script."
}

dotnet build $project -c $Configuration
