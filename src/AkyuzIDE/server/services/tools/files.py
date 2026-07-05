"""File operation tools: list, read, write, edit, delete."""
import os
from .shared import get_workspace, resolve_safe_path, find_file_in_workspace, force_remove_tree, SKIP_DIRS

def list_files(path: str = "") -> str:
    target = resolve_safe_path(path) if path.strip() else get_workspace()
    try:
        items = []
        for entry in sorted(os.scandir(target), key=lambda e: (not e.is_dir(), e.name.lower())):
            if entry.name.startswith(".") or entry.name in SKIP_DIRS:
                continue
            prefix = "📁 " if entry.is_dir() else "📄 "
            items.append(f"{prefix}{entry.name}")
        if not items:
            return f"(empty: {path or 'workspace root'})"
        return f"Contents of '{path or 'workspace root'}':\n" + "\n".join(items)
    except Exception as e:
        return f"Error listing '{path}': {e}"

def read_file(path: str) -> str:
    full = resolve_safe_path(path)
    if not os.path.isfile(full):
        found, rel = find_file_in_workspace(path)
        if found == "ambiguous":
            return f"Error: '{os.path.basename(path)}' found in multiple locations. Specify full path."
        elif found:
            full = found
        else:
            return f"Error: file not found: {path}"
    try:
        with open(full, "r", encoding="utf-8") as f:
            content = f.read()
        lines = content.splitlines()
        if len(lines) > 500:
            return "\n".join(f"{i+1:4}: {l}" for i, l in enumerate(lines[:500])) + f"\n\n... ({len(lines)} total lines)"
        return "\n".join(f"{i+1:4}: {l}" for i, l in enumerate(lines))
    except UnicodeDecodeError:
        return f"Error: {path} is a binary file."
    except Exception as e:
        return f"Error reading '{path}': {e}"

def write_file(path: str, content: str) -> str:
    full = resolve_safe_path(path)
    try:
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
        return f"OK: wrote {path} ({len(content.splitlines())} lines)"
    except Exception as e:
        return f"Error writing '{path}': {e}"

def edit_file(path: str, old_str: str = None, new_str: str = None, content: str = None) -> str:
    if content is not None and old_str is None:
        return write_file(path, content)
    if old_str is None or new_str is None:
        return "Error: edit_file requires old_str and new_str"
    full = resolve_safe_path(path)
    if not os.path.isfile(full):
        found, _ = find_file_in_workspace(path)
        if found and found != "ambiguous":
            full = found
        else:
            return f"Error: file not found: {path}"
    try:
        with open(full, "r", encoding="utf-8") as f:
            current = f.read()
        if old_str not in current:
            return f"Error: text not found in {path}. Use read_file to see exact content."
        count = current.count(old_str)
        if count > 1:
            return f"Error: '{old_str[:40]}…' appears {count} times. Provide more context."
        updated = current.replace(old_str, new_str, 1)
        with open(full, "w", encoding="utf-8", newline="\n") as f:
            f.write(updated)
        return f"OK: edited {path}"
    except Exception as e:
        return f"Error editing '{path}': {e}"

def delete_file(path: str) -> str:
    if '*' in path or '?' in path:
        return "Error: wildcards not supported. Use clear_workspace(confirm='yes') to delete all."
    full = os.path.realpath(resolve_safe_path(path))
    ws = os.path.realpath(get_workspace())
    if full == ws:
        return "Error: cannot delete workspace root. Use clear_workspace(confirm='yes')."
    try:
        if os.path.isdir(full):
            force_remove_tree(full)
            return f"OK: deleted directory {path}"
        else:
            import stat as _stat
            try:
                os.remove(full)
            except PermissionError:
                os.chmod(full, _stat.S_IWRITE | _stat.S_IREAD)
                os.remove(full)
            return f"OK: deleted {path}"
    except FileNotFoundError:
        return f"Error: not found: {path}"
    except Exception as e:
        return f"Error deleting '{path}': {e}"
