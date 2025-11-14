[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false, ValueFromPipeline=$true)]
    [string[]]$BuildDirs,

    [switch]$All,

    [switch]$DryRun
)

# Helper to remove one or more build directories. Accepts an array of paths so callers
# (such as the wrapper) can remove multiple build_* directories in a single call.
# If -All is specified the script will auto-discover directories matching build_* in
# the repository root (the parent of the scripts folder). Use -WhatIf or -DryRun to
# preview deletions without removing anything.

# Determine repo root (scripts folder is under repoRoot\scripts)
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Join-Path $scriptRoot ".."

if ($All) {
    # Discover build_* directories in the repository root
    Write-Host "Discovering build_* directories under: $repoRoot"
    $found = Get-ChildItem -Path $repoRoot -Directory -Filter "build_*" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    if ($found) {
        if ($null -eq $BuildDirs) { $BuildDirs = @() }
        $BuildDirs += $found
    }
}

if ($null -eq $BuildDirs -or $BuildDirs.Count -eq 0) {
    if ($All) {
        # Nothing discovered with -All: be tolerant and exit successfully.
        Write-Host "No build_* directories found under repo root; nothing to remove."
        return
    }
    throw "BuildDirs parameter is required (or use -All) and must contain at least one path"
}

foreach ($BuildDir in $BuildDirs) {
    if ([string]::IsNullOrWhiteSpace($BuildDir)) {
        Write-Warning "Skipping empty build dir entry"
        continue
    }

    Write-Host "Removing build directory: $BuildDir"
    if (Test-Path $BuildDir) {
        # Respect -WhatIf via ShouldProcess and also support explicit -DryRun
        $shouldRemove = $true
        if ($PSCmdlet.ShouldProcess($BuildDir, 'Remove') -ne $true) { $shouldRemove = $false }
        if ($DryRun) { $shouldRemove = $false }

        if ($shouldRemove) {
            try {
                # We need to preserve any files named '*_original.*' anywhere under the build dir.
                # Remove files selectively and then remove empty directories.
                Write-Host "Removing contents of: $BuildDir (preserving '*_original.*' files)"

                # Remove files that do NOT match the preserve pattern
                $allFiles = Get-ChildItem -Path $BuildDir -Recurse -File -Force -ErrorAction SilentlyContinue
                foreach ($f in $allFiles) {
                    if ($f.Name -like '*_original.*') {
                        Write-Host "Preserving original file: $($f.FullName)"
                        continue
                    }
                    try {
                        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                    } catch {
                        Write-Warning "Failed to remove file '$($f.FullName)': $_"
                    }
                }

                # Attempt to remove directories bottom-up if they are empty (preserved files will keep dirs around)
                $allDirs = Get-ChildItem -Path $BuildDir -Recurse -Directory -Force -ErrorAction SilentlyContinue | Sort-Object -Property FullName -Descending
                foreach ($d in $allDirs) {
                    $contents = Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue
                    if (-not $contents -or $contents.Count -eq 0) {
                        try {
                            Remove-Item -LiteralPath $d.FullName -Force -Recurse -ErrorAction Stop
                        } catch {
                            Write-Warning "Failed to remove directory '$($d.FullName)': $_"
                        }
                    }
                }

                # Finally, try to remove the top-level build dir if empty
                $topContents = Get-ChildItem -LiteralPath $BuildDir -Force -ErrorAction SilentlyContinue
                if (-not $topContents -or $topContents.Count -eq 0) {
                    Remove-Item -LiteralPath $BuildDir -Force -Recurse -ErrorAction Stop
                    Write-Host "Removed build directory: $BuildDir"
                } else {
                    Write-Host "Left build directory in place because it contains preserved files or other items: $BuildDir"
                }
            } catch {
                Write-Warning "Failed to remove build directory '$BuildDir': $_"
            }
        } else {
            Write-Host "(DryRun/WhatIf) Would remove: $BuildDir"
        }
    } else {
        Write-Host "Build directory not found (nothing to remove): $BuildDir"
    }
}
