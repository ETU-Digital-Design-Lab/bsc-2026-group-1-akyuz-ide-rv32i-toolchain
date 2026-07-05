"""
AkyuzIDE Model Birleştirme ve Ollama Export
============================================
LoRA adapter'ı base model ile birleştirir, GGUF'a dönüştürür ve Ollama'ya kaydeder.

Gereksinimler:
  - llama.cpp kurulu olmalı veya pip ile llama-cpp-python

Kullanım:
  python merge_export.py --checkpoint checkpoints/qwen25-coder-14b-akyuz/best --model qwen
  python merge_export.py --checkpoint checkpoints/deepseek-coder-v2-lite-akyuz/best --model deepseek
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent

OLLAMA_NAMES = {
    "qwen":     "akyuz-qwen25-coder:14b",
    "deepseek": "akyuz-deepseek-coder:16b",
}

HF_IDS = {
    "qwen":     "Qwen/Qwen2.5-Coder-14B-Instruct",
    "deepseek": "deepseek-ai/DeepSeek-Coder-V2-Lite-Instruct",
}

SYSTEM_PROMPT = {
    "qwen": (
        "Sen AkyuzIDE'nin uzman EDA asistanısın. RISC-V, FPGA ve Verilog konusunda "
        "uzmanlaşmış, synthesizable RTL kodu yazan ve hata ayıklayan bir yapay zekasın."
    ),
    "deepseek": (
        "You are AkyuzIDE's expert EDA assistant, specialized in RISC-V, FPGA, "
        "and Verilog design. You write synthesizable RTL code and debug hardware designs."
    ),
}


def merge_lora(checkpoint: Path, model_key: str, merged_dir: Path) -> None:
    print(f"[1/3] LoRA birleştiriliyor → {merged_dir}")
    merged_dir.mkdir(parents=True, exist_ok=True)

    merge_script = f"""
import torch
from peft import AutoPeftModelForCausalLM
from transformers import AutoTokenizer

print("Model yükleniyor (CPU, bfloat16)...")
model = AutoPeftModelForCausalLM.from_pretrained(
    "{checkpoint}",
    torch_dtype=torch.bfloat16,
    device_map="cpu",
    trust_remote_code=True,
    low_cpu_mem_usage=True,
)
print("LoRA birleştiriliyor...")
merged = model.merge_and_unload()
print("Model kaydediliyor...")
merged.save_pretrained("{merged_dir}", safe_serialization=True, max_shard_size="4GB")

tokenizer = AutoTokenizer.from_pretrained("{checkpoint}", trust_remote_code=True)
tokenizer.save_pretrained("{merged_dir}")
print("Birleştirme tamamlandı.")
"""
    result = subprocess.run([sys.executable, "-c", merge_script], check=True)


def convert_gguf(merged_dir: Path, gguf_path: Path, quantization: str = "Q4_K_M") -> None:
    print(f"[2/3] GGUF dönüşümü ({quantization}) → {gguf_path}")
    gguf_path.parent.mkdir(parents=True, exist_ok=True)

    # llama.cpp'nin convert scriptini ara
    convert_candidates = [
        Path("/usr/local/bin/convert_hf_to_gguf.py"),
        Path.home() / "llama.cpp" / "convert_hf_to_gguf.py",
        Path.home() / "llama.cpp" / "convert-hf-to-gguf.py",
    ]
    convert_script = next((p for p in convert_candidates if p.exists()), None)

    if convert_script is None:
        print("  UYARI: llama.cpp convert scripti bulunamadı.")
        print("  Manuel adım:")
        print(f"    cd ~/llama.cpp")
        print(f"    python convert_hf_to_gguf.py {merged_dir} --outfile {gguf_path} --outtype f16")
        print(f"    ./llama-quantize {gguf_path} {gguf_path.with_suffix('')}_{quantization}.gguf {quantization}")
        return

    fp16_path = gguf_path.with_name(gguf_path.stem + "_f16.gguf")
    subprocess.run([
        sys.executable, str(convert_script),
        str(merged_dir),
        "--outfile", str(fp16_path),
        "--outtype", "f16",
    ], check=True)

    # Quantize
    quantize_bin = convert_script.parent / "llama-quantize"
    if quantize_bin.exists():
        subprocess.run([
            str(quantize_bin), str(fp16_path), str(gguf_path), quantization
        ], check=True)
        fp16_path.unlink(missing_ok=True)
        print(f"  {quantization} quantize tamamlandı.")
    else:
        print(f"  llama-quantize bulunamadı, f16 GGUF kullanılıyor: {fp16_path}")


def create_ollama_modelfile(gguf_path: Path, model_key: str, modelfile_path: Path) -> None:
    system = SYSTEM_PROMPT[model_key]
    ollama_name = OLLAMA_NAMES[model_key]

    content = f"""FROM {gguf_path}

