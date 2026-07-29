param(
    [switch]$SkipVectors,
    [switch]$Gui
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$matlab = 'G:\Matlab\bin\matlab.exe'
$vivado = 'D:\XUni\Vivado\2020.2\bin\vivado.bat'
$logDir = Join-Path $projectRoot 'logs'
$simLog = Join-Path $logDir 'xsim_g_fft_spectrum.log'
$simJournal = Join-Path $logDir 'xsim_g_fft_spectrum.jou'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

Push-Location $projectRoot
try {
    if (-not $SkipVectors) {
        & $matlab -batch "cd('$($projectRoot.Replace("'", "''"))'); addpath('matlab/model'); generate_g_fft_spectrum_vectors"
        if ($LASTEXITCODE -ne 0) {
            throw "FFT spectrum vector generation failed with exit code $LASTEXITCODE"
        }
    }

    $vivadoMode = if ($Gui) { 'gui' } else { 'batch' }
    $vivadoArgs = @('-mode', $vivadoMode, '-source', 'scripts/sim_g_fft_spectrum.tcl',
        '-log', $simLog, '-journal', $simJournal)
    if ($Gui) { $vivadoArgs += @('-tclargs', 'gui') }
    & $vivado @vivadoArgs
    if ($LASTEXITCODE -ne 0) {
        throw "FFT spectrum XSim failed with exit code $LASTEXITCODE"
    }
    if (-not $Gui -and -not (Select-String -LiteralPath $simLog -Pattern '^PASS:' -Quiet)) {
        throw "Self-check PASS marker missing from $simLog"
    }
    if (-not $Gui -and (Select-String -LiteralPath $simLog -Pattern 'FAIL:|Fatal:' -Quiet)) {
        throw "Self-check failure marker found in $simLog"
    }
}
finally {
    Pop-Location
}
