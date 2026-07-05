"""Shell command execution."""
import os
import subprocess
from .shared import get_workspace

def run_command(command: str) -> str:
    ws = get_workspace()
    command = command.replace("\\\\", "\\")
    try:
        result = subprocess.run(
            command, shell=True, cwd=ws,
            capture_output=True, text=True, timeout=120,
            encoding="utf-8", errors="replace",
        )
        out = f"$ {command}\n"
        if result.stdout:
            out += result.stdout
        if result.stderr:
            out += result.stderr
        if result.returncode != 0:
            out += f"\n[exit code {result.returncode}]"
        return out.strip() or "(no output)"
    except subprocess.TimeoutExpired:
        return "Error: command timed out after 120s"
    except Exception as e:
        return f"Error: {e}"
