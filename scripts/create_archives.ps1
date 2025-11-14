[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$ArtifactsDir = "artifacts"
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Join-Path $scriptRoot ".."
$testsDir = Join-Path $repoRoot 'tests'
New-Item -ItemType Directory -Path $testsDir -Force | Out-Null

# Create hello_world.txt in tests
$hello = Join-Path $testsDir 'hello_world.txt'
$helloContent = @"
Hello, world!
This is a test archive created by create_archives.ps1
"@
Set-Content -LiteralPath $hello -Value $helloContent -Encoding UTF8
Write-Host "Created sample file: $hello"

# Find available lzhamtest executables under artifacts\*\lzhamtest.exe
$exeCandidates = Get-ChildItem -Path (Join-Path $repoRoot $ArtifactsDir) -Recurse -Filter 'lzhamtest.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -Unique

if (-not $exeCandidates -or $exeCandidates.Count -eq 0) {
    Write-Warning "No lzhamtest executables found under $ArtifactsDir. No archives will be created."
    return
}

# For each exe create an archive named out_test_<flavor>.lzh in tests dir
foreach ($exe in $exeCandidates) {
    try {
        $flavor = Split-Path -Parent $exe | Split-Path -Leaf
        if (-not $flavor) { $flavor = ([IO.Path]::GetFileName((Split-Path $exe -Parent))) }
        $outName = "out_test_${flavor}.lzh"
        $outPath = Join-Path $testsDir $outName

        Write-Host "Creating archive with $exe -> $outPath"

        $psi = New-Object System.Diagnostics.ProcessStartInfo($exe, "-S c - $outPath")
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        $p.Start() | Out-Null

        # feed hello_world.txt to stdin
        $fsIn = [System.IO.File]::OpenRead($hello)
        $fsIn.CopyTo($p.StandardInput.BaseStream)
        $p.StandardInput.Close()
        $fsIn.Close()

        $stderr = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        if ($p.ExitCode -ne 0) {
            Write-Warning "Creating archive with $exe failed (exit $($p.ExitCode)): $stderr"
        } else {
            if (Test-Path $outPath) { Write-Host "Archive created: $outPath" } else { Write-Warning "Expected archive not found after successful exit: $outPath" }
        }
    } catch {
        Write-Warning ("Exception while creating archive with {0}: {1}" -f $exe, $_)
    }
}

Write-Host "create_archives.ps1 complete. Archives placed in: $testsDir"