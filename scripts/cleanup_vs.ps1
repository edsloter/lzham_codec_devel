[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$DryRun,
    [string[]]$Patterns = @('*.tlog','*.ipdb','*.recipe','*.exp','*.ilk','*.lastbuildstate')
)

# cleanup_vs.ps1
# Remove common Visual Studio / MSBuild intermediate files across the repo
# while preserving any file that contains '_original.' in its name.
# Supports -DryRun and honors ShouldProcess/WhatIf semantics.

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location (Join-Path $scriptRoot "..")

Write-Host "Cleaning up Visual Studio/MSBuild intermediates: $($Patterns -join ', ') (preserving '*_original.*')"

$files = Get-ChildItem -Path . -Recurse -Include $Patterns -File -ErrorAction SilentlyContinue
if (-not $files -or $files.Count -eq 0) {
    Write-Host "No VS/MSBuild intermediate files found matching: $($Patterns -join ', ')"
    return
}

foreach ($f in $files) {
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

Write-Host "VS/MSBuild intermediate cleanup complete."
