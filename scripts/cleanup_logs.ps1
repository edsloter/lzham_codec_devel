<#
  cleanup_logs.ps1
  Remove temporary/unneeded files across the repo while preserving any file
  that contains "_original." in its name.

  This script removes files with these extensions: .log, .tmp, .bak
  It is conservative — it will not remove binaries (.exe/.dll) or build
  artifacts other than logs/backups. Run from repo root via:
    & .\scripts\cleanup_logs.ps1
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$DryRun
)

Write-Host "Cleaning up .log/.tmp/.bak/.tlog files (preserving '*_original.*')"

$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location (Join-Path $root "..")

$extensions = @('*.log','*.tmp','*.bak','*.tlog')

$files = Get-ChildItem -Path . -Recurse -Include $extensions -File -ErrorAction SilentlyContinue
if (-not $files -or $files.Count -eq 0) {
    Write-Host "No log-like files found matching patterns: $($extensions -join ',')"
} else {
    foreach ($f in $files) {
        if ($f.Name -match "_original\.") {
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
}

# If a top-level logs directory exists (used by the build wrapper), remove it if empty
$logsDir = Join-Path (Get-Location) 'logs'
if (Test-Path $logsDir) {
    try {
        $contents = Get-ChildItem -LiteralPath $logsDir -Force -ErrorAction SilentlyContinue
        if (-not $contents -or $contents.Count -eq 0) {
            if (-not $PSCmdlet.ShouldProcess($logsDir, 'Remove')) {
                Write-Host "(WhatIf) Would remove empty logs directory: $logsDir"
            } elseif ($DryRun) {
                Write-Host "(DryRun) Would remove empty logs directory: $logsDir"
            } else {
                Remove-Item -LiteralPath $logsDir -Force -Recurse -ErrorAction Stop
                Write-Host "Removed empty logs directory: $logsDir"
            }
        } else {
            Write-Host "Left logs directory in place (contains files): $logsDir"
        }
    } catch {
        Write-Warning "Failed to inspect/remove logs directory ${logsDir}: $_"
    }
}

Write-Host "Log cleanup complete."
