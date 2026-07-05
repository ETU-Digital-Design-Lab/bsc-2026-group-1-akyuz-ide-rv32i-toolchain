"""
AkyuzIDE Smart Router
=====================
Göreve göre doğru modeli seçer, günlük bütçeyi takip eder,
token israfını önler.
"""
from __future__ import annotations

import json
import os
import re
import asyncio
from datetime import date
from pathlib import Path
from typing import NamedTuple

# ─────────────────────────────────────────────────────────────────────────────
# Sabitler
# ─────────────────────────────────────────────────────────────────────────────

BUDGET_FILE = Path(os.getenv("AKYUZ_LOG_DIR",
                              Path.home() / ".config" / "akyuzide" / "logs")) / "budget.json"

# Günlük bütçe limiti (dolar) — .env ile override edilebilir
DAILY_BUDGET_USD = float(os.getenv("AKYUZ_DAILY_BUDGET", "1.50"))

# 1K token başına tahmini maliyet ($) — input+output ağırlıklı ortalama
COST_PER_1K: dict[str, float] = {
    "anthropic/claude-sonnet-4-6":   0.009,   # $3 in + $15 out, ~2K avg
    "anthropic/claude-haiku-4-5":    0.0008,
    "google/gemini-2.5-flash":       0.0015,  # $0.30 in + $2.50 out
    "google/gemini-2.5-pro":         0.006,
    "openai/gpt-4o-mini":            0.0004,
    "openai/o4-mini":                0.003,
    "deepseek/deepseek-chat":        0.0002,  # DeepSeek V3
    "deepseek/deepseek-r1":          0.0014,
    "qwen/qwen3-235b-a22b":          0.0005,
    # local — ücretsiz
    "akyuz-qwen25-coder:14b":        0.0,   # Fine-tuned model
    "qwen2.5-coder:14b":             0.0,
    "qwen3:14b":                     0.0,
    "qwen3:30b-a3b":                 0.0,
    "llama3.1:8b":                   0.0,
}

# En iyi yerel model (fine-tuned) — API key gerektirmez
FINE_TUNED_LOCAL = "akyuz-qwen25-coder:14b"

# ─────────────────────────────────────────────────────────────────────────────
# Görev Türleri & Yönlendirme Tablosu
# ─────────────────────────────────────────────────────────────────────────────

class RouteEntry(NamedTuple):
    local: str            # Ollama modeli
    cloud_cheap: str      # Ucuz bulut (Gemini Flash / DeepSeek)
    cloud_premium: str    # Kaliteli bulut (Claude)
    max_ctx_tokens: int   # Context penceresini bu kadarla sınırla
    cloud_trigger: str    # Ne zaman buluta geç: "never"|"error_retry"|"always"

ROUTING_TABLE: dict[str, RouteEntry] = {
    # Selamlama / kısa sohbet — her zaman local küçük model
    "greeting": RouteEntry(
        local="llama3.1:8b",
        cloud_cheap="",
        cloud_premium="",
        max_ctx_tokens=512,
        cloud_trigger="never",
    ),
    # Genel soru (HDL dışı)
    "general_ask": RouteEntry(
        local="llama3.1:8b",
        cloud_cheap="google/gemini-2.5-flash",
        cloud_premium="",
        max_ctx_tokens=2048,
        cloud_trigger="never",
    ),
    # Verilog / HDL yazma
    "verilog_write": RouteEntry(
        local="akyuz-qwen25-coder:14b",
        cloud_cheap="google/gemini-2.5-flash",
        cloud_premium="anthropic/claude-sonnet-4-6",
        max_ctx_tokens=6144,
        cloud_trigger="error_retry",  # Hata sonrası escalate
    ),
    # Verilog hata ayıklama
    "verilog_debug": RouteEntry(
        local="qwen3:14b",
        cloud_cheap="google/gemini-2.5-flash",
        cloud_premium="anthropic/claude-sonnet-4-6",
        max_ctx_tokens=6144,
        cloud_trigger="error_retry",
    ),
    # VCD / simülasyon analizi — premium önce (karmaşık sinyal analizi)
    "vcd_analysis": RouteEntry(
        local="qwen3:14b",
        cloud_cheap="google/gemini-2.5-flash",
        cloud_premium="anthropic/claude-sonnet-4-6",
        max_ctx_tokens=8192,
        cloud_trigger="always",
    ),
    # Vivado TCL üretme — kod modeli yeterli
    "vivado_tcl": RouteEntry(
        local="akyuz-qwen25-coder:14b",
        cloud_cheap="google/gemini-2.5-flash",
        cloud_premium="",
        max_ctx_tokens=4096,
        cloud_trigger="error_retry",
    ),
    # Sentez / timing raporu yorumlama
    "synthesis_report": RouteEntry(
        local="qwen3:14b",
        cloud_cheap="google/gemini-2.5-flash",
        cloud_premium="anthropic/claude-sonnet-4-6",
        max_ctx_tokens=8192,
        cloud_trigger="always",
    ),
    # Genel FPGA pipeline (tasarım + simülasyon + impl)
    "fpga_pipeline": RouteEntry(
        local="akyuz-qwen25-coder:14b",
        cloud_cheap="google/gemini-2.5-flash",
        cloud_premium="anthropic/claude-sonnet-4-6",
        max_ctx_tokens=6144,
        cloud_trigger="error_retry",
    ),
}

