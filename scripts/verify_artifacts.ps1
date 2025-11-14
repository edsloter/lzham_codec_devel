<#
    verify_artifacts.ps1
    Runs available lzhamtest artifacts through the streaming decompression test
    and compares extracted bytes to the canonical sample file in ./tests/hello_world.txt.

    Behavior:
      - Uses ./tests/ as the canonical place for archives (.lzh) and extracted outputs.
      - If one or more *.lzh files are present in ./tests/, each archive is decompressed
        with each available artifact variant (static/unified/modular) and the result is
        compared to tests/hello_world.txt (SHA256).
      - If no archives are present, the script will attempt to use the single InFile
        (default tests/out_test.lzh). If that is missing but the sample exists, the
        script will attempt to create the archive using any available lzhamtest exe.
#>

param(
    [string]$ArtifactsDir = "artifacts",
    [string]$InFile = "out_test.lzh",
    [string]$Sample = "hello_world.txt"
)

$ErrorActionPreference = 'Stop'

$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Join-Path $scriptFolder ".."

# Tests folder (inputs/outputs)
$testsDir = Join-Path $repoRoot 'tests'
New-Item -ItemType Directory -Path $testsDir -Force | Out-Null

# Logs folder at repository root (used for per-build logs)
$logsDir = Join-Path $repoRoot 'logs'
New-Item -ItemType Directory -Path $logsDir -Force | Out-Null

# Resolve default paths into tests/repo locations
if ($InFile -eq 'out_test.lzh') { $InFile = Join-Path $testsDir 'out_test.lzh' }
if ($Sample -eq 'hello_world.txt') { $Sample = Join-Path $testsDir 'hello_world.txt' }

# Helper to run a decompression using an lzhamtest exe and compare to the sample
function Invoke-RunStream {
    param(
        [string]$ExePath,
        [string]$ArchivePath,
        [string]$OutPath,
        [string]$SamplePath
    )

    if (-not (Test-Path $ExePath)) { return @{Exe=$ExePath;Archive=$ArchivePath;Status='MissingExe'} }
    if (-not (Test-Path $ArchivePath)) { return @{Exe=$ExePath;Archive=$ArchivePath;Status='MissingArchive'} }

    Write-Host "`nRunning: $ExePath  Archive: $ArchivePath -> $OutPath"

    $psi = New-Object System.Diagnostics.ProcessStartInfo($ExePath, '-S d - -')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $p.Start() | Out-Null

    try {
        $fsIn = [System.IO.File]::OpenRead($ArchivePath)
        $fsIn.CopyTo($p.StandardInput.BaseStream)
        $p.StandardInput.Close()
        $fsIn.Close()
    } catch {
        return @{Exe=$ExePath;Archive=$ArchivePath;Status='FeedFailed';Error=$_.Exception.Message}
    }

    # capture stdout to out path
    try {
        $fsOut = [System.IO.File]::OpenWrite($OutPath)
        $p.StandardOutput.BaseStream.CopyTo($fsOut)
        $fsOut.Close()
    } catch {
        return @{Exe=$ExePath;Archive=$ArchivePath;Status='CaptureFailed';Error=$_.Exception.Message}
    }

    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        return @{Exe=$ExePath;Archive=$ArchivePath;Status='Fail';ExitCode=$p.ExitCode;Stderr=$stderr}
    }

    if (-not (Test-Path $SamplePath)) {
        return @{Exe=$ExePath;Archive=$ArchivePath;Status='NoSample';Note='Sample missing'}
    }

    $hOrig = (Get-FileHash -Path $SamplePath -Algorithm SHA256).Hash
    $hOut = (Get-FileHash -Path $OutPath -Algorithm SHA256).Hash
    if ($hOrig -eq $hOut) { return @{Exe=$ExePath;Archive=$ArchivePath;Status='Pass'} } else { return @{Exe=$ExePath;Archive=$ArchivePath;Status='Fail';Hash1=$hOrig;Hash2=$hOut} }
}

# Main flow
$results = @()

# Find available executables
$exeStatic = Join-Path $ArtifactsDir 'static\lzhamtest.exe'
$exeUnified = Join-Path $ArtifactsDir 'unified\lzhamtest.exe'
$exeModular = Join-Path $ArtifactsDir 'modular\lzhamtest.exe'

# Look for archives in tests
$archives = Get-ChildItem -Path $testsDir -Filter '*.lzh' -File -ErrorAction SilentlyContinue

if ($archives -and $archives.Count -gt 0) {
    foreach ($arc in $archives) {
        $base = $arc.BaseName
        $outS = Join-Path $testsDir ("decompressed_static_${base}.txt")
        $outU = Join-Path $testsDir ("decompressed_unified_${base}.txt")
        $outM = Join-Path $testsDir ("decompressed_modular_${base}.txt")

        $results += Invoke-RunStream -ExePath $exeStatic -ArchivePath $arc.FullName -OutPath $outS -SamplePath $Sample
        $results += Invoke-RunStream -ExePath $exeUnified -ArchivePath $arc.FullName -OutPath $outU -SamplePath $Sample
        $results += Invoke-RunStream -ExePath $exeModular -ArchivePath $arc.FullName -OutPath $outM -SamplePath $Sample
    }
} else {
    # No archives — try single InFile behavior
    if (-not (Test-Path $InFile)) {
        if (-not (Test-Path $Sample)) {
            Write-Warning "Neither input archive ($InFile) nor sample ($Sample) found. Skipping verification."
            exit 0
        }

        # Try to create InFile using any available exe
        $created = $false
        foreach ($exe in @($exeStatic,$exeUnified,$exeModular)) {
            if (Test-Path $exe) {
                Write-Host "Trying to create archive $InFile using $exe"
                $psi = New-Object System.Diagnostics.ProcessStartInfo($exe, "-S c - $InFile")
                $psi.UseShellExecute = $false
                $psi.RedirectStandardInput = $true
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.CreateNoWindow = $true

                $p = New-Object System.Diagnostics.Process
                $p.StartInfo = $psi
                $p.Start() | Out-Null

                $fsIn = [System.IO.File]::OpenRead($Sample)
                $fsIn.CopyTo($p.StandardInput.BaseStream)
                $p.StandardInput.Close()
                $fsIn.Close()

                $p.WaitForExit()
                if ($p.ExitCode -eq 0 -and (Test-Path $InFile)) { $created = $true; break }
            }
        }

        if (-not $created) { Write-Error "Failed to create input archive $InFile from sample. Cannot verify."; exit 2 }
    }

    $outS = Join-Path $testsDir 'decompressed_static.txt'
    $outU = Join-Path $testsDir 'decompressed_unified.txt'
    $outM = Join-Path $testsDir 'decompressed_modular.txt'

    $results += Invoke-RunStream -ExePath $exeStatic -ArchivePath $InFile -OutPath $outS -SamplePath $Sample
    $results += Invoke-RunStream -ExePath $exeUnified -ArchivePath $InFile -OutPath $outU -SamplePath $Sample
    $results += Invoke-RunStream -ExePath $exeModular -ArchivePath $InFile -OutPath $outM -SamplePath $Sample
}

# Summary
Write-Host "`n=== Summary ==="
foreach ($r in $results) { Write-Host ("{0} [{1}] -> {2}" -f $r.Exe, $r.Archive, $r.Status) }

if ($results | Where-Object { $_.Status -ne 'Pass' }) { exit 1 } else { exit 0 }
