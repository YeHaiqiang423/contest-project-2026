$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$matlab = 'G:\Matlab\bin\matlab.exe'

if (-not (Test-Path -LiteralPath $matlab)) {
    throw "MATLAB not found: $matlab"
}

& $matlab -batch "cd('$($projectRoot.Replace("'", "''"))'); addpath('matlab/model'); generate_sat_gain_vectors; generate_adc_frontend_vectors; generate_g_fir_vectors; generate_g_frame_vectors; generate_g_hann_vectors; generate_g_pipeline_vectors; generate_g_fft_spectrum_vectors"
if ($LASTEXITCODE -ne 0) {
    throw "MATLAB vector generation failed with exit code $LASTEXITCODE"
}
