"""Shared utilities: workspace path resolution, force-delete helpers."""
import os
import sys
import stat
import shutil
import subprocess

_DEFAULT_WORKSPACE = os.path.join(os.getcwd(), "workspace")
SKIP_DIRS = {"__pycache__", "node_modules", ".git", "dist", "dist-electron",
             "target", "build", ".venv", "_vivado", "_hardware"}

def get_workspace() -> str:
    ws = os.getenv("WORKSPACE_DIR", _DEFAULT_WORKSPACE)
    os.makedirs(ws, exist_ok=True)
    return ws

def resolve_safe_path(path: str) -> str:
    ws = get_workspace()
    clean = path.lstrip("/\\")
    if clean.startswith("workspace/") or clean.startswith("workspace\\"):
        clean = clean[len("workspace/"):].lstrip("/\\")
    return os.path.join(ws, clean)

def force_remove_tree(path: str) -> None:
    """Remove directory tree, handling read-only and ACL-restricted files on Windows."""
    def _on_error(func, fpath, exc_info):
        try:
            os.chmod(fpath, stat.S_IWRITE | stat.S_IREAD)
            func(fpath)
        except Exception:
            pass

    try:
        shutil.rmtree(path, onerror=_on_error)
    except Exception:
        pass

    if not os.path.exists(path):
        return

    if sys.platform == "win32":
        try:
            subprocess.run(["takeown", "/f", path, "/r", "/d", "y"], capture_output=True, timeout=15)
            subprocess.run(["icacls", path, "/grant", "Everyone:F", "/t", "/c", "/q"], capture_output=True, timeout=15)
        except Exception:
            pass
        try:
            shutil.rmtree(path, onerror=_on_error)
        except Exception:
            pass
        if os.path.exists(path):
            try:
                subprocess.run(
                    ["powershell", "-NoProfile", "-Command",
                     f"Remove-Item -LiteralPath '{path}' -Recurse -Force -ErrorAction SilentlyContinue"],
                    capture_output=True, timeout=30
                )
            except Exception:
                pass

def find_file_in_workspace(path: str):
    """Return (full_path, rel_path) by searching workspace. Returns (None,None) if not found."""
    ws = get_workspace()
    full = resolve_safe_path(path)
    if os.path.isfile(full):
        return full, path
    name = os.path.basename(path)
    hits = []
    for root, dirs, files in os.walk(ws):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        if name in files:
            hits.append(os.path.join(root, name))
    if len(hits) == 1:
        return hits[0], os.path.relpath(hits[0], ws)
    if len(hits) > 1:
        return "ambiguous", None
    return None, None
