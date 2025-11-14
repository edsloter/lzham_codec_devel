[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$ArtifactsDir = "artifacts"
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Join-Path $scriptRoot ".."
$testsDir = Join-Path $repoRoot 'tests'
if (-not (Test-Path $testsDir)) { Write-Error "Tests folder not found: $testsDir"; exit 2 }

# Find archives
$archives = Get-ChildItem -Path $testsDir -Filter '*.lzh' -File -ErrorAction SilentlyContinue
if (-not $archives -or $archives.Count -eq 0) {
    Write-Warning "No .lzh archives found in $testsDir to decompress."
    return
}

# Find lzhamtest exes to use for decompression
$exeCandidates = Get-ChildItem -Path (Join-Path $repoRoot $ArtifactsDir) -Recurse -Filter 'lzhamtest.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -Unique
if (-not $exeCandidates -or $exeCandidates.Count -eq 0) {
    Write-Warning "No lzhamtest executables found under $ArtifactsDir. Cannot decompress archives."
    return
}

# Prefer exe that matches archive flavor if possible
foreach ($arc in $archives) {
    $archName = $arc.BaseName
    $outTxt = Join-Path $testsDir ("extracted_${archName}.txt")
    $usedExe = $null

    # try to pick exe based on archive filename (contains folder name)
    foreach ($exe in $exeCandidates) {
        if ($exe -match "/|\\" ) { }
        $parent = Split-Path -Parent $exe | Split-Path -Leaf
        if ($archName -like "*${parent}*") { $usedExe = $exe; break }
    }
    if (-not $usedExe) { $usedExe = $exeCandidates[0] }

    Write-Host "Decompressing $($arc.FullName) with $usedExe -> $outTxt"

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo($usedExe, '-S d - -')
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        $p.Start() | Out-Null

        # feed archive file to stdin
        $fsIn = [System.IO.File]::OpenRead($arc.FullName)
        $fsIn.CopyTo($p.StandardInput.BaseStream)
        $p.StandardInput.Close()
        $fsIn.Close()

        # capture stdout to file
        $fsOut = [System.IO.File]::OpenWrite($outTxt)
        $p.StandardOutput.BaseStream.CopyTo($fsOut)
        $fsOut.Close()

        $stderr = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        if ($p.ExitCode -ne 0) {
            Write-Warning "Decompression failed for $($arc.Name) (exit $($p.ExitCode)): $stderr"
            continue
        }

        # Compute MD5 of original hello_world.txt (if exists) and extracted file
        $orig = Join-Path $testsDir 'hello_world.txt'
        if (-not (Test-Path $orig)) { Write-Warning "Original file for comparison not found: $orig"; continue }
        $h1 = (Get-FileHash -Path $orig -Algorithm MD5).Hash
        $h2 = (Get-FileHash -Path $outTxt -Algorithm MD5).Hash
        Write-Host "MD5 original: $h1"
        Write-Host "MD5 extracted: $h2"
        if ($h1 -eq $h2) { Write-Host "RESULT: MATCH for $($arc.Name)" } else { Write-Warning "RESULT: DIFFER for $($arc.Name)" }

    } catch {
        Write-Warning "Exception during decompression of $($arc.Name): $_"
    }
}

Write-Host "decompress_archives.ps1 complete."