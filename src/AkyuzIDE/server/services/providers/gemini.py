"""Gemini Flash provider — hızlı intent tespiti ve kullanıcı açıklamaları için."""

import httpx
import json
import os
from typing import AsyncIterator

GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta/models"
DEFAULT_MODEL = "gemini-2.0-flash"

_INTENT_SYSTEM = """Sen AkyuzIDE'nin akıllı yönlendirme asistanısın.
Kullanıcının mesajını analiz ederek ne yapmak istediğini kısaca Türkçe açıkla.
Cevabın 2-3 cümle olsun: ne yapılacak, hangi dosyalar/modüller oluşturulacak, neden bu yaklaşım seçildi.
Teknik detay ver ama çok uzun olmasın. Markdown kullanma."""


def _resolve_key(api_key: str | None) -> str | None:
    return api_key or os.getenv("GEMINI_API_KEY") or None


async def gemini_explain(message: str, mode: str, api_key: str | None = None) -> str:
    """Kullanıcının mesajı için kısa bir açıklama üretir (non-streaming)."""
    key = _resolve_key(api_key)
    if not key:
        return ""

    url = f"{GEMINI_API_BASE}/{DEFAULT_MODEL}:generateContent?key={key}"
    payload = {
        "system_instruction": {"parts": [{"text": _INTENT_SYSTEM}]},
        "contents": [
            {"role": "user", "parts": [{"text": f"Kullanıcı mesajı: {message}\nTespit edilen mod: {mode}"}]}
        ],
        "generationConfig": {"maxOutputTokens": 200, "temperature": 0.3},
    }

    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.post(url, json=payload)
            resp.raise_for_status()
            data = resp.json()
            candidates = data.get("candidates", [])
            if candidates:
                parts = candidates[0].get("content", {}).get("parts", [])
                return "".join(p.get("text", "") for p in parts).strip()
    except Exception:
        pass
    return ""


async def gemini_explain_stream(
    message: str, mode: str, api_key: str | None = None
) -> AsyncIterator[str]:
    """Açıklamayı token token stream eder."""
    key = _resolve_key(api_key)
    if not key:
        return

    url = f"{GEMINI_API_BASE}/{DEFAULT_MODEL}:streamGenerateContent?key={key}&alt=sse"
    payload = {
        "system_instruction": {"parts": [{"text": _INTENT_SYSTEM}]},
        "contents": [
            {"role": "user", "parts": [{"text": f"Kullanıcı mesajı: {message}\nTespit edilen mod: {mode}"}]}
        ],
        "generationConfig": {"maxOutputTokens": 200, "temperature": 0.3},
    }

    try:
        async with httpx.AsyncClient(timeout=12.0) as client:
            async with client.stream("POST", url, json=payload) as resp:
                resp.raise_for_status()
                async for line in resp.aiter_lines():
                    if not line.startswith("data: "):
                        continue
                    raw = line[6:].strip()
                    if not raw or raw == "[DONE]":
                        continue
                    try:
                        data = json.loads(raw)
                        candidates = data.get("candidates", [])
                        if candidates:
                            parts = candidates[0].get("content", {}).get("parts", [])
                            chunk = "".join(p.get("text", "") for p in parts)
                            if chunk:
                                yield chunk
                    except Exception:
                        continue
    except Exception:
        return


async def gemini_detect_mode(message: str, api_key: str | None = None) -> str | None:
    """Regex'in yetersiz kaldığı durumlarda Gemini ile mod tespiti yapar.
    'agent', 'ask', 'plan' veya None döndürür.
    """
    key = _resolve_key(api_key)
    if not key:
        return None

    system = (
        "Kullanıcının mesajını analiz et ve sadece şu üç kelimeden birini yaz: agent, ask, plan\n"
        "agent: dosya oluşturma/düzenleme/silme, kod yazma, derleme, simülasyon gerektiriyorsa\n"
        "ask: bilgi sorma, açıklama isteme, soru sorma ise\n"
        "plan: strateji/yol haritası/adım planı istiyorsa\n"
        "Sadece tek kelime yaz, başka hiçbir şey ekleme."
    )
    url = f"{GEMINI_API_BASE}/{DEFAULT_MODEL}:generateContent?key={key}"
    payload = {
        "system_instruction": {"parts": [{"text": system}]},
        "contents": [{"role": "user", "parts": [{"text": message}]}],
        "generationConfig": {"maxOutputTokens": 5, "temperature": 0.0},
    }

    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(url, json=payload)
            resp.raise_for_status()
            data = resp.json()
            candidates = data.get("candidates", [])
            if candidates:
                parts = candidates[0].get("content", {}).get("parts", [])
                result = "".join(p.get("text", "") for p in parts).strip().lower()
                if result in ("agent", "ask", "plan"):
                    return result
    except Exception:
        pass
    return None
