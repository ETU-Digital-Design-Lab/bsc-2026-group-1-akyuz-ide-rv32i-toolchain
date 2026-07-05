from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, field_validator
from typing import List, Optional, Dict, Any
import os
import re
import sys
import uuid
import unicodedata
import datetime
from pathlib import Path
import uvicorn
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Import our modernized services
from services.assembler import RV32IAssembler
from services.simulation import SimulationService
from services.ai_remote import AIService
from services.hardware import HardwareService
from services.vivado import VivadoService
from fastapi.staticfiles import StaticFiles

app = FastAPI(title="AkyuzIDE Backend API")

# Pending confirmation sessions: session_id → engine state
_PENDING_SESSIONS: dict = {}

# Enable CORS for the React frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # In production, restrict this to the frontend origin
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Services
# --- Unicode-safe path helpers ---
def _upath(p: str) -> str:
    """Return NFC-normalized, absolute path string — handles Turkish/Unicode chars on Windows."""
    return unicodedata.normalize("NFC", str(Path(p).resolve()))

def _umkdir(p: str):
    Path(p).mkdir(parents=True, exist_ok=True)

def _uexists(p: str) -> bool:
    return Path(p).exists()

def _uisdir(p: str) -> bool:
    return Path(p).is_dir()

def _uisfile(p: str) -> bool:
    return Path(p).is_file()

def _ulistdir(p: str) -> list[str]:
    return sorted([x.name for x in Path(p).iterdir()], key=lambda n: (not Path(p, n).is_dir(), n.lower()))

WORKSPACE_DIR = _upath(os.getenv("WORKSPACE_DIR", os.path.join(os.getcwd(), "workspace")))
_umkdir(WORKSPACE_DIR)

# Hardware Toolchain Detection (Standalone Support)
IVERILOG_PATH = "iverilog"
VVP_PATH = "vvp"
RISCV_GCC_PATH = "riscv-none-elf-gcc"

# Check for bundled toolchain or common local path
common_path = "C:\\iverilog\\bin"
local_toolchain = os.path.join(os.getcwd(), "toolchain", "riscv", "bin")

if os.path.exists(os.path.join(common_path, "iverilog.exe")):
    IVERILOG_PATH = os.path.join(common_path, "iverilog.exe")
    VVP_PATH = os.path.join(common_path, "vvp.exe")

if os.path.exists(os.path.join(local_toolchain, "riscv-none-elf-gcc.exe")):
    RISCV_GCC_PATH = os.path.join(local_toolchain, "riscv-none-elf-gcc.exe")
    print(f"[Main] Using local RISC-V toolchain: {RISCV_GCC_PATH}")

assembler = RV32IAssembler()

simulation = SimulationService(
    iverilog_path=IVERILOG_PATH,
    vvp_path=VVP_PATH
)

# Ollama-only defaults (local or remote via Tailscale/ngrok)
OLLAMA_DEFAULT = os.getenv("OLLAMA_HOST", "http://127.0.0.1:11434")
REMOTE_AI_HOST = os.getenv("REMOTE_AI_HOST", OLLAMA_DEFAULT)
DEFAULT_MODEL = os.getenv("AI_MODEL", "qwen3:latest")

ai = AIService(
    base_url=REMOTE_AI_HOST,
    model=DEFAULT_MODEL,
    api_key=None
)

hardware = HardwareService(workspace_dir=os.path.join(WORKSPACE_DIR, "_hardware"))
# Update hardware service with compiler path if needed
hardware.compiler_path = RISCV_GCC_PATH

VIVADO_PATH = os.getenv("VIVADO_PATH", "C:\\Xilinx\\Vivado\\2024.1\\bin\\vivado.bat")
vivado = VivadoService(
    workspace_dir=os.path.join(WORKSPACE_DIR, "_vivado"),
    vivado_path=VIVADO_PATH
)

# --- Models ---
class AssembleRequest(BaseModel):
    source: str
    start_address: int = 0

class SimulateRequest(BaseModel):
    files: List[str]
    top_module: str = "tb_top"

class ChatRequest(BaseModel):
    messages: List[Dict[str, str]]
    remote_host: Optional[str] = None
    model: Optional[str] = None
    system_prompt: Optional[str] = None

    @field_validator("model", mode="before")
    @classmethod
    def _strip_model_opt(cls, v):
        if v is None:
            return None
        return str(v).strip() if isinstance(v, str) else v

class RenameRequest(BaseModel):
    old_path: str
    new_path: str

class WorkspaceRequest(BaseModel):
    path: str


def _extract_path_from_text(text: str) -> Optional[str]:
    """Best-effort path extraction from natural language user text."""
    if not text:
        return None
    # Quoted Windows absolute path: "C:\foo bar\baz" or "C\foo\bar"
    win_quoted = re.findall(r'["\']([A-Za-z](?::|\\)[^"\']+)["\']', text)
    if win_quoted:
        return sorted(win_quoted, key=len, reverse=True)[0].strip()
    # Windows absolute path without quotes (mixed separators supported)
    win = re.findall(r"[A-Za-z](?::|\\)[^\"'`\n]+", text)
    if win:
        # Prefer the longest path-like token that contains at least one separator
        pathy = [w.strip() for w in win if ("\\" in w or "/" in w)]
        if pathy:
            return sorted(pathy, key=len, reverse=True)[0]
    # Quoted Unix path
    unix_quoted = re.findall(r'["\'](/[^"\']+)["\']', text)
    if unix_quoted:
        return sorted(unix_quoted, key=len, reverse=True)[0].strip()
    # Unix-like absolute path without spaces: /foo/bar
    unix = re.findall(r"/[^\s\"'`]+", text)
    if unix:
        return sorted(unix, key=len, reverse=True)[0].strip()
    return None


