$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$vivado = 'D:\XUni\Vivado\2020.2\bin\vivado.bat'
$logDir = Join-Path $projectRoot 'logs'
$logFile = Join-Path $logDir 'xsim_g_cordic_atan2.log'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Push-Location $projectRoot
try {
    & $vivado -mode batch -source scripts/sim_g_cordic_atan2.tcl `
        -log $logFile -journal (Join-Path $logDir 'xsim_g_cordic_atan2.jou')
    if ($LASTEXITCODE -ne 0) {
        throw "CORDIC atan2 XSim failed with exit code $LASTEXITCODE"
    }
    if (-not (Select-String -LiteralPath $logFile -Pattern '^PASS:' -Quiet)) {
        throw "CORDIC atan2 PASS marker missing from $logFile"
    }
    if (Select-String -LiteralPath $logFile -Pattern 'FAIL:|Fatal:' -Quiet) {
        throw "CORDIC atan2 self-check failed; see $logFile"
    }
}
finally {
    Pop-Location
}

