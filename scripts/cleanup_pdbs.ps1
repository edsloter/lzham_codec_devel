[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$DryRun
)

# cleanup_pdbs.ps1
# Remove .pdb (Program Database) files across the repository while preserving
# any files that include '_original.' in their name. Supports -DryRun to
# preview removals without deleting.

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location (Join-Path $scriptRoot "..")

Write-Host "Cleaning up .pdb and .ipdb files across the repository (preserving '*_original.*')"

$pdbFiles = Get-ChildItem -Path . -Recurse -Include *.pdb,*.ipdb -File -ErrorAction SilentlyContinue
if (-not $pdbFiles -or $pdbFiles.Count -eq 0) {
    Write-Host "No matching .pdb or .ipdb files found in repository."
    return
}

foreach ($f in $pdbFiles) {
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

Write-Host ".pdb cleanup complete."
