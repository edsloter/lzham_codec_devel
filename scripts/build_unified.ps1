
param(
    [string]$BuildDir = "build_x64_unified",
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

Write-Host "Configuring unified build in: $BuildDir (Arch=$Arch, Config=$Config)"
# Build static sub-libs but build the wrapper (lzhamdll) as a shared library so it becomes a
# single unified DLL. We use BUILD_SHARED_LIBS=OFF to make lzhamcomp/lzhamdecomp static and
# pass BUILD_LZHAMDLL_SHARED=ON so lzhamdll's CMake will create a SHARED target.
cmake -S . -B $BuildDir -A $Arch -DBUILD_SHARED_LIBS=OFF -DBUILD_LZHAMDLL_SHARED=ON
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }

Write-Host "Building lzhamdll (unified) and lzhamtest..."
cmake --build $BuildDir --config $Config --target lzhamdll lzhamtest
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

# Locate built artifacts
$exePath = Join-Path $BuildDir "lzhamtest\$Config\lzhamtest.exe"

# lzhamdll output name is configured via CMake (e.g. lzham_x64.dll)
$dllCandidates = Get-ChildItem -Path (Join-Path $BuildDir "lzhamdll\$Config") -Filter "*.dll" -ErrorAction SilentlyContinue

if (!(Test-Path $exePath)) { throw "Executable not found: $exePath" }
if (!$dllCandidates) { Write-Warning "Unified DLL not found in build tree (expected in lzhamdll/$Config)" }

# Create artifacts\unified folder
$unifiedDir = Join-Path $ArtifactsDir "unified"
New-Item -ItemType Directory -Path $unifiedDir -Force | Out-Null

# Move exe
$destExe = Join-Path $unifiedDir "lzhamtest.exe"
if (Test-Path $destExe) { Remove-Item -Path $destExe -Force }
Move-Item -Path $exePath -Destination $destExe -Force

# Move the unified DLL(s) into the unified folder
foreach ($dll in $dllCandidates) {
    $dst = Join-Path $unifiedDir $dll.Name
    if (Test-Path $dst) { Remove-Item -Path $dst -Force }
    Move-Item -Path $dll.FullName -Destination $dst -Force
    Write-Host "Moved unified DLL: $dst"
}

Write-Host "Unified build artifacts moved to: $unifiedDir"

# Create and verify test archives (hello_world.txt -> .lzh), then decompress and compare.
if (-not $NoRunTests) {
    Write-Host "Creating and decompressing test archives using available artifacts"
    & "$PSScriptRoot\create_archives.ps1"
    & "$PSScriptRoot\decompress_archives.ps1"
} else {
    Write-Host "Skipping test archive creation/decompression (NoRunTests specified)"
}
