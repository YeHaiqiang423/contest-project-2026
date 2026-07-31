$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$vivado = 'D:\XUni\Vivado\2020.2\bin\vivado.bat'
$logDir = Join-Path $projectRoot 'logs'
$logFile = Join-Path $logDir 'xsim_g_measurement_stabilizer.log'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Push-Location $projectRoot
try {
    & $vivado -mode batch -source scripts/sim_g_measurement_stabilizer.tcl `
        -log $logFile -journal (Join-Path $logDir 'xsim_g_measurement_stabilizer.jou')
    if ($LASTEXITCODE -ne 0) {
        throw "Measurement stabilizer XSim failed with exit code $LASTEXITCODE"
    }
    if (-not (Select-String -LiteralPath $logFile -Pattern '^PASS:' -Quiet)) {
        throw "Measurement stabilizer PASS marker missing from $logFile"
    }
    if (Select-String -LiteralPath $logFile -Pattern 'FAIL:|Fatal:' -Quiet) {
        throw "Measurement stabilizer self-check failed; see $logFile"
    }
}
finally {
    Pop-Location
}
