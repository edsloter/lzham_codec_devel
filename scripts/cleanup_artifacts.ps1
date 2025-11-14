<#
    cleanup_artifacts.ps1
    Remove all .exe and .dll files from the repo tree except files that include
    "_original." in their filename (to preserve *_original.exe etc.).

    Usage: Invoke the script from other build scripts as:
      & "$PSScriptRoot\cleanup_artifacts.ps1"
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$DryRun
)

Write-Host "Removing .exe and .dll files from repo (preserving *_original.*)"

$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location (Join-Path $root "..")

# Find all .exe and .dll files under the repo
$files = Get-ChildItem -Path . -Recurse -Include *.exe,*.dll -File -ErrorAction SilentlyContinue
foreach ($f in $files) {
    $name = $f.Name
    if ($name -match "_original\.") {
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

Write-Host "Cleanup complete."
