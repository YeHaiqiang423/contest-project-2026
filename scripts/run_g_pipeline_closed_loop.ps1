$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$matlab = 'G:\Matlab\bin\matlab.exe'

Push-Location $projectRoot
try {
    & $matlab -batch "cd('$($projectRoot.Replace("'", "''"))'); addpath('matlab/model'); generate_g_pipeline_vectors"
    if ($LASTEXITCODE -ne 0) {
        throw "Pipeline vector generation failed with exit code $LASTEXITCODE"
    }

    & powershell -ExecutionPolicy Bypass -File scripts/run_g_pipeline_xsim.ps1
    if ($LASTEXITCODE -ne 0) {
        throw "Pipeline XSim self-check failed with exit code $LASTEXITCODE"
    }

    & powershell -ExecutionPolicy Bypass -File scripts/run_g_pipeline_synth.ps1
    if ($LASTEXITCODE -ne 0) {
        throw "Pipeline synthesis/timing check failed with exit code $LASTEXITCODE"
    }

    Write-Host 'PASS: MATLAB vectors, bit-true XSim, and 200 MHz synthesis timing all passed.'
}
finally {
    Pop-Location
}
