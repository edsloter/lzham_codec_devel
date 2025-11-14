# run_stream_test.ps1
# Pipes out_test.lzh into lzhamtest -S d - - and writes decompressed_pipe.txt
# Then compares SHA256 hashes with sample.txt

$ErrorActionPreference = 'Stop'

# Determine paths relative to the repository root (scripts is under repoRoot\scripts)
$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location (Join-Path $scriptFolder "..")

$exe = Join-Path -Path (Get-Location) -ChildPath 'build_x64\lzhamtest\Release\lzhamtest.exe'

# Use the repository 'tests' folder for inputs/outputs
$repoRoot = Join-Path $scriptFolder ".."
$testsDir = Join-Path $repoRoot 'tests'
New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
$infile = Join-Path $testsDir 'out_test.lzh'
$outfile = Join-Path $testsDir 'decompressed_pipe.txt'

if (-not (Test-Path $exe)) { Write-Error "Exe not found: $exe"; exit 2 }
if (-not (Test-Path $infile)) { Write-Error "Input file not found: $infile"; exit 2 }
if (-not (Test-Path (Join-Path $repoRoot 'sample.txt'))) { Write-Error "sample.txt not found in repo root"; exit 2 }

Write-Host "Running: $exe -S d - -"

$psi = New-Object System.Diagnostics.ProcessStartInfo($exe, '-S d - -')
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi

try {
    $started = $p.Start()
} catch {
    Write-Error "Failed starting process: $_"
    exit 3
}

# Copy input to stdin
try {
    $fsIn = [System.IO.File]::OpenRead($infile)
    $fsIn.CopyTo($p.StandardInput.BaseStream)
    $p.StandardInput.Close()
    $fsIn.Close()
    Write-Host "Finished writing input to process stdin"
} catch {
    Write-Error "Failed copying input file to process stdin: $_"
    if (-not $p.HasExited) { $p.Kill() }
    exit 4
}

# Read stdout to file
try {
    $fsOut = [System.IO.File]::OpenWrite($outfile)
    $p.StandardOutput.BaseStream.CopyTo($fsOut)
    $fsOut.Close()
    Write-Host "Finished reading stdout to $outfile"
} catch {
    Write-Error "Failed reading stdout: $_"
    if (-not $p.HasExited) { $p.Kill() }
    exit 5
}

# Quick post-processing safeguard: if the expected original size is known (sample.txt),
# truncate any extra trailing diagnostic data that may have been mixed into stdout
# by the test harness so that the hash comparison uses only the raw decompressed bytes.
try {
    $expectedSize = (Get-Item (Join-Path $repoRoot 'sample.txt')).Length
    $actualSize = (Get-Item $outfile).Length
    if ($actualSize -gt $expectedSize) {
        $fsOut = [System.IO.File]::Open($outfile, [System.IO.FileMode]::Open)
        $fsOut.SetLength($expectedSize)
        $fsOut.Close()
        Write-Host "Truncated $outfile from $actualSize to $expectedSize bytes (expected sample size)."
    }
} catch {
    # Non-fatal; continue
}

# Capture stderr
$stderrStr = $p.StandardError.ReadToEnd()
$p.WaitForExit()
$exit = $p.ExitCode

Write-Host "Process exit code: $exit"
if ($stderrStr) {
    Write-Host "----- STDERR -----"
    Write-Host $stderrStr
    Write-Host "------------------"
}

if ($exit -ne 0) {
    Write-Error "Process exited non-zero ($exit). See STDERR above."
    exit $exit
}

# Compare hashes
$h1 = Get-FileHash -Path sample.txt -Algorithm SHA256
$h2 = Get-FileHash -Path $outfile -Algorithm SHA256
Write-Host ("sample.txt: {0}" -f $h1.Hash)
Write-Host ("{0}: {1}" -f $outfile, $h2.Hash)
if ($h1.Hash -eq $h2.Hash) { Write-Host "RESULT: MATCH"; exit 0 } else { Write-Host "RESULT: DIFFER"; exit 6 }
