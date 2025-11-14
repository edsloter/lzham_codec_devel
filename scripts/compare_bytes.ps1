# compare_bytes.ps1
Param(
    [string]$file1 = 'sample.txt',
    [string]$file2 = 'decompressed_pipe.txt'
)

# If caller used the default short name, prefer the repo tests location so
# comparisons operate on the same files the other scripts write.
if ($file2 -eq 'decompressed_pipe.txt') {
    $scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $repoRoot = Join-Path $scriptFolder ".."
    $testsDir = Join-Path $repoRoot 'tests'
    $candidate = Join-Path $testsDir 'decompressed_pipe.txt'
    if (Test-Path $candidate) { $file2 = $candidate }
}

if (-not (Test-Path $file1)) { Write-Error "File not found: $file1"; exit 2 }
if (-not (Test-Path $file2)) { Write-Error "File not found: $file2"; exit 2 }

$a = [System.IO.File]::ReadAllBytes($file1)
$b = [System.IO.File]::ReadAllBytes($file2)
Write-Host "$file1 length: $($a.Length)"
Write-Host "$file2 length: $($b.Length)"
$min = [Math]::Min($a.Length,$b.Length)
$firstDiff = -1
for ($i=0; $i -lt $min; $i++) {
    if ($a[$i] -ne $b[$i]) { $firstDiff = $i; break }
}

if ($firstDiff -eq -1) {
    if ($a.Length -ne $b.Length) {
        Write-Host "Files identical up to min length, lengths differ"
    } else {
        Write-Host "Files identical"
    }
} else {
    Write-Host "First differing byte index: $firstDiff"
    Write-Host ("sample[{0}]={1:X2}  pipe[{0}]={2:X2}" -f $firstDiff, $a[$firstDiff], $b[$firstDiff])
    $start = [Math]::Max(0, $firstDiff - 16)
    $end = [Math]::Min($min - 1, $firstDiff + 16)
    Write-Host ("Context (hex) from {0}:" -f $file1)
    for ($i = $start; $i -le $end; $i++) { Write-Host -NoNewline ("{0:X2} " -f $a[$i]) }
    Write-Host ""
    Write-Host ("Context (hex) from {0}:" -f $file2)
    for ($i = $start; $i -le $end; $i++) { Write-Host -NoNewline ("{0:X2} " -f $b[$i]) }
    Write-Host ""
}
