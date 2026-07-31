$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$vectorPath = Join-Path $projectRoot 'matlab\vectors\g_fft_spectrum_input.txt'
$nfft = 4096
$existingLines = [System.IO.File]::ReadAllLines($vectorPath).Length

if ($existingLines -eq 13*$nfft) {
    Write-Output 'FFT_VECTOR_FALLBACK_PASS: 1 kHz frame already present'
    exit 0
}
if ($existingLines -ne 12*$nfft) {
    throw "Expected 12 existing FFT frames, found $existingLines lines"
}

$values = [System.Collections.Generic.List[string]]::new($nfft)
for ($sample = 0; $sample -lt $nfft; $sample++) {
    $phase = 2.0*[Math]::PI*1000.0*$sample/2000000.0+0.28
    $frameValue = [Math]::Round(
        700.0*[Math]::Cos($phase),
        [MidpointRounding]::AwayFromZero)
    $hannValue = [Math]::Round(
        (0.5-0.5*[Math]::Cos(2.0*[Math]::PI*$sample/($nfft-1)))*
            32767.0,
        [MidpointRounding]::AwayFromZero)
    $product = [int64]$frameValue*[int64]$hannValue
    $windowedValue = [Math]::Floor(($product+16384.0)/32768.0)
    $values.Add(([int64]$windowedValue).ToString(
        [Globalization.CultureInfo]::InvariantCulture))
}

[System.IO.File]::AppendAllLines($vectorPath, $values)
$finalLines = [System.IO.File]::ReadAllLines($vectorPath).Length
if ($finalLines -ne 13*$nfft) {
    throw "Expected 13 FFT frames after append, found $finalLines lines"
}
Write-Output 'FFT_VECTOR_FALLBACK_PASS: appended deterministic 1 kHz Hann frame'
