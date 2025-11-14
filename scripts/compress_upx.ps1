<#
  compress_upx.ps1
  Prompt for the location of upx.exe (or use 'upx' on PATH) and run
  UPX with --best on a set of built artifacts under ./artifacts.

  Usage: run from repo root (PowerShell)
    .\scripts\compress_upx.ps1

  The script will report missing files and the exit code for each UPX call.
#>

[CmdletBinding()]
param(
    [switch]$NoParallel,
    [string]$UpxPath,
    [switch]$Backup
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Join-Path $scriptRoot ".."
Set-Location $repoRoot

Write-Host "This script will run UPX (--best) on selected artifacts under ./artifacts."
Write-Host "Default behavior is to run UPX in parallel across files; pass -NoParallel to run sequentially."
Write-Host "If you don't have upx.exe on your PATH, enter the full path to upx.exe when prompted."

if (-not [string]::IsNullOrWhiteSpace($UpxPath)) {
    if (Test-Path $UpxPath) {
        $upxCmd = (Resolve-Path $UpxPath).ProviderPath
    } else {
        # Provided value doesn't resolve to a local file; treat it as a command name
        $upxCmd = $UpxPath
    }
} else {
    $inputPath = Read-Host -Prompt "Enter full path to upx.exe (or press Enter to use 'upx' from PATH)"
    if ([string]::IsNullOrWhiteSpace($inputPath)) {
        $upxCmd = 'upx'
    } else {
        $upxCmd = $inputPath
        if (-not (Test-Path $upxCmd)) {
            Write-Error "upx executable not found at: $upxCmd"
            exit 2
        }
    }
}

Write-Host "Using UPX command: $upxCmd"
Write-Host "Discovering .exe and .dll files under ./artifacts/ (skipping names that include '_original.')"

# Find all .dll and .exe files under artifacts/* (recursively), excluding preserved originals
$artifactsRoot = Join-Path $repoRoot 'artifacts'
$targets = @()
if (Test-Path $artifactsRoot) {
    $targets = Get-ChildItem -Path $artifactsRoot -Recurse -Include *.dll,*.exe -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notmatch '_original\.' } |
               Select-Object -ExpandProperty FullName
}

if (-not $targets -or $targets.Count -eq 0) {
    Write-Warning "No .dll or .exe files found under: $artifactsRoot"
    exit 0
}

foreach ($t in $targets) { Write-Host "  - $t" }

Write-Host "\nFound $($targets.Count) file(s). Press Enter to proceed with UPX --best on all of them, or Ctrl+C to cancel..."
if (-not [string]::IsNullOrWhiteSpace($UpxPath)) {
    Write-Host "Non-interactive run (UpxPath supplied); proceeding with compression of $($targets.Count) file(s)."
} else {
    Write-Host "Found $($targets.Count) file(s). Press Enter to proceed with UPX --best on all of them, or Ctrl+C to cancel..."
    [void][System.Console]::ReadLine()
}

# If requested, create backups named <name>_original.<ext> before compressing. Do this up-front so
# compression jobs don't need to handle it and to avoid concurrent copies.
if ($Backup) {
    Write-Host "Backup requested: creating '*_original.*' copies for discovered targets..."
    foreach ($t in $targets) {
        try {
            if (-not (Test-Path $t)) { Write-Warning "Skipping backup (not found): $t"; continue }
            $dir = Split-Path -Parent $t
            $base = [System.IO.Path]::GetFileNameWithoutExtension($t)
            $ext = [System.IO.Path]::GetExtension($t)
            $backupName = "${base}_original${ext}"
            $backupPath = Join-Path $dir $backupName
            if (Test-Path $backupPath) {
                Write-Host "Backup already exists, leaving in place: $backupPath"
            } else {
                Copy-Item -LiteralPath $t -Destination $backupPath -Force -ErrorAction Stop
                Write-Host "Created backup: $backupPath"
            }
        } catch {
            Write-Warning ("Failed to create backup for {0}: {1}" -f $t, $_.Exception.Message)
        }
    }
}

$results = @()
if (-not $NoParallel) {
    Write-Host "Running UPX in parallel jobs (Start-Job)..."
    $jobs = @()
    foreach ($t in $targets) {
        if (-not (Test-Path $t)) {
            Write-Warning "Skipping (not found): $t"
            $results += @{File=$t;Status='Missing'}
            continue
        }
        $jobs += Start-Job -ArgumentList $upxCmd,$t -ScriptBlock {
            param($upx,$file)
            try {
                $out = & $upx --best $file 2>&1
                $ec = $LASTEXITCODE
                [PSCustomObject]@{File=$file;ExitCode=$ec;Output=$out}
            } catch {
                [PSCustomObject]@{File=$file;ExitCode=-1;Output=@("EXCEPTION: $($_.Exception.Message)")}
            }
        }
    }

    if ($jobs.Count -gt 0) {
        Write-Host "Waiting for $($jobs.Count) job(s) to finish..."
        Wait-Job -Job $jobs
        foreach ($j in $jobs) {
            $res = Receive-Job -Job $j -ErrorAction SilentlyContinue
            if ($res -is [System.Array]) { $res = $res[0] }
            if ($null -ne $res) {
                if ($res.ExitCode -eq 0) {
                    Write-Host "UPX succeeded for: $($res.File)"
                    $results += @{File=$res.File;Status='Ok';ExitCode=$res.ExitCode}
                } else {
                    Write-Warning "UPX returned exit code $($res.ExitCode) for: $($res.File)"
                    $results += @{File=$res.File;Status='Error';ExitCode=$res.ExitCode}
                }
                # Print the tool output for visibility
                foreach ($line in $res.Output) { Write-Host $line }
            } else {
                Write-Warning "Job produced no output or failed: $($j.Id)"
            }
            Remove-Job -Job $j -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    foreach ($t in $targets) {
        if (-not (Test-Path $t)) {
            Write-Warning "Skipping (not found): $t"
            $results += @{File=$t;Status='Missing'}
            continue
        }

        Write-Host "Running: $upxCmd --best `"$t`""
        try {
            & $upxCmd --best $t 2>&1 | ForEach-Object { Write-Host $_ }
            $ec = $LASTEXITCODE
            if ($ec -eq 0) {
                Write-Host "UPX succeeded for: $t"
                $results += @{File=$t;Status='Ok';ExitCode=$ec}
            } else {
                Write-Warning "UPX returned exit code $ec for: $t"
                $results += @{File=$t;Status='Error';ExitCode=$ec}
            }
        } catch {
            Write-Warning ("Exception invoking UPX for {0}: {1}" -f $t, $_.Exception.Message)
            $results += @{File=$t;Status='Exception';Error=$_.Exception.Message}
        }
    }
}

Write-Host "\n=== UPX run summary ==="
foreach ($r in $results) {
    if ($r.Status -eq 'Ok') { Write-Host "OK      : $($r.File) (exit $($r.ExitCode))" }
    elseif ($r.Status -eq 'Missing') { Write-Host "Missing : $($r.File)" }
    elseif ($r.Status -eq 'Error') { Write-Host "Error   : $($r.File) (exit $($r.ExitCode))" }
    else { Write-Host "Other   : $($r.File) - $($r.Error)" }
}

Write-Host "compress_upx.ps1 finished."
