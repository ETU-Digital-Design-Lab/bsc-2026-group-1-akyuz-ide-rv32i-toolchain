# Ollama model deposunu D: yedegine yonlendirir (kalici: User ortam degiskeni).
# Ollama masaustu uygulamasini tamamen kapatip yeniden acin; sonra: ollama list

$ErrorActionPreference = 'Stop'
$path = 'D:\Masaustu_Yedekler\OllamaModels'

if (-not (Test-Path -LiteralPath $path)) {
    Write-Error "Klasor bulunamadi: $path"
    exit 1
}
foreach ($sub in 'blobs', 'manifests') {
    $p = Join-Path $path $sub
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Error "Eksik alt klasor: $p"
        exit 1
    }
}

[System.Environment]::SetEnvironmentVariable('OLLAMA_MODELS', $path, 'User')
Write-Host "Tamam: OLLAMA_MODELS (User) = $path"
Write-Host "Simdi: Ollama'yi tamamen kapat (sistem tepsisi dahil), yeniden baslat."
Write-Host "Yeni bir terminalde: ollama list"