def _coerce_windows_path(raw: str) -> str:
    """Normalize noisy user-entered Windows paths (mixed slash, missing drive colon)."""
    p = unicodedata.normalize("NFC", str(raw or "").strip().strip('"').strip("'").strip("`"))
    if not p:
        return p
    # Remove trailing punctuation from natural language
    p = p.rstrip(".,;:!?)]} ")
    # C\Users\... -> C:\Users\...
    p = re.sub(r"^([A-Za-z])\\", r"\1:\\", p)
    # C/Users/... -> C:/Users/...
    p = re.sub(r"^([A-Za-z])/", r"\1:/", p)
    # If drive-prefixed, prefer backslash on Windows
    if re.match(r"^[A-Za-z]:", p):
        p = p.replace("/", "\\")
        p = re.sub(r"\\{2,}", r"\\", p)
    return p


def _normalize_target_path(raw: Optional[str]) -> str:
    if not raw:
        return WORKSPACE_DIR
    p = _coerce_windows_path(str(raw))
    if not p:
        return WORKSPACE_DIR
    if Path(p).is_absolute():
        return _upath(p)
    return _upath(str(Path(WORKSPACE_DIR) / p))


def _fold_tr(text: str) -> str:
    """Flatten Turkish/Unicode text for fuzzy comparisons."""
    # Map Turkish special i variants first (must happen before NFKD, which can't map İ)
    pre = (
        text.replace("İ", "i")
            .replace("I\u0307", "i")  # Capital I + combining dot -> i
            .replace("ı", "i")
            .replace("I", "i")
    )
    norm = unicodedata.normalize("NFKD", pre)
    plain = "".join(ch for ch in norm if not unicodedata.combining(ch))
    return plain.lower()


def _resolve_path_fuzzy(target: str) -> str:
    """Walk path components with NFC + Turkish-i tolerance on each segment."""
    # NFC-normalize first — this alone fixes most Windows path mismatches
    nfc_target = unicodedata.normalize("NFC", target)
    if Path(nfc_target).exists():
        return nfc_target

    # Walk component by component using pathlib (handles Windows drive letters)
    try:
        parts = Path(nfc_target).parts  # e.g. ('C:\\', 'Users', 'Taha', 'akyuzide')
    except Exception:
        return target

    if not parts:
        return target

    current = Path(parts[0])
    for part in parts[1:]:
        if not current.is_dir():
            return target
        try:
            children = [c.name for c in current.iterdir()]
        except Exception:
            return target

        # 1. Exact match
        if part in children:
            current = current / part
            continue

        # 2. NFC-normalised match (covers most Windows Türkçe issues)
        nfc_part = unicodedata.normalize("NFC", part)
        nfc_match = next((c for c in children if unicodedata.normalize("NFC", c) == nfc_part), None)
        if nfc_match:
            current = current / nfc_match
            continue

        # 3. Folded (diacritic-free, case-insensitive) match
        folded = _fold_tr(part)
        approx = next((c for c in children if _fold_tr(c) == folded), None)
        if approx:
            current = current / approx
            continue

        # component not found — return best-effort original
        return target

    return str(current)


def _build_directory_listing_reply(user_text: str) -> Optional[str]:
    """Deterministic folder listing shortcut (prevents agent hallucinations)."""
    low = (user_text or "").lower()
    list_intent = any(
        k in low
        for k in (
            "listele",
            "klasörde ne var",
            "klasor",
            "folder",
            "directory",
            "içinde ne var",
            "icinde ne var",
            "show files",
            "ls ",
            "dir ",
            "bunda ne var",
        )
    )
    if not list_intent:
        return None

    candidate = _extract_path_from_text(user_text)
    target = _resolve_path_fuzzy(_normalize_target_path(candidate))

    tp = Path(target)
    if not tp.exists():
        # Fallback: try basename under workspace when user typed a noisy path.
        if candidate:
            base = Path(_coerce_windows_path(candidate)).name.strip()
            if base:
                ws_try = Path(WORKSPACE_DIR) / base
                ws_try = Path(_resolve_path_fuzzy(str(ws_try)))
                if ws_try.exists():
                    tp = ws_try
                    target = str(ws_try)
                else:
                    return (
                        f"❌ Yol bulunamadı: {target}\n"
                        "Not: Yazım/ayraç hatalarını otomatik düzeltmeyi denedim ama eşleşme bulamadım."
                    )
            else:
                return f"❌ Yol bulunamadı: {target}"
        else:
            return f"❌ Yol bulunamadı: {target}"

    if tp.is_file():
        try:
            size = tp.stat().st_size
        except Exception:
            size = -1
        return (
            f"`{target}` bir dosya.\n"
            f"- Ad: `{tp.name}`\n"
            f"- Boyut: `{size}` byte"
        )

    try:
        children = sorted(tp.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower()))
        names = [c.name for c in children]
    except Exception as e:
        return f"❌ Klasör okunamadı: {target}\nHata: {str(e)}"

    if not names:
        return f"`{target}` klasörü boş."

    lines = [f"`{target}` içeriği ({len(names)} öğe):"]
    for c in children[:120]:
        marker = "/" if c.is_dir() else ""
        lines.append(f"- `{c.name}{marker}`")
    if len(names) > 120:
        lines.append(f"- ... ve {len(names) - 120} öğe daha")
    return "\n".join(lines)


