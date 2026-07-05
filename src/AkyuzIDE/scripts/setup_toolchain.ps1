# setup_toolchain.ps1 - AkyuzIDE Toolchain Downloader
# ===================================================
# This script downloads a portable RISC-V GCC toolchain for offline bundling.

$ToolchainDir = Join-Path $PSScriptRoot "..\toolchain"
$RiscvDir = Join-Path $ToolchainDir "riscv"
$ZipFile = Join-Path $ToolchainDir "riscv-gcc.zip"

# Stable xPack RISC-V GCC 14.2.0-1 for Windows x64
$DownloadUrl = "https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v14.2.0-1/xpack-riscv-none-elf-gcc-14.2.0-1-win32-x64.zip"

if (-not (Test-Path $ToolchainDir)) {
    New-Item -ItemType Directory -Path $ToolchainDir
}

if (Test-Path $RiscvDir) {
    Write-Host "[AkyuzIDE] RISC-V Toolchain already exists at $RiscvDir. Skipping download." -ForegroundColor Green
    exit
}

Write-Host "[AkyuzIDE] Downloading xPack RISC-V GCC (Portable)..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipFile

Write-Host "[AkyuzIDE] Extracting toolchain (this may take a minute)..." -ForegroundColor Cyan
Expand-Archive -Path $ZipFile -DestinationPath $RiscvDir
Remove-Item $ZipFile

# Flatten the structure if needed (xPack zips often have a root folder)
$InnerFolder = Get-ChildItem -Path $RiscvDir -Directory | Select-Object -First 1
if ($InnerFolder) {
    Write-Host "[AkyuzIDE] Optimizing folder structure..." -ForegroundColor Gray
    Move-Item -Path "$($InnerFolder.FullName)\*" -Destination $RiscvDir
    Remove-Item $InnerFolder.FullName
}

Write-Host "[AkyuzIDE] SUCCESS! RISC-V Toolchain ready at $RiscvDir" -ForegroundColor Green
