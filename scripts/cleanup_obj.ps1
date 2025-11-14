[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$DryRun
)

# cleanup_obj.ps1
# Remove object files (*.o, *.obj) across the repository while preserving
# any files that include '_original.' in their name. Supports -DryRun to
# preview removals without deleting.

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location (Join-Path $scriptRoot "..")

Write-Host "Cleaning up object files (*.o, *.obj) across the repository (preserving '*_original.*')"

$patterns = @('*.o','*.obj')
$objFiles = @()
foreach ($p in $patterns) {
    $objFiles += Get-ChildItem -Path . -Recurse -Include $p -File -ErrorAction SilentlyContinue
}

if (-not $objFiles -or $objFiles.Count -eq 0) {
    Write-Host "No object files found in repository."
    return
}

foreach ($f in $objFiles) {
    if ($f.Name -like '*_original.*') {
        Write-Host "Skipping preserved file: $($f.FullName)"
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($f.FullName, 'Remove')) {
        Write-Host "(WhatIf) Would remove: $($f.FullName)"
        continue
    }

    if ($DryRun) {
        Write-Host "(DryRun) Would remove: $($f.FullName)"
        continue
    }

    try {
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
        Write-Host "Removed: $($f.FullName)"
    } catch {
        Write-Warning "Failed to remove $($f.FullName): $($_.Exception.Message)"
    }
}

Write-Host "Object file cleanup complete."
