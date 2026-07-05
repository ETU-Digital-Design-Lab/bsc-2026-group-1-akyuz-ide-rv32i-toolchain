"""Workspace management: clear, create_dir, rename_file, set_workspace_dir."""
import os
import shutil
import unicodedata
from pathlib import Path
from .shared import get_workspace, resolve_safe_path, find_file_in_workspace, force_remove_tree

def clear_workspace(confirm: str = "") -> str:
    ws = get_workspace()
    if confirm.strip().lower() != "yes":
        try:
            items = [e.name for e in os.scandir(ws)]
        except Exception:
            items = []
        if not items:
            return "Workspace is already empty."
        return (f"This will delete {len(items)} item(s). Call with confirm='yes' to proceed.\n"
                f"Items: {', '.join(items)}")
    deleted, errors = [], []
    try:
        for entry in os.scandir(ws):
            try:
                if entry.is_dir(follow_symlinks=False):
                    force_remove_tree(entry.path)
                else:
                    import stat as _stat
                    try:
                        os.remove(entry.path)
                    except PermissionError:
                        os.chmod(entry.path, _stat.S_IWRITE | _stat.S_IREAD)
                        os.remove(entry.path)
                deleted.append(entry.name)
            except Exception as e:
                errors.append(f"{entry.name}: {e}")
    except Exception as e:
        return f"Error scanning workspace: {e}"
    result = f"OK: deleted {len(deleted)} item(s) from workspace."
    if errors:
        result += f"\nFailed ({len(errors)}): " + "; ".join(errors)
    return result

def create_dir(path: str) -> str:
    full = resolve_safe_path(path)
    try:
        os.makedirs(full, exist_ok=True)
        return f"OK: created directory {path}"
    except Exception as e:
        return f"Error creating '{path}': {e}"

def rename_file(old_path: str, new_path: str) -> str:
    old_full = resolve_safe_path(old_path)
    new_full = resolve_safe_path(new_path)
    if not os.path.exists(old_full):
        found, _ = find_file_in_workspace(old_path)
        if found and found != "ambiguous":
            old_full = found
        else:
            return f"Error: source not found: {old_path}"
    try:
        os.makedirs(os.path.dirname(new_full), exist_ok=True)
        shutil.move(old_full, new_full)
        return f"OK: moved {old_path} → {new_path}"
    except Exception as e:
        return f"Error: {e}"

def set_workspace_dir(path: str) -> str:
    raw = unicodedata.normalize("NFC", path.strip().strip('"').strip("'"))
    try:
        ws_root = Path(get_workspace()).resolve()
        # Absolute path given
        try:
            given_abs = Path(raw).resolve()
            if given_abs == ws_root:
                return "OK: Already at workspace root. Proceed with file operations."
            if str(given_abs).startswith(str(ws_root) + os.sep):
                rel = str(given_abs.relative_to(ws_root)).replace("\\", "/")
                os.makedirs(str(given_abs), exist_ok=True)
                return (f"OK: Directory '{rel}' is ready. "
                        f"Use write_file('{rel}/filename.v', ...) for all files. "
                        f"Proceed immediately — write the first file now.")
        except Exception:
            pass
        # Relative path — check if inside workspace
        candidate = (ws_root / raw).resolve()
        if str(candidate).startswith(str(ws_root) + os.sep):
            rel = raw.replace("\\", "/")
            os.makedirs(str(candidate), exist_ok=True)
            return (f"OK: Directory '{rel}' is ready. "
                    f"Use write_file('{rel}/filename.v', ...) for all files. "
                    f"Proceed immediately — write the first file now.")
    except Exception:
        pass

    # Actual workspace switch (Desktop-level folder)
    import unicodedata as _uc
    candidates = [raw]
    try:
        desktop = Path.home() / "Desktop"
        candidates += [str(desktop / raw), str(desktop / _uc.normalize("NFC", raw))]
    except Exception:
        pass
    for cand in candidates:
        if os.path.isdir(cand):
            os.environ["WORKSPACE_DIR"] = cand
            try:
                items = [e.name for e in os.scandir(cand)][:20]
            except Exception:
                items = []
            return (f"OK: Workspace switched to '{cand}'\n"
                    f"Contents ({len(items)} items): {', '.join(items) or '(empty)'}")
    return f"Error: directory not found: '{raw}'. Use full path or create it first."
