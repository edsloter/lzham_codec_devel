# run_stream_debug.ps1
# Debugging variant: capture full stdout to decompressed_pipe_full.txt without truncation
$ErrorActionPreference = 'Stop'

# Determine repo root so we place debug output under logs/ at repo root
$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location (Join-Path $scriptFolder "..")

$exe = Join-Path -Path (Get-Location) -ChildPath 'build_x64\lzhamtest\Release\lzhamtest.exe'

# Use the repository 'tests' folder for inputs/outputs
$repoRoot = Join-Path $scriptFolder ".."
$testsDir = Join-Path $repoRoot 'tests'
New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
$infile = Join-Path $testsDir 'out_test.lzh'
$outfile = Join-Path $testsDir 'decompressed_pipe_full.txt'

if (-not (Test-Path $exe)) { Write-Error "Exe not found: $exe"; exit 2 }
if (-not (Test-Path $infile)) { Write-Error "Input file not found: $infile"; exit 2 }

$psi = New-Object System.Diagnostics.ProcessStartInfo($exe, '-S d - -')
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
$p.Start() | Out-Null

# Copy input to stdin
$fsIn = [System.IO.File]::OpenRead($infile)
$fsIn.CopyTo($p.StandardInput.BaseStream)
$p.StandardInput.Close()
$fsIn.Close()
Write-Host "Finished writing input to process stdin"

# Read stdout to file (full capture)
$fsOut = [System.IO.File]::OpenWrite($outfile)
$p.StandardOutput.BaseStream.CopyTo($fsOut)
$fsOut.Close()
Write-Host "Finished reading stdout to $outfile"

$stderrStr = $p.StandardError.ReadToEnd()
$p.WaitForExit()
$exit = $p.ExitCode

Write-Host "Process exit code: $exit"
if ($stderrStr) {
    Write-Host "----- STDERR -----"
    Write-Host $stderrStr
    Write-Host "------------------"
}

if ($exit -ne 0) { Write-Error "Process exited non-zero ($exit)."; exit $exit }

Write-Host "Full stdout written to $outfile"
