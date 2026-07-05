<#
Production-style GO/NO-GO wrapper for model benchmarks.

Usage:
  powershell -ExecutionPolicy Bypass -File .\training\benchmark\release_gate.ps1
  powershell -ExecutionPolicy Bypass -File .\training\benchmark\release_gate.ps1 -RunDir "C:\Users\Taha\Desktop\akyuz_benchmark_20260425_111222"
#>

param(
  [string]$RunDir = "",
  [string]$JsonOut = "",
  [double]$MinPassRate = 90,
  [int]$MaxEmptyOutputs = 0,
  [int]$MaxP90WallMs = 15000,
  [int]$MaxTotalErrors = 2
)

$ErrorActionPreference = "Stop"

if (-not $RunDir) {
  $desktop = [Environment]::GetFolderPath("Desktop")
  $latest = Get-ChildItem -LiteralPath $desktop -Directory -Filter "akyuz_benchmark_*" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $latest) {
    throw "Desktop altında 'akyuz_benchmark_*' klasoru bulunamadi. -RunDir verin."
  }
  $RunDir = $latest.FullName
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$py = Join-Path $scriptDir "release_gate.py"
if (-not (Test-Path -LiteralPath $py)) {
  throw "release_gate.py bulunamadi: $py"
}

$pyArgs = @(
  $py,
  "--run-dir", $RunDir,
  "--min-pass-rate", $MinPassRate,
  "--max-empty-outputs", $MaxEmptyOutputs,
  "--max-p90-wall-ms", $MaxP90WallMs,
  "--max-total-errors", $MaxTotalErrors
)
if ($JsonOut) {
  $pyArgs += @("--json-out", $JsonOut)
}

Write-Host ("Release gate run dir: {0}" -f $RunDir)
python @pyArgs
exit $LASTEXITCODE