# ─────────────────────────────────────────────────────────────────────────────
# Görev Tespiti (keyword tabanlı, LLM çağrısı YOK — token israfı yok)
# ─────────────────────────────────────────────────────────────────────────────

_GREETING_RE = re.compile(
    r"^(merhaba|selam|hey|hi|hello|günaydın|iyi günler|naber|nasılsın|teşekkür|tamam|ok|sağ ol)[!.,\s]*$",
    re.IGNORECASE,
)
_VERILOG_WRITE_RE = re.compile(
    r"\b(verilog|systemverilog|vhdl|modül|module|tasarla|yaz|oluştur|kodla|implement|design|create|generate|write)\b",
    re.IGNORECASE,
)
_VERILOG_DEBUG_RE = re.compile(
    r"\b(hata|bug|düzelt|fix|debug|neden|çalışmıyor|wrong|error|fail|sorun)\b.*\b(verilog|modül|module|kod|code|devre)\b"
    r"|\b(verilog|modül|module|kod|devre)\b.*\b(hata|bug|düzelt|fix|debug|neden|çalışmıyor)\b",
    re.IGNORECASE,
)
_VCD_RE = re.compile(r"\b(vcd|dalga|waveform|sinyal|signal|simülasyon sonucu|sim.*output)\b", re.IGNORECASE)
_TCL_RE = re.compile(r"\b(tcl|vivado.*proje|vivado.*build|sentez|synthesis|impl|bitstream)\b", re.IGNORECASE)
_REPORT_RE = re.compile(r"\b(rapor|report|lut|timing|utilization|wns|kritik yol|timing.*karşıla)\b", re.IGNORECASE)
_FPGA_RE = re.compile(r"\b(fpga|basys|arty|nexys|xilinx|kart|board|pin|xdc)\b", re.IGNORECASE)


def classify_task(message: str) -> str:
    msg = message.strip()
    if _GREETING_RE.match(msg):
        return "greeting"
    if _VCD_RE.search(msg):
        return "vcd_analysis"
    if _REPORT_RE.search(msg):
        return "synthesis_report"
    if _TCL_RE.search(msg):
        return "vivado_tcl"
    if _VERILOG_DEBUG_RE.search(msg):
        return "verilog_debug"
    if _VERILOG_WRITE_RE.search(msg):
        return "verilog_write"
    if _FPGA_RE.search(msg):
        return "fpga_pipeline"
    if len(msg.split()) <= 8 or msg.endswith("?"):
        return "general_ask"
    # Uzun mesaj + hiçbir şey tanımadıysak → fpga pipeline varsayımı
    return "fpga_pipeline"


# ─────────────────────────────────────────────────────────────────────────────
# Bütçe Takibi
# ─────────────────────────────────────────────────────────────────────────────

def _load_budget() -> dict:
    try:
        BUDGET_FILE.parent.mkdir(parents=True, exist_ok=True)
        if BUDGET_FILE.exists():
            return json.loads(BUDGET_FILE.read_text())
    except Exception:
        pass
    return {}


def _save_budget(data: dict) -> None:
    try:
        BUDGET_FILE.write_text(json.dumps(data, indent=2))
    except Exception:
        pass


def get_today_spend() -> float:
    """Bugün harcanan toplam $."""
    data = _load_budget()
    return data.get(str(date.today()), 0.0)


def get_remaining_budget() -> float:
    return max(0.0, DAILY_BUDGET_USD - get_today_spend())


def record_spend(model: str, tokens_used: int) -> float:
    """Harcamayı kaydet, toplam tutarı döndür."""
    cost = COST_PER_1K.get(model, 0.0) * tokens_used / 1000
    if cost == 0:
        return 0.0
    data = _load_budget()
    today = str(date.today())
    data[today] = data.get(today, 0.0) + cost
    # 30 günden eski kayıtları sil
    for key in list(data.keys()):
        if key < str(date.today().replace(day=max(1, date.today().day - 30))):
            del data[key]
    _save_budget(data)
    return cost


