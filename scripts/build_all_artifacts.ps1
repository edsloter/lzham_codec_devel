<#
  build_all_artifacts.ps1
  Wrapper that produces all three artifact layouts (static, unified, modular) in one run.
  It calls cleanup once at the start and then invokes each build script with -NoCleanup
  so each build doesn't remove previously produced artifacts.

  Usage: .\scripts\build_all_artifacts.ps1 [-Config Release] [-Arch x64]
#>

param(
  [string]$Config = "Release",
  [string]$Arch = "x64",
  [switch]$SkipVerify = $false,
  [switch]$NoParallel = $false,
  [switch]$NoCleanupLog = $false,
  [switch]$NoCleanupTests = $false,
  [switch]$NoRunTests = $false,
  [switch]$CleanBuildDirs = $false,
  [switch]$CleanBuildDirsAll = $false,
  [switch]$DryRun = $false
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location (Join-Path $scriptRoot "..")

Write-Host "Running full build: cleanup once, then build static, unified, modular (preserving artifacts)"

# Run cleanup once
& "$PSScriptRoot\cleanup_artifacts.ps1"

# Run log cleanup once (unless suppressed)
if (-not $NoCleanupLog) {
  Write-Host "Cleaning log files (.log/.tmp/.bak) (once before builds)"
  & "$PSScriptRoot\cleanup_logs.ps1"
} else {
  Write-Host "Skipping initial log cleanup (NoCleanupLog specified)"
}

$logsDir = Join-Path $PSScriptRoot "..\logs"
New-Item -ItemType Directory -Path $logsDir -Force | Out-Null

# If requested, remove common build directories in one pass using the shared helper.
if ($CleanBuildDirs -or $CleanBuildDirsAll) {
  Write-Host "Removing build directories for arch: $Arch"
  if ($CleanBuildDirsAll) {
    # Ask the helper to discover build_* directories across the repo
    $params = @{}
    if ($DryRun) { $params['DryRun'] = $true }
    $params['All'] = $true
    Write-Host "Invoking CleanBuildDirs.ps1 -All $([string]::Join(' ', ($params.Keys)))"
    & "$PSScriptRoot\CleanBuildDirs.ps1" @params
  } else {
    $dirs = @("build_${Arch}_static","build_${Arch}_unified","build_${Arch}_shared")
    $params = @{}
    if ($DryRun) { $params['DryRun'] = $true }
    $params['BuildDirs'] = $dirs
    & "$PSScriptRoot\CleanBuildDirs.ps1" @params
  }
} else {
  Write-Host "Skipping build-dir cleanup (CleanBuildDirs not specified)"
}

# Truncate tests folder once before the full-run unless caller asked to skip test cleanup
if (-not $NoCleanupTests) {
  Write-Host "Truncating tests folder once before full build (preserving *_original.*)"
  & "$PSScriptRoot\cleanup_tests.ps1"
} else {
  Write-Host "Skipping initial tests truncation (NoCleanupTests specified)"
}

# Helper to run a build and capture logs
function Invoke-BuildAndLog($scriptPath, $logPath, $cfg, $arch) {
  Write-Host "Running: $scriptPath -> log: $logPath"
  # When invoked from this wrapper we always pass -NoCleanupLog so individual
  # build scripts don't remove logs between builds. The wrapper already
  # handled initial log cleanup (unless NoCleanupLog was specified).
  & $scriptPath -Config $cfg -Arch $arch -NoCleanup -NoCleanupLog -NoCleanupTests -NoRunTests 2>&1 | Out-File -FilePath $logPath -Encoding utf8
  return $LASTEXITCODE
}

if (-not $NoParallel) {
  Write-Host "Running builds in parallel (jobs). Logs in: $logsDir"
  $jobs = @()

  $logStatic = Join-Path $logsDir "build_static.log"
  $logUnified = Join-Path $logsDir "build_unified.log"
  $logShared = Join-Path $logsDir "build_shared.log"

  $scriptStatic = Join-Path $PSScriptRoot "build_static.ps1"
  $scriptUnified = Join-Path $PSScriptRoot "build_unified.ps1"
  $scriptShared = Join-Path $PSScriptRoot "build_shared.ps1"

  # Start jobs and pass -NoCleanupLog so build scripts don't purge logs between runs
  $jobs += Start-Job -ScriptBlock { param($s,$c,$a,$l) & $s -Config $c -Arch $a -NoCleanup -NoCleanupLog -NoCleanupTests -NoRunTests 2>&1 | Out-File -FilePath $l -Encoding utf8 } -ArgumentList $scriptStatic, $Config, $Arch, $logStatic
  $jobs += Start-Job -ScriptBlock { param($s,$c,$a,$l) & $s -Config $c -Arch $a -NoCleanup -NoCleanupLog -NoCleanupTests -NoRunTests 2>&1 | Out-File -FilePath $l -Encoding utf8 } -ArgumentList $scriptUnified, $Config, $Arch, $logUnified
  $jobs += Start-Job -ScriptBlock { param($s,$c,$a,$l) & $s -Config $c -Arch $a -NoCleanup -NoCleanupLog -NoCleanupTests -NoRunTests 2>&1 | Out-File -FilePath $l -Encoding utf8 } -ArgumentList $scriptShared, $Config, $Arch, $logShared

  Write-Host "Waiting for background jobs to finish..."
  Wait-Job -Job $jobs

  # Check for job failures
  $failed = $false
  foreach ($j in $jobs) {
    $state = $j.State
    if ($state -ne 'Completed') {
      Write-Warning "Job $($j.Id) ended with state: $state"
      $failed = $true
    }
  }
  if ($failed) { throw "One or more parallel build jobs failed" }
  Write-Host "All parallel builds completed. Logs are under: $logsDir"
} else {
  Write-Host "Running builds sequentially (capturing logs). Logs in: $logsDir"
  $logStatic = Join-Path $logsDir "build_static.log"
  $logUnified = Join-Path $logsDir "build_unified.log"
  $logShared = Join-Path $logsDir "build_shared.log"

  $rc = Invoke-BuildAndLog (Join-Path $PSScriptRoot "build_static.ps1") $logStatic $Config $Arch
  if ($rc -ne 0) { throw "build_static failed (see $logStatic)" }

  $rc = Invoke-BuildAndLog (Join-Path $PSScriptRoot "build_unified.ps1") $logUnified $Config $Arch
  if ($rc -ne 0) { throw "build_unified failed (see $logUnified)" }

  $rc = Invoke-BuildAndLog (Join-Path $PSScriptRoot "build_shared.ps1") $logShared $Config $Arch
  if ($rc -ne 0) { throw "build_shared failed (see $logShared)" }

  Write-Host "All sequential builds completed. Logs are under: $logsDir"
}

if (-not $SkipVerify) {
  if (-not $NoRunTests) {
    Write-Host "Creating test archives (wrapper)"
    & "$PSScriptRoot\create_archives.ps1"
    Write-Host "Decompressing test archives (wrapper)"
    & "$PSScriptRoot\decompress_archives.ps1"
  } else {
    Write-Host "Skipping create/decompress steps (NoRunTests specified)"
  }

  Write-Host "Running verification: verify_artifacts.ps1"
  & "$PSScriptRoot\verify_artifacts.ps1"
  $verExit = $LASTEXITCODE
  if ($verExit -ne 0) {
    Write-Warning "verify_artifacts.ps1 returned exit code $verExit"
    exit $verExit
  } else {
    Write-Host "Verification succeeded."
  }
} else {
  Write-Host "Skipping verification (SkipVerify specified)"
}
