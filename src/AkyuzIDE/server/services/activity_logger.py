"""
server/services/activity_logger.py
Tüm agent tool çağrıları, workspace değişiklikleri ve build işlemlerini loglar.
"""

import os
import json
import threading
from datetime import datetime
from pathlib import Path

_lock = threading.Lock()

LOG_DIR = Path(os.getenv("AKYUZ_LOG_DIR",
                         Path.home() / ".config" / "akyuzide" / "logs"))
LOG_DIR.mkdir(parents=True, exist_ok=True)

_LOG_FILE = LOG_DIR / "activity.log"
_JSON_FILE = LOG_DIR / "activity.jsonl"

# Çok uzun argümanları kısalt (kod içeriği vb.)
_MAX_ARG_LEN = 120


def _truncate(val, max_len=_MAX_ARG_LEN) -> str:
    s = str(val)
    if len(s) > max_len:
        return s[:max_len] + f"… (+{len(s)-max_len} char)"
    return s


def _fmt_args(args: dict) -> str:
    parts = []
    for k, v in args.items():
        parts.append(f"{k}={_truncate(v)}")
    return ", ".join(parts)


def _write(entry: dict):
    ts = entry["timestamp"]
    level = entry.get("level", "INFO")
    category = entry.get("category", "GENERAL")
    message = entry.get("message", "")
    detail = entry.get("detail", "")

    line = f"[{ts}] [{level}] [{category}] {message}"
    if detail:
        line += f" | {detail}"

    with _lock:
        with open(_LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
        with open(_JSON_FILE, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def _entry(category: str, message: str, detail: str = "", level: str = "INFO", extra: dict = None) -> dict:
    now = datetime.now()
    e = {
        "timestamp": now.strftime("%Y-%m-%d %H:%M:%S.") + f"{now.microsecond // 1000:03d}",
        "level": level,
        "category": category,
        "message": message,
        "detail": detail,
    }
    if extra:
        e.update(extra)
    return e


# ──────────────────────────────────────────────────────────────────────────────
# PUBLIC API
# ──────────────────────────────────────────────────────────────────────────────

def log_tool_call(tool_name: str, args: dict, result: str, file_changed: bool = False):
    """Agent bir tool çağırdığında logla."""
    # Sonucu kısalt
    result_short = _truncate(result, 200)
    ok = not result_short.startswith("Error")
    level = "INFO" if ok else "ERROR"
    detail = f"args=({_fmt_args(args)}) → {result_short}"
    _write(_entry("TOOL", tool_name, detail, level, {"tool": tool_name, "ok": ok, "file_changed": file_changed}))


def log_workspace_change(old_path: str, new_path: str):
    _write(_entry("WORKSPACE", "workspace changed",
                  f"{old_path} → {new_path}", "INFO",
                  {"old": old_path, "new": new_path}))


def log_agent_start(user_message: str, mode: str = "agent"):
    short = _truncate(user_message, 100)
    _write(_entry("AGENT", "session started", f"mode={mode} | prompt={short}", "INFO"))


def log_agent_end(iterations: int, status: str = "done"):
    _write(_entry("AGENT", "session ended", f"iterations={iterations} | status={status}", "INFO"))


def log_simulation(files: list, success: bool, output: str):
    result_short = _truncate(output, 300)
    level = "INFO" if success else "WARN"
    _write(_entry("SIM", "simulation", f"files={files} | {'PASS' if success else 'FAIL'} | {result_short}", level,
                  {"files": files, "success": success}))


def log_vivado(phase: str, success: bool, detail: str = ""):
    level = "INFO" if success else "ERROR"
    status = "OK" if success else "FAILED"
    _write(_entry("VIVADO", f"{phase} {status}", _truncate(detail, 200), level,
                  {"phase": phase, "success": success}))


def log_server_event(message: str, detail: str = "", level: str = "INFO"):
    _write(_entry("SERVER", message, detail, level))


def log_error(source: str, message: str, exc: Exception = None):
    detail = f"{message}"
    if exc:
        detail += f" | exception={type(exc).__name__}: {exc}"
    _write(_entry(source, "ERROR", detail, "ERROR"))


def get_recent_log(lines: int = 100) -> str:
    """Son N log satırını döndür (agent veya UI için)."""
    try:
        with open(_LOG_FILE, "r", encoding="utf-8") as f:
            all_lines = f.readlines()
        return "".join(all_lines[-lines:])
    except FileNotFoundError:
        return "(log dosyası henüz oluşturulmadı)"
    except Exception as e:
        return f"(log okunamadı: {e})"


def get_log_path() -> str:
    return str(_LOG_FILE)


def rotate_if_large(max_mb: float = 5.0):
    """Log 5MB'ı geçerse arşivle, yenisini başlat."""
    try:
        if _LOG_FILE.stat().st_size > max_mb * 1024 * 1024:
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            _LOG_FILE.rename(LOG_DIR / f"activity_{ts}.log")
            _JSON_FILE.rename(LOG_DIR / f"activity_{ts}.jsonl")
            log_server_event("log rotated", f"archived at {ts}")
    except Exception:
        pass
