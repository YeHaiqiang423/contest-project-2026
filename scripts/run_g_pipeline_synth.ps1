$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$vivado = 'D:\XUni\Vivado\2020.2\bin\vivado.bat'
$logDir = Join-Path $projectRoot 'logs'
$tcl = Join-Path $PSScriptRoot 'synth_g_pipeline.tcl'
$timingReport = Join-Path $projectRoot 'results/synth_g_pipeline/timing_summary.rpt'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

Push-Location $projectRoot
try {
    & $vivado -mode batch -nolog -nojournal -source $tcl 2>&1 |
        Tee-Object -FilePath (Join-Path $logDir 'synth_g_pipeline.log')
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado synthesis failed with exit code $LASTEXITCODE"
    }
    if (-not (Test-Path -LiteralPath $timingReport)) {
        throw "Timing report missing: $timingReport"
    }
    if (-not (Select-String -LiteralPath $timingReport `
            -Pattern 'All user specified timing constraints are met\.' -Quiet)) {
        throw "200 MHz timing check failed; inspect $timingReport"
    }
}
finally {
    Pop-Location
}