def get_budget_summary() -> str:
    spent = get_today_spend()
    remaining = get_remaining_budget()
    pct = spent / DAILY_BUDGET_USD * 100
    bar = "█" * int(pct / 10) + "░" * (10 - int(pct / 10))
    status = "⚠ Bütçe dolmak üzere" if remaining < 0.30 else "✓ Bütçe normal"
    return (
        f"Günlük bütçe: ${DAILY_BUDGET_USD:.2f}\n"
        f"Harcanan:     ${spent:.4f}  [{bar}] {pct:.1f}%\n"
        f"Kalan:        ${remaining:.4f}\n"
        f"Durum:        {status}"
    )


# ─────────────────────────────────────────────────────────────────────────────
# Context Optimizer — Token İsrafını Önle
# ─────────────────────────────────────────────────────────────────────────────

def _estimate_tokens(text: str) -> int:
    """Kaba token tahmini (1 token ≈ 4 karakter)."""
    return len(text) // 4


def optimize_context(
    messages: list[dict],
    max_tokens: int,
    keep_last_n: int = 6,
) -> list[dict]:
    """
    Mesaj geçmişini max_tokens sınırına sığdır:
    1. Araç sonuçları çok uzunsa kısalt
    2. Çok eski mesajları çıkar (system mesajı korunur)
    3. Son keep_last_n user+assistant mesajı mutlaka tut
    """
    if not messages:
        return messages

    # Sistem mesajını ayır
    system_msgs = [m for m in messages if m.get("role") == "system"]
    conv_msgs = [m for m in messages if m.get("role") != "system"]

    # Araç sonuçlarını kısalt (500 token üstü)
    def trim_msg(m: dict) -> dict:
        content = m.get("content", "")
        if m.get("role") == "tool" and _estimate_tokens(content) > 500:
            lines = content.splitlines()
            keep = lines[:40]
            trimmed_count = len(lines) - 40
            if trimmed_count > 0:
                keep.append(f"\n… ({trimmed_count} satır kısaltıldı)")
            return {**m, "content": "\n".join(keep)}
        return m

    trimmed = [trim_msg(m) for m in conv_msgs]

    # Son N mesajı kesinlikle tut
    must_keep = trimmed[-keep_last_n:] if len(trimmed) > keep_last_n else trimmed
    earlier = trimmed[:-keep_last_n] if len(trimmed) > keep_last_n else []

    # Toplam token hesapla
    total = sum(_estimate_tokens(m.get("content", "")) for m in system_msgs + must_keep)

    # Eski mesajları en yeniden başlayarak ekle, bütçe dolana kadar
    allowed_earlier = []
    for m in reversed(earlier):
        cost = _estimate_tokens(m.get("content", ""))
        if total + cost <= max_tokens:
            allowed_earlier.insert(0, m)
            total += cost
        else:
            break

    return system_msgs + allowed_earlier + must_keep


# ─────────────────────────────────────────────────────────────────────────────
# Ana Router
# ─────────────────────────────────────────────────────────────────────────────

class ModelDecision(NamedTuple):
    is_local: bool
    model: str              # Ollama tag veya OpenRouter model ID
    task_type: str
    reason: str
    max_ctx_tokens: int
    estimated_cost: float   # Bu çağrı için tahmini $ (local=0)


