[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$All,
    [switch]$DryRun,
    [switch]$KeepArtifacts,
    [switch]$PreservePdbs,
    [switch]$PreserveObj,
    [switch]$PreserveCMake
)

# cleanup_all.ps1
# Wrapper that runs the repository cleanup helpers in a recommended order.
# By default this will run CleanBuildDirs, cleanup_artifacts, cleanup_logs, cleanup_tests.
# Pass -KeepArtifacts to skip the artifact removal step.

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location (Join-Path $scriptRoot "..")

Write-Host "Running repository-wide cleanup"

# 1) Clean build directories (either discovered with -All or default common dirs)
$cbParams = @{}
if ($DryRun) { $cbParams['DryRun'] = $true }
if ($All) {
    Write-Host "Invoking CleanBuildDirs.ps1 -All"
    $cbParams['All'] = $true
} else {
    # Default set of build directories commonly used by the scripts
    $cbParams['BuildDirs'] = @('build_x64_static','build_x64_unified','build_x64_shared')
}

if ($PSCmdlet.ShouldProcess('CleanBuildDirs','Remove build directories')) {
    & "$PSScriptRoot\CleanBuildDirs.ps1" @cbParams
}

# 2) Optionally remove artifacts (.exe/.dll)
if ($KeepArtifacts) {
    Write-Host "Skipping artifact removal (KeepArtifacts specified)"
} else {
    if ($PSCmdlet.ShouldProcess('cleanup_artifacts.ps1','Remove .exe/.dll files')) {
        $caParams = @{}
        if ($DryRun) { $caParams['DryRun'] = $true }
        & "$PSScriptRoot\cleanup_artifacts.ps1" @caParams
    }
}

# 2.5) Remove PDB symbol files (skip when -PreservePdbs is set)
if ($PreservePdbs) {
    Write-Host "Preserving .pdb files because -PreservePdbs was specified"
} else {
    if ($PSCmdlet.ShouldProcess('cleanup_pdbs.ps1','Remove .pdb files')) {
        $cpParams = @{}
        if ($DryRun) { $cpParams['DryRun'] = $true }
        & "$PSScriptRoot\cleanup_pdbs.ps1" @cpParams
    }
}

# 2.6) Remove compiled object files (*.o, *.obj) unless -PreserveObj is specified
if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('PreserveObj') -and $PreserveObj) {
    Write-Host "Preserving object files because -PreserveObj was specified"
} else {
    if ($PSCmdlet.ShouldProcess('cleanup_obj.ps1','Remove object files')) {
        $coParams = @{}
        if ($DryRun) { $coParams['DryRun'] = $true }
        & "$PSScriptRoot\cleanup_obj.ps1" @coParams
    }
}

# 2.7) Remove Visual Studio / MSBuild intermediate files (tlog, ipdb, recipe, etc.)
if ($PSCmdlet.ShouldProcess('cleanup_vs.ps1','Remove Visual Studio/MSBuild intermediate files')) {
    $vsParams = @{}
    if ($DryRun) { $vsParams['DryRun'] = $true }
    & "$PSScriptRoot\cleanup_vs.ps1" @vsParams
}

# 3) Cleanup logs
if ($PSCmdlet.ShouldProcess('cleanup_logs.ps1','Remove .log/.tmp/.bak files')) {
    $clParams = @{}
    if ($DryRun) { $clParams['DryRun'] = $true }
    & "$PSScriptRoot\cleanup_logs.ps1" @clParams
}

# 3.5) Cleanup CMake-generated files (skip when -PreserveCMake is set)
if ($PreserveCMake) {
    Write-Host "Preserving CMake-generated files because -PreserveCMake was specified"
} else {
    if ($PSCmdlet.ShouldProcess('cleanup_cmake.ps1','Remove CMake-generated files (CMakeCache.txt, CMakeFiles, cmake_install.cmake)')) {
        $cmParams = @{}
        if ($DryRun) { $cmParams['DryRun'] = $true }
        # Pass PreserveBuildDirs down if provided to wrapper (default is to skip build_* dirs)
        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('PreserveBuildDirs') -and $PreserveBuildDirs) { $cmParams['PreserveBuildDirs'] = $true }
        & "$PSScriptRoot\cleanup_cmake.ps1" @cmParams
    }
}

# 4) Truncate tests folder (preserve *_original.* and hello_world.txt)
if ($PSCmdlet.ShouldProcess('cleanup_tests.ps1','Truncate tests folder')) {
    $ctParams = @{}
    if ($DryRun) { $ctParams['DryRun'] = $true }
    & "$PSScriptRoot\cleanup_tests.ps1" @ctParams
}

Write-Host "Repository cleanup complete."


