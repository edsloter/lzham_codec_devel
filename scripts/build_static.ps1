param(
    [string]$BuildDir = "build_x64_static",
    [string]$Config = "Release",
    [string]$Arch = "x64",
    [string]$ArtifactsDir = "artifacts",
    [switch]$NoCleanup = $false,
    [switch]$NoCleanupLog = $false,
    [switch]$NoCleanupTests = $false,
    [switch]$NoRunTests = $false,
    [switch]$CleanBuildDirs = $false,
    [switch]$CleanBuildDirsAll = $false,
    [switch]$DryRun = $false
)

# Ensure script works from repo root regardless of invocation location
$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location (Join-Path $scriptFolder "..")

if (-not $NoCleanup) {
    Write-Host "Cleaning repo .exe/.dll files (except *_original.*)"
    & "$PSScriptRoot\cleanup_artifacts.ps1"
} else {
    Write-Host "Skipping cleanup (NoCleanup specified)"
}

# By default truncate tests folder unless caller asked to skip tests cleanup
if (-not $NoCleanupTests) {
    Write-Host "Truncating tests folder before build (preserving *_original.*)"
    & "$PSScriptRoot\cleanup_tests.ps1"
} else {
    Write-Host "Skipping tests truncation (NoCleanupTests specified)"
}

if (-not $NoCleanupLog) {
    Write-Host "Cleaning log files (.log/.tmp/.bak)"
    & "$PSScriptRoot\cleanup_logs.ps1"
} else {
    Write-Host "Skipping log cleanup (NoCleanupLog specified)"
}

if ($CleanBuildDirs -or $CleanBuildDirsAll) {
    $params = @{}
    if ($DryRun) { $params['DryRun'] = $true }
    if ($CleanBuildDirsAll) {
        $params['All'] = $true
    } else {
        $params['BuildDirs'] = @($BuildDir)
    }
    & "$PSScriptRoot\CleanBuildDirs.ps1" @params
}

Write-Host "Configuring static build in: $BuildDir (Arch=$Arch, Config=$Config)"
cmake -S . -B $BuildDir -A $Arch -DBUILD_SHARED_LIBS=OFF
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }

Write-Host "Building lzhamtest (static)..."
cmake --build $BuildDir --config $Config --target lzhamtest
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

# Locate built exe
$exePath = Join-Path $BuildDir "lzhamtest\$Config\lzhamtest.exe"
if (!(Test-Path $exePath)) { throw "Executable not found: $exePath" }

# Create artifacts folders
$staticDir = Join-Path $ArtifactsDir "static"
New-Item -ItemType Directory -Path $staticDir -Force | Out-Null

# Move the built exe into artifacts\static (remove any existing file first)
$destExe = Join-Path $staticDir "lzhamtest.exe"
if (Test-Path $destExe) { Remove-Item -Path $destExe -Force }
Move-Item -Path $exePath -Destination $destExe -Force
Write-Host "Static EXE moved to: $destExe"

Write-Host "Static build artifacts moved to: $staticDir"

# Create and verify test archives (hello_world.txt -> .lzh), then decompress and compare.
if (-not $NoRunTests) {
    Write-Host "Creating and decompressing test archives using available artifacts"
    & "$PSScriptRoot\create_archives.ps1"
    & "$PSScriptRoot\decompress_archives.ps1"
} else {
    Write-Host "Skipping test archive creation/decompression (NoRunTests specified)"
}
