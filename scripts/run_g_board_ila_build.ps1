$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$vivado = 'D:\XUni\Vivado\2020.2\bin\vivado.bat'
$logDir = Join-Path $projectRoot 'logs'
$outputDir = Join-Path $projectRoot 'results\board_ila'
$buildLog = Join-Path $logDir 'build_g_board_ila.log'
$tcl = Join-Path $PSScriptRoot 'build_g_board_ila.tcl'

New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Push-Location $projectRoot
try {
    & $vivado -mode batch -nolog -nojournal -source $tcl 2>&1 |
        Tee-Object -FilePath $buildLog
    if ($LASTEXITCODE -ne 0) {
        throw "Board ILA build failed with exit code $LASTEXITCODE"
    }
    if (-not (Select-String -LiteralPath $buildLog `
            -Pattern '^BOARD_ILA_BUILD_PASS:' -Quiet)) {
        throw "Board ILA success marker missing from $buildLog"
    }
    foreach ($name in @('g_board_ila.bit', 'g_board_ila.ltx', 'build_manifest.txt')) {
        $path = Join-Path $outputDir $name
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Expected board ILA artifact missing: $path"
        }
    }
}
finally {
    Pop-Location
}
