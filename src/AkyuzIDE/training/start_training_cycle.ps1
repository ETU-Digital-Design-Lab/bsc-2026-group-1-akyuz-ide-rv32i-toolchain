<#
Start a new model training cycle for AkyuzIDE.

What this does:
1) (optional) regenerate synthetic batch
2) validate train/eval/generated
3) build deduped train.full.jsonl
4) validate train.full.jsonl
5) print next-step commands for local LoRA and cloud-model benchmark

Usage:
  powershell -ExecutionPolicy Bypass -File .\training\start_training_cycle.ps1
  powershell -ExecutionPolicy Bypass -File .\training\start_training_cycle.ps1 -RegenerateBatch
#>

param(
  [switch]$RegenerateBatch
)

$ErrorActionPreference = "Stop"

$datasetDir = Join-Path $PSScriptRoot "riscv_agent_dataset"

$seed = Join-Path $datasetDir "train.seed.jsonl"
$eval = Join-Path $datasetDir "eval.seed.jsonl"
$generated = Join-Path $datasetDir "generated.batch1.jsonl"
$full = Join-Path $datasetDir "train.full.jsonl"

if ($RegenerateBatch) {
  Write-Host "Generating new batch..."
  python (Join-Path $datasetDir "generate_batch.py")
}

Write-Host "Validating seed/eval/generated..."
python (Join-Path $datasetDir "validate_dataset.py") $seed
python (Join-Path $datasetDir "validate_dataset.py") $eval
python (Join-Path $datasetDir "validate_dataset.py") $generated

Write-Host "Building merged train.full.jsonl..."
python (Join-Path $datasetDir "build_train_full.py") `
  --seed $seed `
  --generated $generated `
  --out $full

Write-Host "Validating merged dataset..."
python (Join-Path $datasetDir "validate_dataset.py") $full

Write-Host ""
Write-Host "=== NEXT: Local LoRA training (example) ==="
Write-Host "python -m pip install -U transformers datasets peft trl accelerate bitsandbytes"
Write-Host "# then run your trainer with dataset: $full"

Write-Host ""
Write-Host "=== NEXT: Benchmark + GO/NO-GO ==="
Write-Host "powershell -ExecutionPolicy Bypass -File .\training\benchmark\benchmark_run.ps1"
Write-Host "powershell -ExecutionPolicy Bypass -File .\training\benchmark\release_gate.ps1"

Write-Host ""
Write-Host "=== NEXT: Remote local model (Tailscale/ngrok tunnel) ==="
Write-Host '$env:REMOTE_AI_HOST="http://127.0.0.1:11434"   # local'
Write-Host '# or: $env:REMOTE_AI_HOST="http://100.x.y.z:11434"  # tailscale desktop ollama'
