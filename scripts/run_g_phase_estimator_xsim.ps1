$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$vivado = 'D:\XUni\Vivado\2020.2\bin\vivado.bat'
$logDir = Join-Path $projectRoot 'logs'
$logFile = Join-Path $logDir 'xsim_g_phase_estimator.log'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

Push-Location $projectRoot
try {
    & $vivado -mode batch -source scripts/sim_g_phase_estimator.tcl `
        -log $logFile -journal (Join-Path $logDir 'xsim_g_phase_estimator.jou')
    if ($LASTEXITCODE -ne 0) {
        throw "Phase estimator XSim failed with exit code $LASTEXITCODE"
    }
    if (-not (Select-String -LiteralPath $logFile -Pattern '^PASS:' -Quiet)) {
        throw "Phase estimator PASS marker missing from $logFile"
    }
    if (Select-String -LiteralPath $logFile -Pattern 'FAIL:|Fatal:' -Quiet) {
        throw "Phase estimator self-check failed; see $logFile"
    }
}
finally {
    Pop-Location
}