SYSTEM \"\"\"{system}\"\"\"

PARAMETER temperature 0.1
PARAMETER top_p 0.9
PARAMETER top_k 40
PARAMETER repeat_penalty 1.1
PARAMETER num_ctx 4096
PARAMETER stop "<|im_end|>"
PARAMETER stop "<|im_start|>"
"""
    modelfile_path.write_text(content, encoding="utf-8")
    print(f"  Modelfile yazıldı: {modelfile_path}")


def register_ollama(modelfile_path: Path, ollama_name: str) -> None:
    print(f"[3/3] Ollama'ya kaydediliyor: {ollama_name}")
    result = subprocess.run(
        ["ollama", "create", ollama_name, "-f", str(modelfile_path)],
        capture_output=False,
    )
    if result.returncode == 0:
        print(f"  ✓ Ollama modeli hazır: ollama run {ollama_name}")
    else:
        print(f"  ✗ Ollama kayıt başarısız. Manuel çalıştır:")
        print(f"    ollama create {ollama_name} -f {modelfile_path}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", required=True, help="best/ checkpoint dizini")
    ap.add_argument("--model",      choices=["qwen", "deepseek"], required=True)
    ap.add_argument("--quant",      default="Q4_K_M",
                    help="GGUF quantization (Q4_K_M, Q5_K_M, Q8_0 — default: Q4_K_M)")
    ap.add_argument("--skip-gguf",  action="store_true",
                    help="GGUF dönüşümünü atla, sadece birleştir")
    ap.add_argument("--skip-ollama", action="store_true",
                    help="Ollama kaydını atla")
    args = ap.parse_args()

    checkpoint   = Path(args.checkpoint).resolve()
    model_name   = OLLAMA_NAMES[args.model].replace(":", "-").replace("/", "_")
    merged_dir   = SCRIPT_DIR / "checkpoints" / f"{model_name}_merged"
    gguf_path    = SCRIPT_DIR / "checkpoints" / "gguf" / f"{model_name}_{args.quant}.gguf"
    modelfile    = SCRIPT_DIR / "checkpoints" / "gguf" / f"{model_name}.Modelfile"

    print(f"\nAkyuzIDE Model Export")
    print(f"  Checkpoint  : {checkpoint}")
    print(f"  Model       : {HF_IDS[args.model]}")
    print(f"  Ollama adı  : {OLLAMA_NAMES[args.model]}")
    print(f"  Quantization: {args.quant}\n")

    merge_lora(checkpoint, args.model, merged_dir)

    if not args.skip_gguf:
        convert_gguf(merged_dir, gguf_path, args.quant)
    else:
        gguf_path = merged_dir  # Ollama direkt HF formatından da yükleyebilir

    create_ollama_modelfile(gguf_path, args.model, modelfile)

    if not args.skip_ollama:
        register_ollama(modelfile, OLLAMA_NAMES[args.model])

    print("\nTamamlandı.")
    print(f"  AkyuzIDE engine.py'de COMPLEX_MODEL = '{OLLAMA_NAMES[args.model]}' yapabilirsin.")


if __name__ == "__main__":
    main()
