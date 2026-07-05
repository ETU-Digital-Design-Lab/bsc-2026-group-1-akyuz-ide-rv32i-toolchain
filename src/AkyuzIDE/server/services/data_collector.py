"""
AkyuzIDE Autonomous Data Collector
====================================
Agent'ın başarılı kod üretimlerini ve hata düzeltmelerini
arka planda Alpaca formatında JSONL dosyalarına kaydeder.

Kalite seviyeleri:
  gold  (1.0) → Vivado sentezi başarılı  → gold.jsonl
  silver(0.9) → Simülasyon geçti        → silver.jsonl
  fix   (–)   → Hata → düzeltme çifti   → error_fixes.jsonl
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import threading
from datetime import datetime
from pathlib import Path

_LOCK = threading.Lock()

TRAIN_DIR = Path(os.getenv("AKYUZ_TRAIN_DIR",
                            Path.home() / ".config" / "akyuzide" / "train_data"))

_GOLD_FILE   = TRAIN_DIR / "gold.jsonl"
_SILVER_FILE = TRAIN_DIR / "silver.jsonl"
_FIX_FILE    = TRAIN_DIR / "error_fixes.jsonl"
_STATS_FILE  = TRAIN_DIR / "stats.json"

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _ensure_dir() -> None:
    TRAIN_DIR.mkdir(parents=True, exist_ok=True)


def _fingerprint(instruction: str, output: str) -> str:
    """Tekrar kaydı önlemek için SHA256 parmak izi."""
    raw = f"{instruction.strip()}|||{output.strip()}"
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


def _already_exists(target_file: Path, fp: str) -> bool:
    """Aynı parmak izi zaten dosyada var mı?"""
    if not target_file.exists():
        return False
    try:
        with open(target_file, "r", encoding="utf-8") as f:
            for line in f:
                try:
                    rec = json.loads(line)
                    if rec.get("metadata", {}).get("fingerprint") == fp:
                        return True
                except Exception:
                    continue
    except Exception:
        pass
    return False


def _sanitize_path(text: str) -> str:
    """Mutlak yolları göreli biçime çevir, kişisel bilgileri maskele."""
    # /home/kullanici/AkyuzIDE/server/workspace/proje/dosya.v → workspace/proje/dosya.v
    text = re.sub(r"/home/[^/]+/AkyuzIDE/server/", "", text)
    text = re.sub(r"C:\\\\[^\\\\]+\\\\AkyuzIDE\\\\server\\\\", "", text)
    return text


def _append(target_file: Path, record: dict) -> None:
    _ensure_dir()
    with _LOCK:
        with open(target_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
    _update_stats(target_file.stem)


def _update_stats(category: str) -> None:
    stats: dict = {}
    try:
        if _STATS_FILE.exists():
            stats = json.loads(_STATS_FILE.read_text(encoding="utf-8"))
    except Exception:
        pass
    stats[category] = stats.get(category, 0) + 1
    stats["last_updated"] = datetime.now().isoformat()
    try:
        _STATS_FILE.write_text(json.dumps(stats, indent=2, ensure_ascii=False), encoding="utf-8")
    except Exception:
        pass


def _extract_verilog(text: str) -> str:
    """Yanıt metninden Verilog kod bloğunu çıkar."""
    m = re.search(r"```(?:verilog|systemverilog)?\s*\n(.*?)```", text, re.DOTALL)
    if m:
        return m.group(1).strip()
    return text.strip()


def _count_lines(text: str) -> int:
    return len(text.strip().splitlines())


# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────────────────

def record_gold(
    instruction: str,
    output_code: str,
    board: str = "unknown",
    top_module: str = "",
    utilization: dict | None = None,
    timing: str = "N/A",
    model_name: str = "",
) -> bool:
    """
    Vivado sentezi başarılı → gold.jsonl'e ekle.
    Returns True if recorded, False if skipped (duplicate or too short).
    """
    instruction = instruction.strip()
    output_code = _sanitize_path(output_code.strip())

    if _count_lines(output_code) < 5:
        return False

    fp = _fingerprint(instruction, output_code)
    if _already_exists(_GOLD_FILE, fp):
        return False

    record = {
        "instruction": instruction,
        "input": "",
        "output": output_code,
        "metadata": {
            "quality": 1.0,
            "category": "gold",
            "board": board,
            "top_module": top_module,
            "synthesis_tool": "Vivado",
            "utilization": utilization or {},
            "timing": timing,
            "model": model_name,
            "timestamp": datetime.now().isoformat(),
            "fingerprint": fp,
        },
    }
    _append(_GOLD_FILE, record)
    return True


def record_silver(
    instruction: str,
    output_code: str,
    sim_output: str = "",
    board: str = "unknown",
    model_name: str = "",
) -> bool:
    """
    Simülasyon geçti → silver.jsonl'e ekle.
    Returns True if recorded.
    """
    instruction = instruction.strip()
    output_code = _sanitize_path(output_code.strip())

    if _count_lines(output_code) < 5:
        return False

    fp = _fingerprint(instruction, output_code)
    if _already_exists(_SILVER_FILE, fp):
        return False

    # Simülasyon çıktısından PASS/FAIL bilgisi
    sim_note = ""
    if sim_output:
        lines = sim_output.strip().splitlines()
        sim_note = "\n".join(lines[-10:])  # son 10 satır

    record = {
        "instruction": instruction,
        "input": "",
        "output": output_code,
        "metadata": {
            "quality": 0.9,
            "category": "silver",
            "board": board,
            "sim_summary": sim_note,
            "model": model_name,
            "timestamp": datetime.now().isoformat(),
            "fingerprint": fp,
        },
    }
    _append(_SILVER_FILE, record)
    return True


def record_error_fix(
    instruction: str,
    error_message: str,
    code_before: str,
    code_after: str,
    error_code: str = "",
    board: str = "unknown",
    model_name: str = "",
) -> bool:
    """
    Hata → düzeltme çifti → error_fixes.jsonl'e ekle.
    instruction: kullanıcının orijinal isteği
    error_message: Vivado/iverilog hata çıktısı
    code_before: hatalı kod
    code_after: düzeltilmiş kod
    error_code: örn. "8-2571"
    """
    instruction = instruction.strip()
    code_before = _sanitize_path(code_before.strip())
    code_after  = _sanitize_path(code_after.strip())
    error_message = _sanitize_path(error_message.strip())

    if _count_lines(code_after) < 5:
        return False
    if code_before == code_after:
        return False

    fp = _fingerprint(error_message[:200], code_after)
    if _already_exists(_FIX_FILE, fp):
        return False

    # Alpaca: instruction = ne yapılmak isteniyor + hata
    # input = hatalı kod, output = düzeltilmiş kod
    fix_instruction = (
        f"{instruction}\n\n"
        f"Aşağıdaki hata oluştu, düzelt:\n{error_message[:500]}"
    )

    record = {
        "instruction": fix_instruction,
        "input": code_before,
        "output": code_after,
        "metadata": {
            "quality": 0.95,
            "category": "error_fix",
            "error_code": error_code,
            "board": board,
            "synthesis_tool": "Vivado" if error_code else "iverilog",
            "model": model_name,
            "timestamp": datetime.now().isoformat(),
            "fingerprint": fp,
        },
    }
    _append(_FIX_FILE, record)
    return True


def get_stats() -> dict:
    """Toplanan veri istatistiklerini döndür."""
    _ensure_dir()
    stats: dict = {}
    try:
        if _STATS_FILE.exists():
            stats = json.loads(_STATS_FILE.read_text(encoding="utf-8"))
    except Exception:
        pass

    # Dosya satır sayıları
    for key, f in [("gold_lines", _GOLD_FILE), ("silver_lines", _SILVER_FILE), ("fix_lines", _FIX_FILE)]:
        try:
            stats[key] = sum(1 for _ in open(f, encoding="utf-8")) if f.exists() else 0
        except Exception:
            stats[key] = 0

    return stats


def get_stats_text() -> str:
    s = get_stats()
    return (
        f"AkyuzIDE Fine-Tune Dataset:\n"
        f"  Gold  (Vivado synth): {s.get('gold_lines', 0)} örnek\n"
        f"  Silver (simülasyon):  {s.get('silver_lines', 0)} örnek\n"
        f"  Error fixes:          {s.get('fix_lines', 0)} örnek\n"
        f"  Son güncelleme: {s.get('last_updated', 'henüz yok')}"
    )
