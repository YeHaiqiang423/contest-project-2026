param([switch]$Gui)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$vivado = 'D:\XUni\Vivado\2020.2\bin\vivado.bat'
$logDir = Join-Path $projectRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$arguments = @('-mode', $(if ($Gui) {'gui'} else {'batch'}),
    '-source', 'scripts/sim_g_tjc_display_uart.tcl',
    '-log', 'logs/xsim_g_tjc_display_uart.log',
    '-journal', 'logs/xsim_g_tjc_display_uart.jou')
if ($Gui) { $arguments += @('-tclargs', 'gui') }
$output = & $vivado @arguments 2>&1 |
    Tee-Object -FilePath (Join-Path $logDir 'xsim_g_tjc_display_uart.console.log')
if ($LASTEXITCODE -ne 0) { throw "TJC UART XSim failed with exit code $LASTEXITCODE" }
if (-not ($output -match 'PASS:') -or ($output -match 'Fatal:|FAIL:')) {
    throw 'TJC UART XSim did not produce a clean PASS result'
}
