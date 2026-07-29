$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$matlab = 'G:\Matlab\bin\matlab.exe'
$logDir = Join-Path $projectRoot 'logs'
$logFile = Join-Path $logDir 'g_model_regression.log'

if (-not (Test-Path -LiteralPath $matlab)) {
    throw "MATLAB executable not found: $matlab"
}
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$escapedRoot = $projectRoot.Replace("'", "''")
$batchCommand = "cd('$escapedRoot'); addpath('matlab/model'); run_g_model_regression"
& $matlab -logfile $logFile -batch $batchCommand
if ($LASTEXITCODE -ne 0) {
    throw "MATLAB regression failed. See $logFile"
}
Write-Host "MATLAB regression passed. Log: $logFile"
