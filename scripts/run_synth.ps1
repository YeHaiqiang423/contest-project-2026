$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$vivado = 'D:\XUni\Vivado\2020.2\bin\vivado.bat'
$logDir = Join-Path $projectRoot 'logs'
$tcl = Join-Path $PSScriptRoot 'synth_sat_gain.tcl'

New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Push-Location $projectRoot
try {
    & $vivado -mode batch -nolog -nojournal -source $tcl 2>&1 |
        Tee-Object -FilePath (Join-Path $logDir 'synth_sat_gain.log')
    if ($LASTEXITCODE -ne 0) { throw "Vivado synthesis failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