def _build_create_items_reply(user_text: str) -> Optional[str]:
    """Deterministic create-folder/create-file shortcut for common Turkish prompts."""
    text = user_text or ""
    low = _fold_tr(text)
    wants_create = any(
        k in low
        for k in (
            "olustur",
            "yarat",
            "ekle",
            "create",
            "new file",
            "new folder",
            "yaz",
            "kodu yaz",
            "dosyaya yaz",
            "write",
            "kaydet",
            "hazirla",
        )
    )

    root_candidate = _extract_path_from_text(text)
    root = _resolve_path_fuzzy(_normalize_target_path(root_candidate))
    if not os.path.isdir(root):
        root = WORKSPACE_DIR

    # Relative folder intent: "deneme1 içine alu.v yaz", "deneme1 klasorune ...".
    rel_root_match = re.search(
        r"\b([a-z0-9_.\-]+)\s+(?:klasor(?:u|une|unun)?)?\s*(?:icine|icine|icerisine|altina|klasorune)\b",
        low,
        flags=re.IGNORECASE,
    )
    if rel_root_match:
        rel_name = rel_root_match.group(1).strip(". ")
        if rel_name and rel_name not in ("bu", "su", "o"):
            rel_candidate = Path(root) / rel_name
            rel_candidate = Path(_resolve_path_fuzzy(str(rel_candidate)))
            if rel_candidate.is_dir():
                root = str(rel_candidate)

    # Example: "abc klasörü oluştur", "abc klasor olustur"
    folder_names = re.findall(
        r"\b([a-z0-9_.\-]+)\s+klasor(?:u)?\s+(?:olustur|yarat|ekle|ac)\b",
        low,
        flags=re.IGNORECASE,
    )
    folder_names = [n.strip(". ") for n in folder_names if n.strip(". ")]

    # Example: "foo.v dosyası oluştur", "bar.py oluştur"
    file_names = re.findall(
        r"\b([a-z0-9_.\-]+\.(?:v|sv|py|txt|md|json|c|h|cpp|tcl|log))\b",
        low,
        flags=re.IGNORECASE,
    )
    file_names = [n.strip(". ") for n in file_names if n.strip(". ")]

    # Example: "aluv kodu yaz", "alu dosyasi yaz" -> infer Verilog filename
    if not file_names and wants_create:
        inferred = re.findall(
            r"\b([a-z0-9_.\-]+)\s+(?:kodu|dosyasi)\s+yaz\w*\b",
            low,
            flags=re.IGNORECASE,
        )
        for stem in inferred:
            s = stem.strip(". ")
            if not s:
                continue
            if "." in s:
                file_names.append(s)
            else:
                file_names.append(f"{s}.v")

    # If no deterministic target is found, let agent path handle it.
    if not folder_names and not file_names and not wants_create:
        return None

    created: list[str] = []
    skipped: list[str] = []

    root_p = Path(root)
    for folder in folder_names:
        fp = root_p / folder
        try:
            if fp.is_dir():
                skipped.append(f"`{folder}/` (zaten var)")
                continue
            fp.mkdir(parents=True, exist_ok=True)
            created.append(f"`{folder}/`")
        except Exception as e:
            skipped.append(f"`{folder}/` (hata: {str(e)})")

    for file_name in file_names:
        fp = root_p / file_name
        try:
            fp.parent.mkdir(parents=True, exist_ok=True)
            if fp.exists():
                skipped.append(f"`{file_name}` (zaten var)")
                continue
            fp.write_text("", encoding="utf-8")
            created.append(f"`{file_name}`")
        except Exception as e:
            skipped.append(f"`{file_name}` (hata: {str(e)})")

    if not created and not skipped:
        return None

    lines = [f"İşlem kökü: `{root}`"]
    if created:
        lines.append("Oluşturuldu:")
        lines.extend([f"- {x}" for x in created])
    if skipped:
        lines.append("Atlandı:")
        lines.extend([f"- {x}" for x in skipped])
    return "\n".join(lines)

# --- Endpoints ---

@app.get("/api/health")
async def health_check():
    return {"status": "ok", "workspace": WORKSPACE_DIR}

@app.post("/api/workspace/set")
async def set_workspace(req: WorkspaceRequest):
    global WORKSPACE_DIR, hardware, vivado
    # First NFC-normalize, then fuzzy-resolve for Turkish/Unicode folder names
    raw = unicodedata.normalize("NFC", str(req.path).strip().strip('"').strip("'"))
    resolved = _resolve_path_fuzzy(raw)
    normalized_path = _upath(resolved)

    if not _uexists(normalized_path):
        raise HTTPException(status_code=404, detail=f"Klasör bulunamadı: {req.path}")

    WORKSPACE_DIR = normalized_path
    os.environ["WORKSPACE_DIR"] = WORKSPACE_DIR
    print(f"[Main] Workspace changed to: {WORKSPACE_DIR}")

    hardware.workspace_dir = str(Path(WORKSPACE_DIR) / "_hardware")
    vivado.workspace_dir   = str(Path(WORKSPACE_DIR) / "_vivado")

    # Agent tools da güncellenmeli — yoksa agent eski workspace'te çalışır
    _agent_tools.vivado_service.workspace_dir = str(Path(WORKSPACE_DIR) / "_vivado")
    _agent_tools.vivado_service.project_dir   = Path(WORKSPACE_DIR) / "_vivado" / _agent_tools.vivado_service.project_name
    _agent_tools.plan_manager.workspace_dir   = WORKSPACE_DIR

    return {"success": True, "workspace": WORKSPACE_DIR}