def decide_model(
    message: str,
    performance_mode: str = "auto",
    api_key_available: bool = False,
    force_local: bool = False,
    retry_count: int = 0,       # Kaçıncı deneme (hata sonrası escalation için)
) -> ModelDecision:
    """
    Göreve ve bütçeye göre hangi modelin kullanılacağına karar verir.
    """
    task = classify_task(message)
    route = ROUTING_TABLE.get(task, ROUTING_TABLE["fpga_pipeline"])
    remaining = get_remaining_budget()

    # --- Manuel override ---
    if performance_mode == "low" or force_local:
        return ModelDecision(
            is_local=True, model=route.local, task_type=task,
            reason="manual-low / force-local",
            max_ctx_tokens=route.max_ctx_tokens, estimated_cost=0.0,
        )

    if performance_mode == "high":
        if api_key_available:
            cloud = route.cloud_premium or route.cloud_cheap
            if cloud and remaining > 0:
                est = COST_PER_1K.get(cloud, 0) * route.max_ctx_tokens / 1000
                return ModelDecision(
                    is_local=False, model=cloud, task_type=task,
                    reason="manual-high",
                    max_ctx_tokens=route.max_ctx_tokens, estimated_cost=est,
                )
        # API key yoksa veya bütçe bittiyse → fine-tuned yerel model
        return ModelDecision(
            is_local=True, model=FINE_TUNED_LOCAL, task_type=task,
            reason="manual-high-local",
            max_ctx_tokens=route.max_ctx_tokens, estimated_cost=0.0,
        )

    # --- Bütçe tükendiyse her zaman local ---
    if remaining <= 0:
        return ModelDecision(
            is_local=True, model=route.local, task_type=task,
            reason="budget-exhausted",
            max_ctx_tokens=route.max_ctx_tokens, estimated_cost=0.0,
        )

    # --- API key yoksa local ---
    if not api_key_available:
        return ModelDecision(
            is_local=True, model=route.local, task_type=task,
            reason="no-api-key",
            max_ctx_tokens=route.max_ctx_tokens, estimated_cost=0.0,
        )

    # --- Cloud trigger politikası ---
    trigger = route.cloud_trigger

    if trigger == "never":
        return ModelDecision(
            is_local=True, model=route.local, task_type=task,
            reason="task-never-needs-cloud",
            max_ctx_tokens=route.max_ctx_tokens, estimated_cost=0.0,
        )

    if trigger == "always":
        # Premium önce, ucuz fallback
        # Bütçenin %40'ından fazlasını tek çağrıya verme
        budget_per_call_cap = DAILY_BUDGET_USD * 0.40

        if route.cloud_premium and remaining > 0.05:
            model = route.cloud_premium
            est = COST_PER_1K.get(model, 0) * route.max_ctx_tokens / 1000
            if est <= min(remaining, budget_per_call_cap):
                return ModelDecision(
                    is_local=False, model=model, task_type=task,
                    reason="cloud-always-premium",
                    max_ctx_tokens=route.max_ctx_tokens, estimated_cost=est,
                )

        if route.cloud_cheap and remaining > 0.01:
            model = route.cloud_cheap
            est = COST_PER_1K.get(model, 0) * route.max_ctx_tokens / 1000
            return ModelDecision(
                is_local=False, model=model, task_type=task,
                reason="cloud-always-cheap",
                max_ctx_tokens=route.max_ctx_tokens, estimated_cost=est,
            )

        # Fallback local
        return ModelDecision(
            is_local=True, model=route.local, task_type=task,
            reason="cloud-always-but-budget-low",
            max_ctx_tokens=route.max_ctx_tokens, estimated_cost=0.0,
        )

    if trigger == "error_retry":
        if retry_count == 0:
            # İlk deneme local
            return ModelDecision(
                is_local=True, model=route.local, task_type=task,
                reason="first-attempt-local",
                max_ctx_tokens=route.max_ctx_tokens, estimated_cost=0.0,
            )
        elif retry_count == 1:
            # İkinci deneme ucuz bulut
            if route.cloud_cheap and remaining > 0.01:
                model = route.cloud_cheap
                est = COST_PER_1K.get(model, 0) * route.max_ctx_tokens / 1000
                return ModelDecision(
                    is_local=False, model=model, task_type=task,
                    reason="retry-1-cheap-cloud",
                    max_ctx_tokens=route.max_ctx_tokens, estimated_cost=est,
                )
        else:
            # Üçüncü+ deneme premium bulut (bütçe varsa)
            if route.cloud_premium and remaining > 0.05:
                model = route.cloud_premium
                est = COST_PER_1K.get(model, 0) * route.max_ctx_tokens / 1000
                budget_cap = DAILY_BUDGET_USD * 0.40
                if est <= min(remaining, budget_cap):
                    return ModelDecision(
                        is_local=False, model=model, task_type=task,
                        reason=f"retry-{retry_count}-premium-cloud",
                        max_ctx_tokens=route.max_ctx_tokens, estimated_cost=est,
                    )
            if route.cloud_cheap and remaining > 0.01:
                model = route.cloud_cheap
                est = COST_PER_1K.get(model, 0) * route.max_ctx_tokens / 1000
                return ModelDecision(
                    is_local=False, model=model, task_type=task,
                    reason=f"retry-{retry_count}-cheap-cloud",
                    max_ctx_tokens=route.max_ctx_tokens, estimated_cost=est,
                )
        # Her şey başarısız → local
        return ModelDecision(
            is_local=True, model=route.local, task_type=task,
            reason="retry-fallback-local",
            max_ctx_tokens=route.max_ctx_tokens, estimated_cost=0.0,
        )

    # Varsayılan: local
    return ModelDecision(
        is_local=True, model=route.local, task_type=task,
        reason="default-local",
        max_ctx_tokens=route.max_ctx_tokens, estimated_cost=0.0,
    )
