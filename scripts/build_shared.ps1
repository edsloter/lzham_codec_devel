param(
    [string]$BuildDir = "build_x64_shared",
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

Write-Host "Configuring shared build in: $BuildDir (Arch=$Arch, Config=$Config)"
cmake -S . -B $BuildDir -A $Arch -DBUILD_SHARED_LIBS=ON
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }

Write-Host "Building lzhamdll and lzhamtest..."
cmake --build $BuildDir --config $Config --target lzhamdll lzhamtest
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

# Locate built artifacts
$exePath = Join-Path $BuildDir "lzhamtest\$Config\lzhamtest.exe"
$dllPath = Join-Path $BuildDir "lzhamdll\$Config\lzhamdll.dll"

if (!(Test-Path $exePath)) { throw "Executable not found: $exePath" }
if (!(Test-Path $dllPath)) { Write-Warning "DLL not found at $dllPath - build may have produced an import lib only" }

# Create artifacts\modular folder
$modularDir = Join-Path $ArtifactsDir "modular"
New-Item -ItemType Directory -Path $modularDir -Force | Out-Null

# Move exe
$destExe = Join-Path $modularDir "lzhamtest.exe"
if (Test-Path $destExe) { Remove-Item -Path $destExe -Force }
Move-Item -Path $exePath -Destination $destExe -Force

if (Test-Path $dllPath) {
    $dllLeaf = Split-Path $dllPath -Leaf
    $dstDll = Join-Path $modularDir $dllLeaf
    if (Test-Path $dstDll) { Remove-Item -Path $dstDll -Force }
    Move-Item -Path $dllPath -Destination $dstDll -Force

    # Also move the DLL to the filename the test harness expects at runtime
    if ($Arch -eq "x64") { $expectedDll = "lzham_x64.dll" } else { $expectedDll = "lzham_x86.dll" }
    if ($Config -eq "Debug") { $expectedDll = [IO.Path]::GetFileNameWithoutExtension($expectedDll) + "D.dll" }

    $expectedDllPath = Join-Path $modularDir $expectedDll
    if (Test-Path $expectedDllPath) { Remove-Item -Path $expectedDllPath -Force }
    Copy-Item -Path $dstDll -Destination $expectedDllPath -Force
}

# Move any other DLLs produced by the shared build (e.g. lzhamcomp.dll, lzhamdecomp.dll)
Get-ChildItem -Path $BuildDir -Recurse -Filter "*.dll" | ForEach-Object {
    $src = $_.FullName
    # Only move DLLs from the configuration output folder (e.g. */Release/*.dll)
    if ($src -match "\\$Config\\") {
        $leaf = Split-Path $src -Leaf
        $dst = Join-Path $modularDir $leaf
        if (Test-Path $dst) { Remove-Item -Path $dst -Force }
        Move-Item -Path $src -Destination $dst -Force
    }
}

Write-Host "Shared build artifacts moved to: $modularDir"
Write-Host "Executable: $destExe"
if ($null -ne $dstDll -and (Test-Path $dstDll)) { Write-Host "DLL: $dstDll" }

# Create and verify test archives (hello_world.txt -> .lzh), then decompress and compare.
if (-not $NoRunTests) {
    Write-Host "Creating and decompressing test archives using available artifacts"
    & "$PSScriptRoot\create_archives.ps1"
    & "$PSScriptRoot\decompress_archives.ps1"
} else {
    Write-Host "Skipping test archive creation/decompression (NoRunTests specified)"
}
