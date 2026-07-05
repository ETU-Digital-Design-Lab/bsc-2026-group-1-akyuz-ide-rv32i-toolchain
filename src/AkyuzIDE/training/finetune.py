"""
AkyuzIDE QLoRA Fine-Tuner
==========================
Qwen2.5-Coder-14B-Instruct veya DeepSeek-Coder-V2-Lite-Instruct modellerini
Vivado doğrulamalı Verilog veriseti üzerinde ince ayar yapar.

Kullanım:
  # Qwen2.5-Coder-14B
  python finetune.py --model qwen

  # DeepSeek-Coder-V2-Lite
  python finetune.py --model deepseek

  # Tüm seçenekler
  python finetune.py --model qwen --epochs 3 --rank 32 --batch-size 1 --grad-accum 8
"""
from __future__ import annotations

import argparse
import os
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

# ── Model Konfigürasyonları ────────────────────────────────────────────────────

@dataclass
class ModelConfig:
    hf_id:          str
    lora_targets:   list[str]
    lora_r:         int
    lora_alpha:     int
    max_seq_len:    int  # Bellek kısıtı için 1024'e düşürüldü (14B + 16GB VRAM)
    chat_template:  str   # "chatml" | "deepseek"
    output_dir:     str

MODELS: dict[str, ModelConfig] = {
    "qwen": ModelConfig(
        hf_id         = "Qwen/Qwen2.5-Coder-14B-Instruct",
        lora_targets  = ["q_proj", "k_proj", "v_proj", "o_proj",
                         "gate_proj", "up_proj", "down_proj"],
        lora_r        = 32,
        lora_alpha    = 64,
        max_seq_len   = 1024,
        chat_template = "chatml",
        output_dir    = "checkpoints/qwen25-coder-14b-akyuz",
    ),
    "deepseek": ModelConfig(
        hf_id         = "deepseek-ai/DeepSeek-Coder-V2-Lite-Instruct",
        # MoE mimarisi — sadece attention katmanlarına LoRA uygula
        lora_targets  = ["q_proj", "k_proj", "v_proj", "o_proj"],
        lora_r        = 16,
        lora_alpha    = 32,
        max_seq_len   = 1024,
        chat_template = "deepseek",
        output_dir    = "checkpoints/deepseek-coder-v2-lite-akyuz",
    ),
}

# ── Dizin yolları ──────────────────────────────────────────────────────────────
SCRIPT_DIR  = Path(__file__).parent
DATA_DIR    = SCRIPT_DIR.parent / "server" / "train_data"
TRAIN_FILE  = DATA_DIR / "final_train.jsonl"
EVAL_FILE   = DATA_DIR / "final_eval.jsonl"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--model",      choices=["qwen", "deepseek"], required=True)
    p.add_argument("--epochs",     type=int,   default=2)
    p.add_argument("--rank",       type=int,   default=0,
                   help="LoRA rank override (0 = model default)")
    p.add_argument("--batch-size", type=int,   default=1)
    p.add_argument("--grad-accum", type=int,   default=8)
    p.add_argument("--lr",         type=float, default=2e-4)
    p.add_argument("--warmup",     type=int,   default=50)
    p.add_argument("--output",     type=str,   default="",
                   help="Çıktı dizini override (boş = model default)")
    p.add_argument("--resume",     type=str,   default="",
                   help="Checkpoint dizininden devam et")
    return p.parse_args()


