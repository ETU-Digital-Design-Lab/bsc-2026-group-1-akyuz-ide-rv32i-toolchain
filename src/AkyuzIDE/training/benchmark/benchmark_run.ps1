<# 
AkyuzIDE - Ollama coklu model benchmark (PowerShell 5+)

Felsefe (dürüst değerlendirme):
- Bu script "dostça yorum" yapmaz. Olçtügü sey: süre, token sayilari, temel sinyal bayraklari.
- Kötü sonuc "kötü" diye isaretlenir. Model egitiminde ilerleme, kolaycilikla yanılsama degil, olculebilen iyilesmedir.
- Ciktilari kaydeder; puan/insan degerlendirmesini sizin rubricinizle yapin.

Girdi:
- prompts.txt (varsayilan ayni klasörde) format:
  - Her prompt bir BLOK
  - Bloklar arasina ayirici: satir: ---

Kullanim:
  powershell -ExecutionPolicy Bypass -File .\training\benchmark\benchmark_run.ps1
  $env:OLLAMA_BASE="http://100.x.x.x:11434"
  powershell -ExecutionPolicy Bypass -File .\training\benchmark\benchmark_run.ps1 -OllamaBase $env:OLLAMA_BASE
#>

param(
  [string]$OllamaBase = ($env:OLLAMA_BASE, "http://127.0.0.1:11434" | Where-Object { $_ } | Select-Object -First 1),
  [string[]]$Models = @(
    "qwen2.5-coder:14b",
    "risc-v-verilog-v2:latest",
    "risc-v-verilog-v2-agent:latest"
  ),
  [string]$PromptFile = (Join-Path $PSScriptRoot "prompts.txt"),
  [string]$OutDir = (Join-Path $env:USERPROFILE ("Desktop\\akyuz_benchmark_{0:yyyyMMdd_HHmmss}" -f (Get-Date))),
  [switch]$SkipReleaseGate,
  [double]$GateMinPassRate = 90,
  [int]$GateMaxEmptyOutputs = 0,
  [int]$GateMaxP90WallMs = 15000,
  [int]$GateMaxTotalErrors = 2
)

$ErrorActionPreference = "Stop"

function Sanitize-Name([string]$s) {
  if (-not $s) { return "model" }
  return ($s -replace "[\\/:*?`"<>|]+", "_")
}

function Split-PromptsFromFile([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Prompt file not found: $path" }
  $raw = Get-Content -LiteralPath $path -Raw
  if (-not $raw) { throw "Prompt file is empty: $path" }
  $parts = $raw -split "^\s*---\s*$", 0, "Multiline" |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and $_.Length -gt 0 }
  if ($parts.Count -lt 1) { throw "No prompt blocks found. Use '---' separators in prompts.txt" }
  return $parts
}

function NsToMs([Nullable[int64]]$ns) {
  if ($null -eq $ns) { return $null }
  return [int64]([double]$ns / 1e6)
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$logCsv = Join-Path $OutDir "summary.csv"
$rows = @()

# Preflight: Ollama erisilebilir mi? (Sadece hızlı sinyal)
try {
  $root = $OllamaBase.TrimEnd("/")
  Invoke-RestMethod -Method Get -Uri ("{0}/api/tags" -f $root) -TimeoutSec 10 | Out-Null
} catch {
  throw ("Ollama'ya erisilemedi: {0}. -OllamaBase dogru mu? Ornek: http://127.0.0.1:11434 veya Tailscale IP." -f $OllamaBase)
}

$prompts = Split-PromptsFromFile $PromptFile
$pidx = 0

foreach ($p in $prompts) {
  $pidx += 1
  foreach ($m in $Models) {
    $safeM = Sanitize-Name $m
    $bodyObj = @{
      model    = $m
      stream   = $false
      messages = @(@{ role = "user"; content = $p })
      # Tekrarlanabilir kıyas için düşük sıcaklık (kıyaslanabilirlik, "yaratıcılık" değil)
      options  = @{
        temperature = 0.0
        top_p       = 0.9
      }
    }
    $body = $bodyObj | ConvertTo-Json -Depth 8

    $t0 = Get-Date
    $ok = $true
    $err = $null
    $r = $null
    try {
      $r = Invoke-RestMethod -Method Post -Uri ("{0}/api/chat" -f $OllamaBase.TrimEnd("/")) `
        -ContentType "application/json" -Body $body -TimeoutSec 600
    } catch {
      $ok = $false
      $err = $_.Exception.Message
    }
    $dt = (Get-Date) - $t0

    $content = $null
    if ($ok -and $r -and $r.message) { $content = [string]$r.message.content } else { $content = "" }

    $outPath = Join-Path $OutDir ("P{0:00}__{1}.txt" -f $pidx, $safeM)
    $header = @(
      "PROMPT_INDEX=$pidx"
      "MODEL=$m"
      "OLLAMA_BASE=$OllamaBase"
      "WALL_MS=$([int64]$dt.TotalMilliseconds)"
    ) -join [Environment]::NewLine

    if (-not $ok) {
      @($header, "", "ERROR:", $err) -join [Environment]::NewLine | Set-Content -Encoding utf8 $outPath
    } else {
      @($header, "", $content) -join [Environment]::NewLine | Set-Content -Encoding utf8 $outPath
    }

    $hasTool = if ($content -match "<tool_call>") { $true } else { $false }
    $empty = if ([string]::IsNullOrWhiteSpace($content)) { $true } else { $false }

    $rows += [pscustomobject]@{
      prompt_index          = $pidx
      model                 = $m
      wall_ms               = [int64]$dt.TotalMilliseconds
      ollama_total_ms       = (NsToMs $r.total_duration)
      ollama_load_ms        = (NsToMs $r.load_duration)
      ollama_prompt_eval_ms = (NsToMs $r.prompt_eval_duration)
      ollama_eval_ms         = (NsToMs $r.eval_duration)
      out_chars              = $content.Length
      eval_count             = $r.eval_count
      prompt_eval_count      = $r.prompt_eval_count
      has_tool_call_tag      = $hasTool
      empty_output           = $empty
      ok                     = $ok
      error                  = $err
      output_file            = $outPath
    }
  }
}

$rows | Export-Csv -Path $logCsv -NoTypeInformation -Encoding UTF8
Write-Host ("Bitti. Ciktilar: {0}" -f $OutDir)
Write-Host ("CSV: {0}" -f $logCsv)
$rows | Sort-Object prompt_index, model | Format-Table -Auto

if (-not $SkipReleaseGate) {
  $gatePy = Join-Path $PSScriptRoot "release_gate.py"
  if (-not (Test-Path -LiteralPath $gatePy)) {
    Write-Warning ("Release gate atlandi. Dosya bulunamadi: {0}" -f $gatePy)
    return
  }

  $gateJson = Join-Path $OutDir "release_gate.json"
  $gateArgs = @(
    $gatePy,
    "--run-dir", $OutDir,
    "--json-out", $gateJson,
    "--min-pass-rate", $GateMinPassRate,
    "--max-empty-outputs", $GateMaxEmptyOutputs,
    "--max-p90-wall-ms", $GateMaxP90WallMs,
    "--max-total-errors", $GateMaxTotalErrors
  )

  Write-Host ""
  Write-Host "=== Release Gate ==="
  python @gateArgs
  $gateCode = $LASTEXITCODE
  if ($gateCode -eq 0) {
    Write-Host ("Release gate: GO (json: {0})" -f $gateJson)
  } else {
    Write-Warning ("Release gate: NO-GO (exit={0}, json: {1})" -f $gateCode, $gateJson)
  }
}
