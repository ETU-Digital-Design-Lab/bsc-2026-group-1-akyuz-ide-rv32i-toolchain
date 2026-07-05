<# 
AkyuzIDE benchmark analyzer wrapper.

Examples:
  powershell -ExecutionPolicy Bypass -File .\training\benchmark\analyze_results.ps1
  powershell -ExecutionPolicy Bypass -File .\training\benchmark\analyze_results.ps1 -RunDir "C:\Users\Taha\Desktop\akyuz_benchmark_20260425_111222" -JsonOut report.json
#>

param(
  [string]$RunDir = "",
  [string]$JsonOut = ""
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
$py = Join-Path $scriptDir "analyze_results.py"
if (-not (Test-Path -LiteralPath $py)) {
  throw "Python analyzer bulunamadi: $py"
}

$args = @($py, "--run-dir", $RunDir)
if ($JsonOut) {
  $args += @("--json-out", $JsonOut)
}

Write-Host ("Analyze run dir: {0}" -f $RunDir)
python @args
