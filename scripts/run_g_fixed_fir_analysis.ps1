$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$matlab = 'G:\Matlab\bin\matlab.exe'
$logDir = Join-Path $projectRoot 'logs'
$logFile = Join-Path $logDir 'g_fixed_fir_analysis.log'

if (-not (Test-Path -LiteralPath $matlab)) {
    throw "MATLAB executable not found: $matlab"
}
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$escapedRoot = $projectRoot.Replace("'", "''")
$batchCommand = "cd('$escapedRoot'); addpath('matlab/model'); analyze_g_fixed_fir"
& $matlab -logfile $logFile -batch $batchCommand
if ($LASTEXITCODE -ne 0) {
    throw "Fixed FIR analysis failed. See $logFile"
}
Write-Host "Fixed FIR analysis passed. Log: $logFile"
