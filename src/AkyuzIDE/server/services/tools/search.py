"""Search tools: grep and glob."""
import os
import re as _re
import glob as _glob
from .shared import get_workspace, resolve_safe_path, SKIP_DIRS

def grep_files(pattern: str, path: str = "", recursive: bool = True) -> str:
    target = resolve_safe_path(path) if path.strip() else get_workspace()
    try:
        compiled = _re.compile(pattern, _re.IGNORECASE)
    except _re.error as e:
        return f"Invalid regex: {e}"
    results = []
    try:
        if os.path.isfile(target):
            file_list = [target]
        elif recursive:
            file_list = []
            for root, dirs, files in os.walk(target):
                dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
                for fname in files:
                    if not fname.startswith("."):
                        file_list.append(os.path.join(root, fname))
        else:
            file_list = [os.path.join(target, f) for f in os.listdir(target)
                         if os.path.isfile(os.path.join(target, f))]
        ws = get_workspace()
        for fpath in file_list[:200]:
            try:
                with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                    for i, line in enumerate(f, 1):
                        if compiled.search(line):
                            rel = os.path.relpath(fpath, ws)
                            results.append(f"{rel}:{i}: {line.rstrip()}")
                            if len(results) >= 100:
                                break
            except Exception:
                pass
            if len(results) >= 100:
                break
        if not results:
            return f"No matches for '{pattern}'"
        out = "\n".join(results)
        if len(results) == 100:
            out += "\n... (truncated at 100 matches)"
        return out
    except Exception as e:
        return f"Error: {e}"

def glob_files(pattern: str) -> str:
    ws = get_workspace()
    full_pattern = os.path.join(ws, pattern)
    try:
        matches = _glob.glob(full_pattern, recursive=True)
        rel = sorted(
            os.path.relpath(m, ws).replace("\\", "/")
            for m in matches
            if not any(p in SKIP_DIRS or p.startswith(".") for p in m.split(os.sep))
        )
        return "\n".join(rel[:100]) if rel else f"No files matching '{pattern}'"
    except Exception as e:
        return f"Error: {e}"
