param(
    [switch]$Gui
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$vivadoBin = 'D:\XUni\Vivado\2020.2\bin'
$logDir = Join-Path $projectRoot 'logs'
$simLog = Join-Path $logDir 'xsim_g_fft_input.log'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

Push-Location $projectRoot
try {
    & (Join-Path $vivadoBin 'xvlog.bat') --sv `
        'rtl/src/g_hann_rom.v' 'rtl/src/g_fft_input_stream.v' `
        'rtl/tb/tb_g_fft_input_stream.sv' 2>&1 |
        Tee-Object -FilePath (Join-Path $logDir 'xvlog_g_fft_input.log')
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed with exit code $LASTEXITCODE" }

    & (Join-Path $vivadoBin 'xelab.bat') tb_g_fft_input_stream `
        -debug typical -s tb_g_fft_input_stream_sim 2>&1 |
        Tee-Object -FilePath (Join-Path $logDir 'xelab_g_fft_input.log')
    if ($LASTEXITCODE -ne 0) { throw "xelab failed with exit code $LASTEXITCODE" }

    if ($Gui) {
        & (Join-Path $vivadoBin 'xsim.bat') tb_g_fft_input_stream_sim -gui
    }
    else {
        & (Join-Path $vivadoBin 'xsim.bat') tb_g_fft_input_stream_sim -runall 2>&1 |
            Tee-Object -FilePath $simLog
    }
    if ($LASTEXITCODE -ne 0) { throw "xsim failed with exit code $LASTEXITCODE" }
    if (-not $Gui) {
        if (-not (Select-String -LiteralPath $simLog -Pattern '^PASS:' -Quiet)) {
            throw "Self-check PASS marker missing from $simLog"
        }
        if (Select-String -LiteralPath $simLog -Pattern 'FAIL:|Fatal:' -Quiet) {
            throw "Self-check failure marker found in $simLog"
        }
    }
}
finally {
    Pop-Location
}
