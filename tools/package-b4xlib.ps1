<#
.SYNOPSIS
    Builds the Pakai Asadi library and packages it as release/PakaiAsadi.b4xlib.

.DESCRIPTION
    Runs B4JBuilder with -Task=BuildLibrary (which excludes the main module and
    compiles AsadiHandler, AsadiState, and PakaiAsadi as a library), then zips the
    library sources together with source/manifest.txt.

    B4JBuilder 10.70 reports success but does not write the archive itself, so the
    .b4xlib is assembled here. A B4J .b4xlib is a plain zip with the .bas files and
    manifest.txt at its root.

.PARAMETER OutputPath
    Archive to create. Defaults to <repo>\release\PakaiAsadi.b4xlib.

.PARAMETER BuilderPath
    B4JBuilder.exe location.

.PARAMETER SkipBuild
    Package the current sources without running the library compiler.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\package-b4xlib.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputPath = '',
    [string]$BuilderPath = 'C:\Program Files\B4X\B4J\B4JBuilder.exe',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repoRoot = (Resolve-Path -LiteralPath (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..')).Path
$sourceDir = Join-Path $repoRoot 'source'
$projectPath = Join-Path $sourceDir 'Pakai-Asadi.b4j'
$manifestPath = Join-Path $sourceDir 'manifest.txt'
if ($OutputPath -eq '') { $OutputPath = Join-Path $repoRoot 'release\PakaiAsadi.b4xlib' }
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

# Only these modules ship. main and DemoHomeHandler are demo-host code.
$modules = @('AsadiHandler.bas', 'AsadiState.bas', 'PakaiAsadi.bas')

foreach ($module in $modules) {
    $sourceFile = Join-Path $sourceDir $module
    if (-not (Test-Path -LiteralPath $sourceFile)) { throw "Missing library source: $sourceFile" }
}

if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Missing library manifest: $manifestPath" }

# Keep the project attributes and the archive manifest on the same version.
$projectText = Get-Content -LiteralPath $projectPath -Raw
$manifestText = Get-Content -LiteralPath $manifestPath -Raw
$projectVersion = [regex]::Match($projectText, '(?m)^#LibraryVersion:\s*(\S+)\s*$').Groups[1].Value
$manifestVersion = [regex]::Match($manifestText, '(?m)^Version=(\S+)\s*$').Groups[1].Value
$projectName = [regex]::Match($projectText, '(?m)^#LibraryName:\s*(\S+)\s*$').Groups[1].Value
if ($projectName -ne 'PakaiAsadi') { throw "Pakai-Asadi.b4j must declare #LibraryName: PakaiAsadi (found '$projectName')." }
if ($projectVersion -eq '' -or $projectVersion -ne $manifestVersion) {
    throw "Version mismatch: project declares '$projectVersion', manifest declares '$manifestVersion'."
}

if ($SkipBuild -eq $false) {
    if (-not (Test-Path -LiteralPath $BuilderPath)) { throw "B4JBuilder not found: $BuilderPath" }
    # A previous application build leaves a generated main.java that a library build
    # cannot reuse (it imports the debug runtime). Drop only the generated source and
    # class folders; keep the application jar and any runtime files under Objects.
    foreach ($generated in 'src', 'bin') {
        $generatedPath = Join-Path (Join-Path $sourceDir 'Objects') $generated
        if (Test-Path -LiteralPath $generatedPath) { Remove-Item -LiteralPath $generatedPath -Recurse -Force }
    }
    Write-Host "Building library from $sourceDir"
    & $BuilderPath '-Task=BuildLibrary' "-BaseFolder=$sourceDir" '-NoClean=True' '-ShowWarnings=True'
    if ($LASTEXITCODE -ne 0) { throw "BuildLibrary failed with exit code $LASTEXITCODE." }
}

$staging = Join-Path ([System.IO.Path]::GetTempPath()) ('pakai-asadi-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging | Out-Null
try {
    foreach ($module in $modules) {
        Copy-Item -LiteralPath (Join-Path $sourceDir $module) -Destination (Join-Path $staging $module)
    }
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $staging 'manifest.txt')

    $outputDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }
    if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }

    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $staging,
        $OutputPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false)
}
finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}

$archive = [System.IO.Compression.ZipFile]::OpenRead($OutputPath)
try {
    Write-Host "Created $OutputPath"
    foreach ($entry in $archive.Entries) {
        Write-Host ("  {0} ({1} bytes)" -f $entry.FullName, $entry.Length)
    }
}
finally {
    $archive.Dispose()
}