@app.post("/api/assemble")
async def api_assemble(req: AssembleRequest):
    try:
        result = assembler.assemble(req.source)
        return {
            "hex": result.to_readmemh(),
            "listing": result.listing,
            "symbols": result.symbols
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/api/files/{path:path}")
async def get_file_content(path: str):
    full_path = _upath(str(Path(WORKSPACE_DIR) / path))
    if not _uexists(full_path):
        raise HTTPException(status_code=404, detail="File not found")
    try:
        return {"content": Path(full_path).read_text(encoding="utf-8")}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/files/{path:path}")
async def save_file_content(path: str, data: dict):
    full_path = _upath(str(Path(WORKSPACE_DIR) / path))
    try:
        content = data.get("content", "")
        Path(full_path).parent.mkdir(parents=True, exist_ok=True)
        Path(full_path).write_text(content, encoding="utf-8")
        return {"success": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/files/{path:path}")
async def delete_file(path: str):
    full_path = _upath(str(Path(WORKSPACE_DIR) / path))
    if not _uexists(full_path):
        raise HTTPException(status_code=404, detail="File not found")
    try:
        p = Path(full_path)
        if p.is_dir():
            import shutil
            shutil.rmtree(p)
        else:
            p.unlink()
        return {"success": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/files/rename")
async def rename_file(req: RenameRequest):
    old_full = _upath(str(Path(WORKSPACE_DIR) / req.old_path))
    new_full = _upath(str(Path(WORKSPACE_DIR) / req.new_path))
    if not _uexists(old_full):
        raise HTTPException(status_code=404, detail="Source not found")
    if _uexists(new_full):
        raise HTTPException(status_code=400, detail="Destination already exists")
    try:
        Path(new_full).parent.mkdir(parents=True, exist_ok=True)
        Path(old_full).rename(new_full)
        return {"success": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# New architecture
from services.agent.engine import AgentEngine as NewAgentEngine, route_request
from services.agent.mode_detector import detect_mode
from services.smart_router import decide_model, optimize_context, record_spend, get_budget_summary
from services.providers.ollama import OllamaProvider
from services.providers.openrouter import OpenRouterProvider
from services.providers.moonshot import MoonshotProvider
from services.providers.gemini import gemini_explain_stream, gemini_detect_mode
# Legacy (kept for non-agent endpoints)
from services.agent_engine import AgentEngine
from services.eda_diagnostics import build_agent_environment
import services.agent_tools as _agent_tools
from fastapi.responses import StreamingResponse
import json as json_lib
import httpx as httpx_lib


def normalize_ollama_base(url: Optional[str]) -> str:
    """Ollama base URL (no /api/v1)."""
    raw = (url or OLLAMA_DEFAULT or "http://127.0.0.1:11434").strip()
    raw = raw.replace("/api/v1", "").rstrip("/")
    if not raw.startswith(("http://", "https://")):
        raw = f"http://{raw}"
    raw = raw.rstrip("/")
    # Windows: localhost bazen ::1 olur; Ollama genelde yalnizca IPv4 dinler
    raw = raw.replace("://localhost:", "://127.0.0.1:")
    if raw in ("http://localhost", "https://localhost"):
        raw = "http://127.0.0.1:11434"
    return raw


def _norm_model_tag(s: str) -> str:
    """Tire/bosluk varyantlarini Ollama etiketiyle uyumlu hale getirir."""
    if not s:
        return ""
    t = (
        str(s)
        .replace("\u2013", "-")
        .replace("\u2014", "-")
        .replace("\uff0d", "-")
        .strip()
    )
    return t


async def ollama_fetch_model_tags(ollama_base: str) -> List[str]:
    base = normalize_ollama_base(ollama_base)
    try:
        async with httpx_lib.AsyncClient(timeout=12.0, trust_env=False) as client:
            r = await client.get(f"{base}/api/tags")
            if r.status_code != 200:
                return []
            data = r.json()
            out: List[str] = []
            for m in data.get("models") or []:
                if isinstance(m, dict) and m.get("name"):
                    out.append(str(m["name"]).strip())
            return out
    except Exception:
        return []


def resolve_ollama_model_for_request(requested: str, tags: List[str]) -> tuple[Optional[str], Optional[str]]:
    """
    (ollama_model, None) veya (None, kullaniciya_aciklama).
    tags bos ise istenen dizgiyi oldugu gibi dener (Ollama bos olabilir).
    """
    r = _norm_model_tag(requested or "")
    if not tags:
        return (r or None, None)
    if not r:
        return (tags[0], None)
    uniq = list(dict.fromkeys(tags))
    if r in uniq:
        return (r, None)
    rn = _norm_model_tag(r)
    for t in uniq:
        if _norm_model_tag(t) == rn:
            return (t, None)
    rl = r.lower()
    for t in uniq:
        if t.lower() == rl:
            return (t, None)
    tail = r.split("/")[-1]
    for t in uniq:
        if t == tail or t.endswith("/" + tail):
            return (t, None)
    preview = ", ".join(uniq[:10])
    more = " …" if len(uniq) > 10 else ""
    return (
        None,
        f"'{r}' bu Ollama örneğinde yok. Yüklü: {preview}{more}. Ayarlar'daki Ollama adresi ile `ollama list` aynı mı kontrol edin; gerekirse: ollama pull {r}",
    )


class AgentChatRequest(BaseModel):
    message: str
    remote_host: str = "http://127.0.0.1:11434"
    model: str = "qwen2.5-coder:14b"
    history: List[Dict[str, str]] = []
    system_prompt: Optional[str] = None
    active_file: Optional[str] = None
    open_files: List[str] = []
    # agent = full tools; plan = read-only planning subset
    agent_mode: Optional[str] = "agent"
    api_key: Optional[str] = None
    moonshot_api_key: Optional[str] = None
    moonshot_model: Optional[str] = "kimi-latest"
    # "auto" = smart routing, "high" = qwen3:latest, "low" = llama3.1:8b
    performance_mode: Optional[str] = "auto"
    # Google AI Studio key — hızlı intent tespiti + kullanıcı açıklaması için
    gemini_key: Optional[str] = None

    @field_validator("model", mode="before")
    @classmethod
    def _strip_model(cls, v):
        if isinstance(v, str):
            return v.strip()
        return v or "qwen2.5-coder:14b"

class PullModelRequest(BaseModel):
    name: str
    host: Optional[str] = None

@app.get("/api/models")
async def list_ollama_models(host: Optional[str] = None):
    """List tags from a running Ollama instance (proxied through backend for CORS)."""
    base = normalize_ollama_base(host)
    try:
        async with httpx_lib.AsyncClient(timeout=15.0, trust_env=False) as client:
            res = await client.get(f"{base}/api/tags")
            res.raise_for_status()
            data = res.json()
            names = [m["name"] for m in data.get("models", [])]
            return {"models": names, "host": base}
    except Exception as e:
        return {"models": [], "host": base, "error": str(e)}


@app.post("/api/models/pull")
async def pull_model(req: PullModelRequest):
    """Pull a model from Ollama."""
    base = normalize_ollama_base(req.host)
    try:
        async with httpx_lib.AsyncClient(timeout=None, trust_env=False) as client:
            # Ollama: yeni surumler "model", bazilari "name" — ikisini gonder; 405 ise name-only dene
            payload: dict = {"model": req.name, "name": req.name, "stream": False}
            res = await client.post(f"{base}/api/pull", json=payload)
            if res.status_code == 405:
                res = await client.post(
                    f"{base}/api/pull",
                    json={"name": req.name, "stream": False},
                )
            if res.status_code >= 400:
                body = (res.text or "")[:500]
                raise HTTPException(
                    status_code=502,
                    detail=f"Ollama pull HTTP {res.status_code}: {body or res.reason_phrase}",
                )
            return res.json()
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Ollama pull failed: {str(e)}")


@app.post("/api/models/pull/stream")
async def pull_model_stream(req: PullModelRequest):
    """Pull a model from Ollama with streaming progress (SSE)."""
    import json as _json
    base = normalize_ollama_base(req.host)

    async def generate():
        try:
            async with httpx_lib.AsyncClient(timeout=None, trust_env=False) as client:
                payload = {"model": req.name, "name": req.name, "stream": True}
                async with client.stream("POST", f"{base}/api/pull", json=payload) as resp:
                    if resp.status_code >= 400:
                        body = await resp.aread()
                        yield f"data: {_json.dumps({'type': 'error', 'content': f'HTTP {resp.status_code}: {body.decode()[:300]}'})}\n\n"
                        return
                    async for line in resp.aiter_lines():
                        if not line:
                            continue
                        try:
                            data = _json.loads(line)
                        except Exception:
                            continue
                        status = data.get("status", "")
                        total = data.get("total", 0)
                        completed = data.get("completed", 0)
                        if total > 0:
                            pct = int(completed * 100 / total)
                            mb_done = completed // (1024 * 1024)
                            mb_total = total // (1024 * 1024)
                            yield f"data: {_json.dumps({'type': 'progress', 'status': status, 'pct': pct, 'mb_done': mb_done, 'mb_total': mb_total})}\n\n"
                        else:
                            yield f"data: {_json.dumps({'type': 'progress', 'status': status, 'pct': 0, 'mb_done': 0, 'mb_total': 0})}\n\n"
                        if status == "success":
                            yield f"data: {_json.dumps({'type': 'done'})}\n\n"
                            return
        except Exception as e:
            yield f"data: {_json.dumps({'type': 'error', 'content': str(e)})}\n\n"

    return StreamingResponse(generate(), media_type="text/event-stream")


@app.post("/api/agent/chat")
async def agent_chat(req: AgentChatRequest):
    """Chat with the agentic loop enabled."""
    try:
        deterministic_listing = _build_directory_listing_reply(req.message)
        if deterministic_listing:
            return {"content": deterministic_listing}

        host = normalize_ollama_base(req.remote_host or os.getenv("REMOTE_AI_HOST", OLLAMA_DEFAULT))
        tags = await ollama_fetch_model_tags(host)
        use_model, tag_err = resolve_ollama_model_for_request(req.model, tags)
        if tag_err:
            return {"error": tag_err}
        env = build_agent_environment(host, IVERILOG_PATH, VVP_PATH, VIVADO_PATH)
        
        # Enrich system prompt with context
        ctx = f"\nŞu anki bağlam:\n- Açık dosyalar: {', '.join(req.open_files) if req.open_files else 'Yok'}\n- Aktif dosya: {req.active_file or 'Yok'}\n"
        custom_sys = (req.system_prompt or "") + ctx + "\n" + env["system_block"]

        engine = AgentEngine(
            host=host,
            model=use_model or req.model,
            history=req.history,
            system_prompt=custom_sys,
            api_key=req.api_key or None,
            mode=req.agent_mode or "agent",
            environment_brief=env["user_line"],
        )
        final_response = await engine.run_step(req.message)
        return {"content": final_response}
    except Exception as e:
        return {"error": str(e)}

def _log_connection(request: Request, message: str):
    """Bağlanan istemci IP'sini ve mesajını connections.log'a yazar."""
    try:
        client_ip = request.headers.get("X-Forwarded-For", "").split(",")[0].strip() \
                    or (request.client.host if request.client else "unknown")
        ws = os.getenv("WORKSPACE_DIR", os.path.join(os.getcwd(), "workspace"))
        log_path = os.path.join(ws, "connections.log")
        entry = {
            "ts": datetime.datetime.now().isoformat(timespec="seconds"),
            "ip": client_ip,
            "msg": message[:300],
        }
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(json_lib.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        pass


@app.post("/api/agent/stream")
async def agent_stream(req: AgentChatRequest, request: Request):
    """Stream agent responses via SSE."""
    _log_connection(request, req.message)
    deterministic_listing = _build_directory_listing_reply(req.message)
    if deterministic_listing:
        async def gen_fast_listing():
            yield f"data: {json_lib.dumps({'type': 'thinking', 'content': 'Klasör içeriği doğrudan okunuyor...'}, ensure_ascii=False)}\n\n"
            yield f"data: {json_lib.dumps({'type': 'done', 'content': deterministic_listing}, ensure_ascii=False)}\n\n"
            yield "data: [DONE]\n\n"

        return StreamingResponse(
            gen_fast_listing(),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )

    host = normalize_ollama_base(req.remote_host or os.getenv("REMOTE_AI_HOST", OLLAMA_DEFAULT))

    # ── Auto-detect mode ──────────────────────────────────────────────────────
    gemini_key = req.gemini_key or os.getenv("GEMINI_API_KEY") or None
    regex_mode = detect_mode(req.message)
    # Gemini ile daha doğru mod tespiti (Gemini key varsa, hızlı çağrı)
    if gemini_key and req.agent_mode not in ("ask", "plan", "agent"):
        gemini_mode = await gemini_detect_mode(req.message, gemini_key)
        auto_mode = gemini_mode or regex_mode
    else:
        auto_mode = regex_mode
    # Use explicit mode only if user picked ask/plan/agent deliberately;
    # 'auto' (or any unknown value) means let detect_mode decide.
    mode = req.agent_mode if req.agent_mode in ("ask", "plan", "agent") else auto_mode

    # ── Smart Model Routing ───────────────────────────────────────────────────
    api_key = req.api_key or None
    moonshot_key = req.moonshot_api_key or None
    moonshot_model = req.moonshot_model or "kimi-latest"
    cloud_key_available = bool(api_key) or bool(moonshot_key)
    decision = decide_model(
        message=req.message,
        performance_mode=req.performance_mode or "auto",
        api_key_available=cloud_key_available,
        retry_count=0,
    )

    if moonshot_key:
        # Moonshot key varsa her zaman öncelik ver (smart router'a bakma)
        model_name = moonshot_model
        route_reason = f"Moonshot/{model_name}"
        print(f"[Moonshot] Key present (len={len(moonshot_key)}), model={model_name}")
        provider = MoonshotProvider(api_key=moonshot_key, model=model_name)
    elif decision.is_local:
        model_name = decision.model
        route_reason = decision.reason
        provider = OllamaProvider(host=host, model=model_name, mode=mode)
    else:
        # Fallback: OpenRouter
        model_name = decision.model
        route_reason = decision.reason
        provider = OpenRouterProvider(api_key=api_key, model=model_name)
        if decision.estimated_cost > 0:
            record_spend(model_name, int(decision.max_ctx_tokens))

    # ── Extra context ─────────────────────────────────────────────────────────
    ctx_parts = []
    if req.open_files:
        ctx_parts.append(f"Open files: {', '.join(req.open_files)}")
    if req.active_file:
        ctx_parts.append(f"Active file: {req.active_file}")
    if req.system_prompt:
        ctx_parts.append(req.system_prompt)
    extra_context = "\n".join(ctx_parts) or None

    # ── Create new engine ─────────────────────────────────────────────────────
    session_id = str(uuid.uuid4())
    engine = NewAgentEngine(
        provider=provider,
        message=req.message,
        history=req.history,
        mode=mode,
        extra_context=extra_context,
        session_id=session_id,
        pending_store=_PENDING_SESSIONS,
        model_name=model_name,
        max_ctx_tokens=decision.max_ctx_tokens,
    )

    # ── Activity log ──────────────────────────────────────────────────────────
    _ws = os.getenv("WORKSPACE_DIR", os.path.join(os.getcwd(), "workspace"))
    _log_path = os.path.join(_ws, "activity.log")
    _now = datetime.datetime.now()
    _log_lines: list[str] = [
        f"\n{'─'*60}",
        f"[{_now.strftime('%Y-%m-%d %H:%M:%S')}]  model={model_name}  mod={mode}",
        f"USER: {req.message}",
    ]

    async def generate():
        yield f"data: {json_lib.dumps({'type': 'model_routed', 'model': model_name, 'reason': route_reason, 'task': decision.task_type, 'is_cloud': not decision.is_local}, ensure_ascii=False)}\n\n"

        # ── Gemini Flash açıklaması: ajan çalışmadan önce kullanıcıya bilgi ver ──
        if gemini_key and mode == "agent":
            explain_buf = ""
            async for chunk in gemini_explain_stream(req.message, mode, gemini_key):
                explain_buf += chunk
                yield f"data: {json_lib.dumps({'type': 'explain', 'content': chunk}, ensure_ascii=False)}\n\n"
            if explain_buf:
                yield f"data: {json_lib.dumps({'type': 'explain_done'}, ensure_ascii=False)}\n\n"

        async for event in engine.run_stream(req.message):
            etype = event.get("type", "")
            ts = datetime.datetime.now().strftime("%H:%M:%S")
            if etype == "tool_call":
                _log_lines.append(f"[{ts}] ARAÇ:   {event.get('content', '')}")
            elif etype == "tool_result":
                _log_lines.append(f"[{ts}] SONUÇ:  {event.get('content', '')[:200]}")
            elif etype == "done":
                _log_lines.append(f"[{ts}] AI:     {event.get('content', '')[:300]}")
            elif etype == "error":
                _log_lines.append(f"[{ts}] HATA:   {event.get('content', '')}")
            yield f"data: {json_lib.dumps(event, ensure_ascii=False)}\n\n"
        try:
            os.makedirs(_ws, exist_ok=True)
            with open(_log_path, "a", encoding="utf-8") as lf:
                lf.write("\n".join(_log_lines) + "\n")
        except Exception:
            pass
        yield "data: [DONE]\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"}
    )


class AgentConfirmRequest(BaseModel):
    session_id: str


@app.post("/api/agent/resume")
async def agent_resume(req: AgentConfirmRequest):
    """Confirm pending tool and continue stream."""
    pending = _PENDING_SESSIONS.get(req.session_id)
    if not pending:
        async def _not_found():
            yield f"data: {json_lib.dumps({'type': 'error', 'content': 'Oturum bulunamadı.'}, ensure_ascii=False)}\n\n"
            yield "data: [DONE]\n\n"
        return StreamingResponse(_not_found(), media_type="text/event-stream",
                                 headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})

    engine: NewAgentEngine = pending["engine"]
    iterations = pending["iterations"]

    async def resume_generate():
        async for event in engine.resume_stream(confirmed=True, iterations=iterations):
            yield f"data: {json_lib.dumps(event, ensure_ascii=False)}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(resume_generate(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


@app.post("/api/agent/reject")
async def agent_reject(req: AgentConfirmRequest):
    """Reject pending tool and continue stream with rejection message."""
    pending = _PENDING_SESSIONS.get(req.session_id)
    if not pending:
        return {"ok": True}

    engine: NewAgentEngine = pending["engine"]
    iterations = pending["iterations"]

    async def reject_generate():
        async for event in engine.resume_stream(confirmed=False, iterations=iterations):
            yield f"data: {json_lib.dumps(event, ensure_ascii=False)}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(reject_generate(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


@app.get("/api/health/eda")
async def api_eda_health(host: Optional[str] = None):
    """Icarus (iverilog/vvp), Vivado path, and Ollama reachability (optional host query)."""
    h = normalize_ollama_base(host or os.getenv("REMOTE_AI_HOST", OLLAMA_DEFAULT))
    env = build_agent_environment(h, IVERILOG_PATH, VVP_PATH, VIVADO_PATH)
    return {
        "summary": env["user_line"],
        "ollama": env["parts"]["ollama"],
        "icarus": env["parts"]["icarus"],
        "vivado": env["parts"]["vivado"],
    }


@app.get("/api/agent/plan")
async def api_get_plan():
    """Returns the current adaptive project plan."""
    from services.agent_tools import generate_project_plan
    return {"plan": generate_project_plan()}

@app.post("/api/simulate/auto")
async def api_simulate_auto():
    """Find all .v files in workspace and run simulation automatically."""
    skip = {"__pycache__", "node_modules", ".git", "dist", "_vivado", "_hardware"}
    vfiles = []
    for root, dirs, files in os.walk(WORKSPACE_DIR):
        dirs[:] = [d for d in dirs if d not in skip]
        for f in files:
            if f.endswith(".v") or f.endswith(".sv"):
                vfiles.append(os.path.join(root, f))
    if not vfiles:
        return {"success": False, "log": "Workspace'de .v dosyası bulunamadı."}
    # Prefer testbench as top module
    tb_files = [f for f in vfiles if "testbench" in f.lower() or "_tb" in f.lower()]
    top_module = "tb_top"
    if tb_files:
        name = os.path.splitext(os.path.basename(tb_files[0]))[0]
        top_module = name
    result = simulation.run_simulation(vfiles, top_module)
    return {"success": result.success, "log": result.log, "files": [os.path.relpath(f, WORKSPACE_DIR) for f in vfiles]}


@app.post("/api/simulate")
async def api_simulate(req: SimulateRequest):
    # Ensure file paths are safe (simplified for now)
    resolved_files = []
    for f in req.files:
        path = os.path.join(WORKSPACE_DIR, f)
        if os.path.exists(path):
            resolved_files.append(path)
        else:
            # Fallback to current working directory or provided absolute path
            resolved_files.append(f)
            
    result = simulation.run_simulation(resolved_files, req.top_module)
    return {
        "success": result.success,
        "log": result.log,
        "vcd_available": result.vcd_path is not None
    }


@app.get("/api/budget")
async def api_get_budget():
    """Günlük API bütçe durumunu döndür."""
    from services.smart_router import get_budget_summary, get_today_spend, get_remaining_budget, DAILY_BUDGET_USD
    return {
        "daily_limit": DAILY_BUDGET_USD,
        "spent_today": round(get_today_spend(), 4),
        "remaining": round(get_remaining_budget(), 4),
        "summary": get_budget_summary(),
    }


@app.get("/api/waveform")
async def api_get_waveform(path: str):
    """VCD dosyasını parse edip JSON formatında döndür."""
    from services.vcd_parser import parse_vcd
    import urllib.parse
    decoded = urllib.parse.unquote(path)
    # Güvenlik: workspace veya logs altında olmalı
    safe_roots = [WORKSPACE_DIR, str(Path(__file__).parent / "logs")]
    abs_path = os.path.abspath(decoded)
    if not any(abs_path.startswith(os.path.abspath(r)) for r in safe_roots):
        from fastapi import HTTPException
        raise HTTPException(status_code=403, detail="Dosya erişim izni yok.")
    if not os.path.exists(abs_path):
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="VCD dosyası bulunamadı.")
    result = parse_vcd(abs_path)
    return result


@app.get("/api/vcd/list")
async def api_list_vcds():
    """Workspace altındaki tüm .vcd dosyalarını listele."""
    vcd_files = []
    for root, _, files in os.walk(WORKSPACE_DIR):
        for f in files:
            if f.endswith(".vcd"):
                full = os.path.join(root, f)
                rel = os.path.relpath(full, WORKSPACE_DIR)
                vcd_files.append({"path": full, "name": rel})
    return {"vcds": vcd_files}


@app.get("/api/dataset/stats")
async def api_dataset_stats():
    """Fine-tune dataset istatistiklerini döndür."""
    from services.data_collector import get_stats, get_stats_text
    s = get_stats()
    return {
        "gold": s.get("gold_lines", 0),
        "silver": s.get("silver_lines", 0),
        "error_fixes": s.get("fix_lines", 0),
        "total": s.get("gold_lines", 0) + s.get("silver_lines", 0) + s.get("fix_lines", 0),
        "last_updated": s.get("last_updated", ""),
        "summary": get_stats_text(),
    }


@app.post("/api/chat")
async def api_chat(req: ChatRequest):
    base = normalize_ollama_base(req.remote_host or REMOTE_AI_HOST)
    raw = req.model or ai.model
    tags = await ollama_fetch_model_tags(base)
    use_model, tag_err = resolve_ollama_model_for_request(raw or "", tags)
    if tag_err:
        return {"error": tag_err}
    model = use_model or raw
    ai.update_config(base_url=base, model=model, api_key=None)

    messages: List[Dict[str, str]] = list(req.messages)
    if req.system_prompt and str(req.system_prompt).strip():
        messages = [{"role": "system", "content": req.system_prompt.strip()}] + messages

    response = await ai.chat(messages)
    return response


@app.post("/api/chat/stream")
async def api_chat_stream(req: ChatRequest):
    """Ollama streaming chat (Ask modu)."""
    ollama_base = normalize_ollama_base(req.remote_host or OLLAMA_DEFAULT)
    raw = req.model or ai.model
    tags = await ollama_fetch_model_tags(ollama_base)
    use_model, tag_err = resolve_ollama_model_for_request(raw or "", tags)
    if tag_err:
        async def gen_ask_err():
            yield f"data: {json_lib.dumps({'type': 'error', 'content': tag_err}, ensure_ascii=False)}\n\n"
            yield "data: [DONE]\n\n"

        return StreamingResponse(
            gen_ask_err(),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )

    model = use_model or raw

    messages: List[Dict[str, str]] = list(req.messages)
    if req.system_prompt and str(req.system_prompt).strip():
        messages = [{"role": "system", "content": req.system_prompt.strip()}] + messages

    async def generate():
        accum = ""
        try:
            async with httpx_lib.AsyncClient(timeout=180.0, trust_env=False) as client:
                async with client.stream(
                    "POST",
                    f"{ollama_base}/api/chat",
                    json={"model": model, "messages": messages, "stream": True},
                    headers={"Content-Type": "application/json"},
                ) as res:
                    if res.status_code != 200:
                        body = await res.aread()
                        err = body.decode("utf-8", errors="replace")[:800]
                        yield f"data: {json_lib.dumps({'type': 'error', 'content': f'Ollama HTTP {res.status_code}: {err}'}, ensure_ascii=False)}\n\n"
                        yield "data: [DONE]\n\n"
                        return

                    buf = ""
                    async for chunk in res.aiter_text():
                        buf += chunk
                        while "\n" in buf:
                            line, buf = buf.split("\n", 1)
                            line = line.strip()
                            if not line:
                                continue
                            try:
                                obj = json_lib.loads(line)
                            except json_lib.JSONDecodeError:
                                continue
                            err = obj.get("error")
                            if err:
                                yield f"data: {json_lib.dumps({'type': 'error', 'content': str(err)}, ensure_ascii=False)}\n\n"
                                yield "data: [DONE]\n\n"
                                return
                            piece = (obj.get("message") or {}).get("content") or ""
                            if piece:
                                accum += piece
                                yield f"data: {json_lib.dumps({'type': 'chunk', 'delta': piece, 'text': accum}, ensure_ascii=False)}\n\n"
                            if obj.get("done"):
                                yield f"data: {json_lib.dumps({'type': 'done', 'content': accum}, ensure_ascii=False)}\n\n"
                                yield "data: [DONE]\n\n"
                                return

                    yield f"data: {json_lib.dumps({'type': 'done', 'content': accum}, ensure_ascii=False)}\n\n"
                    yield "data: [DONE]\n\n"
        except Exception as e:
            yield f"data: {json_lib.dumps({'type': 'error', 'content': str(e)}, ensure_ascii=False)}\n\n"
            yield "data: [DONE]\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.get("/api/hardware/ports")
async def api_get_ports():
    return hardware.scan_ports()

class CompileRequest(BaseModel):
    file_path: str
    output_name: str = "program"

@app.post("/api/hardware/compile")
async def api_compile(req: CompileRequest):
    return hardware.compile_c(req.file_path, req.output_name)

class UploadRequest(BaseModel):
    port: str
    baud: int = 115200
    file_path: str

@app.post("/api/hardware/upload")
async def api_upload(req: UploadRequest):
    return hardware.upload_to_serial(req.port, req.baud, req.file_path)

class VivadoBuildRequest(BaseModel):
    files: List[str]
    top_module: str
    part: str = "xc7a35tcpg236-1"

@app.post("/api/vivado/build")
async def api_vivado_build(req: VivadoBuildRequest):
    project_files = [os.path.join(WORKSPACE_DIR, f) for f in req.files]
    tcl_path = vivado.generate_build_tcl(project_files, req.top_module, req.part)
    return vivado.execute_tcl(tcl_path)

class VivadoProgramRequest(BaseModel):
    board: str = "basys3"

@app.post("/api/vivado/program")
async def api_vivado_program(req: VivadoProgramRequest):
    tcl_path = vivado.generate_program_tcl(req.board)
    return vivado.execute_tcl(tcl_path)

@app.post("/api/terminal")
async def run_terminal_command(data: dict):
    """Run any shell command in the workspace directory."""
    import subprocess
    cmd = data.get("command", "").strip()
    if not cmd:
        return {"stdout": "", "stderr": "No command provided.", "returncode": 1}
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=WORKSPACE_DIR, timeout=60)
        return {"stdout": result.stdout, "stderr": result.stderr, "returncode": result.returncode}
    except subprocess.TimeoutExpired:
        return {"stdout": "", "stderr": "Command timed out (60s).", "returncode": 1}
    except Exception as e:
        return {"stdout": "", "stderr": str(e), "returncode": 1}

@app.get("/api/files")
async def api_list_files():
    """List all files in the workspace recursively (Unicode-safe)."""
    all_files = []
    skip_dirs = {'.git', 'node_modules', '__pycache__', '_hardware', '_vivado', '.gemini', 'target', 'build'}
    ws = Path(WORKSPACE_DIR)

    try:
        for root, dirs, files in os.walk(str(ws)):
            root_path = Path(root)
            dirs[:] = [d for d in dirs if d not in skip_dirs and not d.startswith('.')]
            for file in files:
                if file.startswith('.'):
                    continue
                rel = (root_path / file).relative_to(ws)
                all_files.append(unicodedata.normalize("NFC", str(rel).replace(os.sep, '/')))
            for d in dirs:
                rel = (root_path / d).relative_to(ws)
                all_files.append(unicodedata.normalize("NFC", str(rel).replace(os.sep, '/')) + '/')
    except Exception as e:
        print(f"Error walking workspace: {e}")

    return all_files

# Serve the React Frontend (Built version)
# Ensure this folder exists or is copied during Docker build
if os.path.exists("server/static"):
    app.mount("/", StaticFiles(directory="server/static", html=True), name="static")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8001)
