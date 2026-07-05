"""
EDA / runtime checks for the agent: Ollama, Icarus (iverilog/vvp), Vivado path.
"""
from __future__ import annotations

import os
import subprocess
from typing import Any

import httpx


def _run_version(cmd: str, timeout: float = 8.0) -> dict[str, Any]:
    try:
        r = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        out = (r.stdout or r.stderr or "").strip()
        head = (out.splitlines()[0] if out else f"(çıktı yok, exit {r.returncode})")[:200]
        ok = r.returncode == 0
        if not ok and out:
            # Icarus sometimes prints version to stderr with 0; accept known patterns
            low = out.lower()
            ok = "icarus" in low or "iverilog" in low
        return {"ok": bool(ok), "detail": head}
    except subprocess.TimeoutExpired:
        return {"ok": False, "detail": "zaman aşımı"}
    except Exception as e:
        return {"ok": False, "detail": str(e)}


def check_ollama(base_url: str) -> dict[str, Any]:
    b = (base_url or "").strip().rstrip("/")
    if not b.startswith("http://") and not b.startswith("https://"):
        b = f"http://{b}"
    try:
        with httpx.Client(timeout=6.0, follow_redirects=True, trust_env=False) as client:
            r = client.get(f"{b}/api/tags")
            if r.status_code != 200:
                return {"ok": False, "detail": f"HTTP {r.status_code}", "host": b, "model_sample": []}
            data = r.json()
            names = [m["name"] for m in data.get("models", [])]
            sample = names[:5]
            extra = f" (örnek: {', '.join(sample)})" if sample else " (yüklü model yok)"
            return {
                "ok": True,
                "detail": f"erişilebilir, {len(names)} model{extra}",
                "host": b,
                "model_sample": sample,
            }
    except Exception as e:
        return {"ok": False, "detail": str(e)[:200], "host": b, "model_sample": []}


def check_icarus(iverilog_path: str, vvp_path: str) -> dict[str, Any]:
    iver = _run_version(f'"{iverilog_path}" -V' if os.path.sep in iverilog_path else f"{iverilog_path} -V")
    vvp = _run_version(f'"{vvp_path}" -V' if os.path.sep in vvp_path else f"{vvp_path} -V")
    return {
        "iverilog": iver,
        "vvp": vvp,
        "ok": bool(iver.get("ok") and vvp.get("ok")),
    }


def check_vivado_bat(vivado_bat: str) -> dict[str, Any]:
    p = vivado_bat or ""
    if not p:
        return {"ok": False, "detail": "VIVADO_PATH boş"}
    if os.path.isfile(p):
        return {"ok": True, "detail": f"Yol mevcut: {p}"}
    return {"ok": False, "detail": f"Yol bulunamadı: {p}"}


def build_agent_environment(
    ollama_host: str,
    iverilog_path: str,
    vvp_path: str,
    vivado_bat: str,
) -> dict[str, Any]:
    """
    Returns:
      - system_block: Appended to agent system prompt (Turkish).
      - user_line: Short line for SSE (shown in chat streaming strip).
      - parts: raw dicts for API/debug.
    """
    o = check_ollama(ollama_host)
    ic = check_icarus(iverilog_path, vvp_path)
    v = check_vivado_bat(vivado_bat)

    ollama_s = f"OK — {o['detail']}" if o.get("ok") else f"BAĞLANTI YOK / HATA — {o.get('detail', '')}"
    iv_s = f"iverilog: {'OK' if ic['iverilog'].get('ok') else 'HATA'} ({ic['iverilog'].get('detail', '')})"
    vvp_s = f"vvp: {'OK' if ic['vvp'].get('ok') else 'HATA'} ({ic['vvp'].get('detail', '')})"
    viv_s = f"{'OK' if v.get('ok') else 'EKSİK / HATA'} — {v.get('detail', '')}"

    system_block = f"""
--- Otomatik ortam özeti (sunucu tarafı, {o.get("host", "")}) ---
- Ollama (yerel/uzak AI): {ollama_s}
- Icarus Verilog: {iv_s}
- {vvp_s}
- Vivado (batch): {viv_s}

GÖREV: Kullanıcıya ilk yanıtında (veya kısa bir devam cümlesinde) bu durumu 2-4 cümleyle Türkçe özetle:
  - AI modeli için Ollama erişimi,
  - Simülasyon için iverilog/vvp (Icarus),
  - Sentez/yükleme için Vivado yolunun cihazda geçerli olup olmadığı.
Eksik bir bileşen varsa ne yapılması gerektiğini sade dille söyle (PATH, kurulum, .env VIVADO_PATH vb.). Ardından kullanıcının isteğine geç.
"""

    user_line = (
        f"Ortam: Ollama {'OK' if o.get('ok') else 'YOK'} | "
        f"Icarus (iverilog/vvp) {'OK' if ic.get('ok') else 'YOK'} | "
        f"Vivado {'OK' if v.get('ok') else 'YOK'}"
    )

    return {
        "system_block": system_block.strip() + "\n",
        "user_line": user_line,
        "parts": {"ollama": o, "icarus": ic, "vivado": v},
    }