def build_trainer(args: argparse.Namespace):
    import torch
    from datasets import load_dataset
    from peft import LoraConfig, TaskType, get_peft_model
    from transformers import (AutoModelForCausalLM, AutoTokenizer,
                               BitsAndBytesConfig)
    from trl import SFTTrainer, SFTConfig

    cfg = MODELS[args.model]
    if args.rank > 0:
        cfg.lora_r     = args.rank
        cfg.lora_alpha = args.rank * 2
    output_dir = Path(args.output) if args.output else SCRIPT_DIR / cfg.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"\n{'='*55}")
    print(f" Model     : {cfg.hf_id}")
    print(f" LoRA r={cfg.lora_r}, alpha={cfg.lora_alpha}")
    print(f" Targets   : {cfg.lora_targets}")
    print(f" Eğitim    : {TRAIN_FILE}  ({sum(1 for _ in open(TRAIN_FILE))} satır)")
    print(f" Eval      : {EVAL_FILE}  ({sum(1 for _ in open(EVAL_FILE))} satır)")
    print(f" Çıktı     : {output_dir}")
    print(f"{'='*55}\n")

    # ── 4-bit quantization ────────────────────────────────────
    bnb_config = BitsAndBytesConfig(
        load_in_4bit               = True,
        bnb_4bit_quant_type        = "nf4",
        bnb_4bit_compute_dtype     = torch.bfloat16,
        bnb_4bit_use_double_quant  = True,
    )

    # ── Tokenizer ─────────────────────────────────────────────
    print("Tokenizer yükleniyor...")
    tokenizer = AutoTokenizer.from_pretrained(
        cfg.hf_id,
        trust_remote_code = True,
        padding_side      = "right",
    )
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    # ── Model ─────────────────────────────────────────────────
    print("Model yükleniyor (4-bit)...")
    model = AutoModelForCausalLM.from_pretrained(
        cfg.hf_id,
        quantization_config = bnb_config,
        device_map          = "auto",
        trust_remote_code   = True,
        dtype               = torch.bfloat16,
        attn_implementation = "flash_attention_2" if _flash_attn_available() else "eager",
    )
    # PEFT 0.14+ önerilen yöntem — float32 cast yapmaz, bellek tasarrufu sağlar
    model.config.use_cache = False
    model.gradient_checkpointing_enable(
        gradient_checkpointing_kwargs={"use_reentrant": False}
    )
    model.enable_input_require_grads()

    # ── LoRA ──────────────────────────────────────────────────
    lora_config = LoraConfig(
        task_type       = TaskType.CAUSAL_LM,
        r               = cfg.lora_r,
        lora_alpha      = cfg.lora_alpha,
        lora_dropout    = 0.05,
        target_modules  = cfg.lora_targets,
        bias            = "none",
    )
    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()

    # ── Dataset ───────────────────────────────────────────────
    print("Veri seti yükleniyor...")
    dataset = load_dataset("json", data_files={
        "train": str(TRAIN_FILE),
        "eval":  str(EVAL_FILE),
    })

    # ── SFTConfig (TRL 1.x: TrainingArguments + SFT parametreleri bir arada) ──
    run_name = f"{args.model}_{datetime.now().strftime('%m%d_%H%M')}"
    sft_config = SFTConfig(
        output_dir                  = str(output_dir),
        num_train_epochs            = args.epochs,
        per_device_train_batch_size = args.batch_size,
        per_device_eval_batch_size  = args.batch_size,
        gradient_accumulation_steps = args.grad_accum,
        gradient_checkpointing      = True,
        optim                       = "paged_adamw_8bit",
        learning_rate               = args.lr,
        lr_scheduler_type           = "cosine",
        warmup_steps                = args.warmup,
        fp16                        = False,
        bf16                        = True,
        logging_steps               = 20,
        eval_strategy               = "steps",
        eval_steps                  = 200,
        save_strategy               = "steps",
        save_steps                  = 200,
        save_total_limit            = 3,
        load_best_model_at_end      = True,
        metric_for_best_model       = "eval_loss",
        report_to                   = "tensorboard",
        run_name                    = run_name,
        dataloader_num_workers      = 2,
        dataset_text_field          = "text",
        max_length                  = cfg.max_seq_len,
        packing                     = False,
    )

    # ── SFTTrainer ────────────────────────────────────────────
    trainer = SFTTrainer(
        model            = model,
        processing_class = tokenizer,
        train_dataset    = dataset["train"],
        eval_dataset     = dataset["eval"],
        args             = sft_config,
    )
    return trainer, output_dir


def _flash_attn_available() -> bool:
    try:
        import flash_attn  # noqa: F401
        return True
    except ImportError:
        return False


def main():
    args = parse_args()

    import torch
    if not torch.cuda.is_available():
        print("HATA: CUDA bulunamadı. GPU gerekli.")
        raise SystemExit(1)

    vram = torch.cuda.get_device_properties(0).total_memory / 1024**3
    print(f"GPU: {torch.cuda.get_device_name(0)} ({vram:.1f} GB)")

    if vram < 14:
        print(f"UYARI: {vram:.1f} GB VRAM — 14B model için en az 14 GB öneriliyor.")

    trainer, output_dir = build_trainer(args)

    print("\nEğitim başlıyor...")
    trainer.train(resume_from_checkpoint=args.resume or None)

    print("\nEn iyi model kaydediliyor...")
    trainer.save_model(str(output_dir / "best"))
    trainer.tokenizer.save_pretrained(str(output_dir / "best"))

    print(f"\nTamamlandı → {output_dir / 'best'}")
    print("Sonraki adım: python merge_export.py --checkpoint <dizin> --model <qwen|deepseek>")


if __name__ == "__main__":
    main()
