[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$DryRun
)

# Truncate the repository 'tests' folder by removing all files and directories
# except files matching '*_original.*'. Supports -WhatIf/ShouldProcess and a -DryRun flag.

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Join-Path $scriptRoot ".."
$testsDir = Join-Path $repoRoot 'tests'

if (-not (Test-Path $testsDir)) {
    Write-Host "Tests folder not found; creating: $testsDir"
    if (-not $PSCmdlet.ShouldProcess($testsDir, 'New-Item')) { return }
    New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
}

Write-Host "Truncating tests folder: $testsDir (preserving '*_original.*')"

# Collect items in tests dir
$items = Get-ChildItem -LiteralPath $testsDir -Force -ErrorAction SilentlyContinue
foreach ($item in $items) {
    # Skip preserved originals and the canonical hello_world.txt at the top-level
    if ($item.PSIsContainer -eq $false -and ($item.Name -like '*_original.*' -or $item.Name -ieq 'hello_world.txt')) {
        Write-Host "Preserving file: $($item.FullName)"
        continue
    }

    if ($item.PSIsContainer) {
        # Directory: if it contains any *_original.* files, move those to tests\preserved_originals,
        # then remove the directory. Otherwise, delete directory.
        $origFiles = Get-ChildItem -Path $item.FullName -Recurse -File -Filter '*_original.*' -ErrorAction SilentlyContinue
        if ($origFiles) {
            $preserveDir = Join-Path $testsDir 'preserved_originals'
            if (-not (Test-Path $preserveDir)) { New-Item -ItemType Directory -Path $preserveDir -Force | Out-Null }
            foreach ($of in $origFiles) {
                $destName = ($item.Name + '_' + $of.Name)
                $destPath = Join-Path $preserveDir $destName
                if ($PSCmdlet.ShouldProcess($of.FullName, "Move to $destPath")) {
                    if (-not $DryRun) { Move-Item -LiteralPath $of.FullName -Destination $destPath -Force }
                    Write-Host "Moved preserved file: $($of.FullName) -> $destPath"
                }
            }
        }

        if ($PSCmdlet.ShouldProcess($item.FullName, 'Remove Directory')) {
            if (-not $DryRun) {
                try { Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop } catch { Write-Warning "Failed to remove directory $($item.FullName): $_" }
            } else {
                Write-Host "(DryRun) Would remove directory: $($item.FullName)"
            }
        }
    } else {
        # File: remove unless it is *_original.*
        if ($item.Name -like '*_original.*') {
            Write-Host "Preserving file: $($item.FullName)"
            continue
        }
        if ($PSCmdlet.ShouldProcess($item.FullName, 'Remove File')) {
            if (-not $DryRun) {
                try { Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop } catch { Write-Warning "Failed to remove file $($item.FullName): $_" }
            } else {
                Write-Host "(DryRun) Would remove file: $($item.FullName)"
            }
        }
    }
}

Write-Host "Tests folder truncation complete."