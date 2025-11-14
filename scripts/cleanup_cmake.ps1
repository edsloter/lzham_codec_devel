[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$DryRun,
    [switch]$PreserveBuildDirs
)

# cleanup_cmake.ps1
# Remove CMake-generated files across the repository: CMakeCache.txt, cmake_install.cmake,
# and directories named CMakeFiles. By default this targets files outside build_* directories.
# Use -PreserveBuildDirs to explicitly avoid removing anything under build_*.

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location (Join-Path $scriptRoot "..")

Write-Host "Cleaning up CMake-generated files (CMakeCache.txt, cmake_install.cmake, CMakeFiles/)."

# Discover candidate files and directories
$candidates = @()
$candidates += Get-ChildItem -Path . -Recurse -Include 'CMakeCache.txt','cmake_install.cmake' -File -ErrorAction SilentlyContinue
$candidates += Get-ChildItem -Path . -Recurse -Directory -Filter 'CMakeFiles' -ErrorAction SilentlyContinue

if (-not $candidates -or $candidates.Count -eq 0) {
    Write-Host "No CMake-generated files found in repository."
    return
}

foreach ($item in $candidates) {
    $full = $item.FullName

    # Skip items under build_* when PreserveBuildDirs is specified or when by default we only target non-build dirs
    $inBuildDir = ($full -match "\\build_[^\\]+\\")

    # Preserve any files explicitly marked as originals (do not remove '*_original.*')
    if ($item.Name -like '*_original.*') {
        Write-Host "Skipping preserved file: $full"
        continue
    }
    if ($inBuildDir -and $PreserveBuildDirs) {
        Write-Host "Skipping (preserve build dirs): $full"
        continue
    }

    # By default we only remove CMake artifacts that are NOT under build_* directories
    if (-not $inBuildDir) {
        if (-not $PSCmdlet.ShouldProcess($full, 'Remove')) {
            Write-Host "(WhatIf) Would remove: $full"
            continue
        }
        if ($DryRun) {
            Write-Host "(DryRun) Would remove: $full"
            continue
        }

        try {
            if ($item.PSIsContainer) {
                Remove-Item -LiteralPath $full -Force -Recurse -ErrorAction Stop
                Write-Host "Removed directory: $full"
            } else {
                Remove-Item -LiteralPath $full -Force -ErrorAction Stop
                Write-Host "Removed file: $full"
            }
        } catch {
            Write-Warning ("Failed to remove {0}: {1}" -f $full, $_.Exception.Message)
        }
    } else {
        # Item is under build_* and PreserveBuildDirs was not set; skip by default but inform user
        Write-Host "Skipping CMake artifact in build dir (use -PreserveBuildDirs=$false to remove): $full"
    }
}

Write-Host "CMake cleanup complete."
