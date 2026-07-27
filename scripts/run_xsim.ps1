$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$vivadoBin = 'D:\XUni\Vivado\2020.2\bin'
$logDir = Join-Path $projectRoot 'logs'
$workDir = Join-Path $projectRoot 'results\xsim_work'

New-Item -ItemType Directory -Path $logDir, $workDir -Force | Out-Null
Push-Location $projectRoot
try {
    & (Join-Path $vivadoBin 'xvlog.bat') --sv 'rtl/src/sat_gain.sv' 'rtl/tb/tb_sat_gain.sv' 2>&1 |
        Tee-Object -FilePath (Join-Path $logDir 'xvlog.log')
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed with exit code $LASTEXITCODE" }

    & (Join-Path $vivadoBin 'xelab.bat') tb_sat_gain -s tb_sat_gain_sim 2>&1 |
        Tee-Object -FilePath (Join-Path $logDir 'xelab.log')
    if ($LASTEXITCODE -ne 0) { throw "xelab failed with exit code $LASTEXITCODE" }

    & (Join-Path $vivadoBin 'xsim.bat') tb_sat_gain_sim -runall 2>&1 |
        Tee-Object -FilePath (Join-Path $logDir 'xsim.log')
    if ($LASTEXITCODE -ne 0) { throw "xsim failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

