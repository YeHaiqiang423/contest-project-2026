$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$vivado = 'D:\XUni\Vivado\2020.2\bin\vivado.bat'
$logDir = Join-Path $projectRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
foreach ($top in @('tb_g_time_domain_display', 'tb_g_spectrum_display')) {
    & $vivado -mode batch -source scripts/sim_g_display_builders.tcl `
        -tclargs $top -log "logs/xsim_$top.log" -journal "logs/xsim_$top.jou"
    if ($LASTEXITCODE -ne 0) { throw "$top XSim failed with exit code $LASTEXITCODE" }
}

