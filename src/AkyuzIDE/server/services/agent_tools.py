import os
import re as _re
import glob as _glob
import subprocess
import shutil

from services.vivado import VivadoService
from services.boards import get_board_profile
from services.project_plan_manager import ProjectPlanManager

_DEFAULT_WORKSPACE = os.path.join(os.getcwd(), "workspace")
VIVADO_PATH = os.getenv("VIVADO_PATH", "C:\\Xilinx\\Vivado\\2024.1\\bin\\vivado.bat")
_SKIP_DIRS = {"__pycache__", "node_modules", ".git", "dist", "dist-electron", "target", "build", ".venv", "_vivado", "_hardware"}

vivado_service = VivadoService(
    workspace_dir=os.path.join(os.getenv("WORKSPACE_DIR", _DEFAULT_WORKSPACE), "_vivado"),
    vivado_path=VIVADO_PATH,
)
plan_manager = ProjectPlanManager(workspace_dir=os.getenv("WORKSPACE_DIR", _DEFAULT_WORKSPACE))


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


# ──────────────────────────────────────────────
# FILE TOOLS
# ──────────────────────────────────────────────

def list_files(path: str = "") -> str:
    """List workspace contents. Call with '' for root, or a subdirectory name."""
    target = resolve_safe_path(path) if path.strip() else get_workspace()
    try:
        items = []
        for entry in sorted(os.scandir(target), key=lambda e: (not e.is_dir(), e.name.lower())):
            if entry.name.startswith(".") or entry.name in _SKIP_DIRS:
                continue
            prefix = "📁 " if entry.is_dir() else "📄 "
            items.append(f"{prefix}{entry.name}")
        if not items:
            return f"(empty: {path or 'workspace root'})"
        return f"Contents of '{path or 'workspace root'}':\n" + "\n".join(items)
    except Exception as e:
        return f"Error listing '{path}': {e}"


def _find_file_in_workspace(path: str):
    """Return (full_path, rel_path) by searching workspace if exact path not found."""
    ws = get_workspace()
    full = resolve_safe_path(path)
    if os.path.isfile(full):
        return full, path
    name = os.path.basename(path)
    hits = []
    for root, dirs, files in os.walk(ws):
        dirs[:] = [d for d in dirs if d not in _SKIP_DIRS]
        if name in files:
            hits.append(os.path.join(root, name))
    if len(hits) == 1:
        rel = os.path.relpath(hits[0], ws)
        return hits[0], rel
    return None, None if not hits else "ambiguous"


def read_file(path: str) -> str:
    """Read a file's full content."""
    full = resolve_safe_path(path)
    if not os.path.isfile(full):
        found, rel = _find_file_in_workspace(path)
        if found and found != "ambiguous":
            full = found
        elif found == "ambiguous":
            return f"Error: '{os.path.basename(path)}' found in multiple locations. Specify the full relative path."
        else:
            return f"Error: file not found: {path}. Use list_files to check the correct path."
    try:
        with open(full, "r", encoding="utf-8") as f:
            content = f.read()
        lines = content.splitlines()
        if len(lines) > 500:
            return "\n".join(f"{i+1:4}: {l}" for i, l in enumerate(lines[:500])) + f"\n\n... (truncated — {len(lines)} total lines)"
        return "\n".join(f"{i+1:4}: {l}" for i, l in enumerate(lines))
    except UnicodeDecodeError:
        return f"Error: {path} is a binary file."
    except Exception as e:
        return f"Error reading '{path}': {e}"


def edit_file(path: str, old_str: str = None, new_str: str = None, content: str = None) -> str:
    """Surgical edit: replace old_str with new_str. old_str must be unique in the file."""
    # Model sometimes calls edit_file(path, content=...) instead of write_file — redirect it
    if content is not None and old_str is None:
        return write_file(path, content)
    if old_str is None or new_str is None:
        return "Error: edit_file requires old_str and new_str. Use write_file(path, content) to write full file content."
    full = resolve_safe_path(path)
    if not os.path.isfile(full):
        found, rel = _find_file_in_workspace(path)
        if found and found != "ambiguous":
            full, path = found, rel
        elif found == "ambiguous":
            return f"Error: '{os.path.basename(path)}' found in multiple locations. Specify the full relative path."
        else:
            return f"Error: file not found: {path}. Use list_files to check the correct path."
    try:
        with open(full, "r", encoding="utf-8") as f:
            content = f.read()
        count = content.count(old_str)
        if count == 0:
            snippet = old_str[:60].replace("\n", "\\n")
            return f"Error: text not found in {path}.\nLooking for: '{snippet}'\nUse read_file first to verify exact whitespace and indentation."
        if count > 1:
            return f"Error: text found {count} times in {path} — make old_str more specific."
        new_content = content.replace(old_str, new_str, 1)
        # Verilog dosyası bozuldu mu kontrol et
        if path.endswith((".v", ".sv")) and "module " not in new_content:
            return (
                f"Error: edit aborted — result would remove all 'module' declarations from {path}. "
                f"Use write_file to rewrite the complete file including the module header."
            )
        with open(full, "w", encoding="utf-8") as f:
            f.write(new_content)
        return f"OK: edited {path}"
    except Exception as e:
        return f"Error editing '{path}': {e}"


def write_file(path: str, content: str) -> str:
    """Write (or create) a file with the given content."""
    full = resolve_safe_path(path)
    try:
        os.makedirs(os.path.dirname(full) or ".", exist_ok=True)
        with open(full, "w", encoding="utf-8") as f:
            f.write(content)
        return f"OK: wrote {path} ({len(content.splitlines())} lines)"
    except Exception as e:
        return f"Error writing '{path}': {e}"


def delete_file(path: str) -> str:
    """Delete a file or directory (not the workspace root itself)."""
    # Wildcard kullanımını engelle
    if '*' in path or '?' in path:
        return (
            "Error: wildcard paths are not supported in delete_file. "
            "Tüm içeriği silmek için clear_workspace(confirm='yes') kullan. "
            "Tek tek silmek için önce list_files() ile dosyaları gör, sonra her biri için delete_file() çağır."
        )
    full = os.path.realpath(resolve_safe_path(path))
    ws = os.path.realpath(get_workspace())
    if full == ws:
        return (
            "Error: cannot delete the workspace root directory. "
            "Use clear_workspace(confirm='yes') to delete all its contents instead."
        )
    try:
        if os.path.isdir(full):
            _force_remove_tree(full)
            return f"OK: deleted directory {path}"
        else:
            try:
                os.remove(full)
            except PermissionError:
                import stat
                os.chmod(full, stat.S_IWRITE | stat.S_IREAD)
                os.remove(full)
            return f"OK: deleted {path}"
    except FileNotFoundError:
        return f"Error: not found: {path}"
    except PermissionError as e:
        return f"Error deleting '{path}': permission denied — {e}"
    except Exception as e:
        return f"Error deleting '{path}': {e}"


def _force_remove_tree(path: str) -> None:
    """Remove a directory tree, forcing read-only/ACL-restricted files on Windows."""
    import stat
    import subprocess
    import sys

    def _on_error(func, fpath, exc_info):
        try:
            os.chmod(fpath, stat.S_IWRITE | stat.S_IREAD)
            func(fpath)
        except Exception:
            pass

    # First attempt: standard rmtree with chmod fallback
    try:
        shutil.rmtree(path, onerror=_on_error)
    except Exception:
        pass

    if not os.path.exists(path):
        return

    if sys.platform == "win32":
        # Take ownership + grant full control, then force-remove
        try:
            subprocess.run(
                ["takeown", "/f", path, "/r", "/d", "y"],
                capture_output=True, timeout=15
            )
            subprocess.run(
                ["icacls", path, "/grant", "Everyone:F", "/t", "/c", "/q"],
                capture_output=True, timeout=15
            )
        except Exception:
            pass

        # Now try rmtree again
        try:
            shutil.rmtree(path, onerror=_on_error)
        except Exception:
            pass

        # Final fallback: PowerShell Remove-Item
        if os.path.exists(path):
            try:
                subprocess.run(
                    ["powershell", "-NoProfile", "-Command",
                     f"Remove-Item -LiteralPath '{path}' -Recurse -Force -ErrorAction SilentlyContinue"],
                    capture_output=True, timeout=30
                )
            except Exception:
                pass


def clear_workspace(confirm: str = "") -> str:
    """Delete ALL contents of the workspace (files + subdirs). The workspace folder itself stays.
    Pass confirm='yes' to execute."""
    ws = get_workspace()  # auto-creates if missing
    if confirm.strip().lower() != "yes":
        try:
            items = [e.name for e in os.scandir(ws)]
        except Exception:
            items = []
        if not items:
            return "Workspace is already empty. Nothing to delete."
        return (
            f"This will delete {len(items)} item(s) from workspace. "
            f"Call again with confirm='yes' to proceed.\n"
            f"Items: {', '.join(items)}"
        )
    ws = get_workspace()
    deleted, errors = [], []
    try:
        for entry in os.scandir(ws):
            try:
                if entry.is_dir(follow_symlinks=False):
                    _force_remove_tree(entry.path)
                else:
                    try:
                        os.remove(entry.path)
                    except PermissionError:
                        import stat
                        os.chmod(entry.path, stat.S_IWRITE | stat.S_IREAD)
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
    """Create a directory (including parents)."""
    full = resolve_safe_path(path)
    try:
        os.makedirs(full, exist_ok=True)
        return f"OK: created directory {path}"
    except Exception as e:
        return f"Error creating directory '{path}': {e}"


def rename_file(old_path: str, new_path: str) -> str:
    """Rename or move a file/directory within the workspace."""
    old_full = resolve_safe_path(old_path)
    new_full = resolve_safe_path(new_path)
    if not os.path.exists(old_full):
        found, rel = _find_file_in_workspace(old_path)
        if found and found != "ambiguous":
            old_full = found
        else:
            return f"Error: source not found: {old_path}"
    try:
        os.makedirs(os.path.dirname(new_full), exist_ok=True)
        shutil.move(old_full, new_full)
        return f"OK: moved {old_path} → {new_path}"
    except Exception as e:
        return f"Error renaming '{old_path}': {e}"


# ──────────────────────────────────────────────
# SEARCH TOOLS
# ──────────────────────────────────────────────

def grep_files(pattern: str, path: str = "", recursive: bool = True) -> str:
    """Search for a text/regex pattern in workspace files."""
    target = resolve_safe_path(path) if path.strip() else get_workspace()
    results = []
    try:
        compiled = _re.compile(pattern, _re.IGNORECASE)
    except _re.error as e:
        return f"Invalid regex: {e}"
    try:
        if os.path.isfile(target):
            file_list = [target]
        elif recursive:
            file_list = []
            for root, dirs, files in os.walk(target):
                dirs[:] = [d for d in dirs if d not in _SKIP_DIRS and not d.startswith(".")]
                for fname in files:
                    if not fname.startswith("."):
                        file_list.append(os.path.join(root, fname))
        else:
            file_list = [os.path.join(target, f) for f in os.listdir(target)
                         if os.path.isfile(os.path.join(target, f))]

        for fpath in file_list[:200]:
            try:
                with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                    for i, line in enumerate(f, 1):
                        if compiled.search(line):
                            rel = os.path.relpath(fpath, get_workspace())
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
            out += "\n... (output truncated at 100 matches)"
        return out
    except Exception as e:
        return f"Error: {e}"


def glob_files(pattern: str) -> str:
    """Find files matching a glob pattern (e.g. '**/*.v', 'src/*.ts')."""
    ws = get_workspace()
    full_pattern = os.path.join(ws, pattern)
    try:
        matches = _glob.glob(full_pattern, recursive=True)
        rel_matches = sorted(
            os.path.relpath(m, ws).replace("\\", "/")
            for m in matches
            if not any(part in _SKIP_DIRS or part.startswith(".") for part in m.split(os.sep))
        )
        if not rel_matches:
            return f"No files matching '{pattern}'"
        return "\n".join(rel_matches[:100])
    except Exception as e:
        return f"Error: {e}"


# ──────────────────────────────────────────────
# SHELL
# ──────────────────────────────────────────────

def run_command(command: str) -> str:
    """Run a shell command in the workspace directory. Use forward slashes or single backslashes in paths."""
    ws = get_workspace()
    # Normalize double-backslash escapes that appear from JSON serialization
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


# ──────────────────────────────────────────────
# VERILOG / EDA
# ──────────────────────────────────────────────

IVERILOG = os.getenv("IVERILOG_PATH", r"C:\iverilog\bin\iverilog.exe")
VVP = os.getenv("VVP_PATH", r"C:\iverilog\bin\vvp.exe")


def compile_verilog(files: list) -> str:
    ws = get_workspace()
    resolved = [resolve_safe_path(f) for f in files]
    quoted = " ".join(f'"{r}"' for r in resolved)
    cmd = f'"{IVERILOG}" -g2012 -o sim.out {quoted}'
    try:
        result = subprocess.run(cmd, shell=True, cwd=ws, capture_output=True, text=True, timeout=60)
        if result.returncode != 0:
            return f"COMPILATION FAILED:\n{result.stderr}"
        return "COMPILATION SUCCESSFUL. Binary: sim.out"
    except Exception as e:
        return f"Error: {e}"


def run_simulation(files: list) -> str:
    result = compile_verilog(files)
    if "FAILED" in result:
        return result
    ws = get_workspace()
    try:
        r = subprocess.run(f'"{VVP}" sim.out', shell=True, cwd=ws, capture_output=True, text=True, timeout=30)
        out = f"{r.stdout}\n{r.stderr}".strip()

        # Simülasyon çıktısını proje klasörüne kaydet
        # Testbench dosyasından proje klasörünü çıkar
        log_dir = ws
        if files:
            tb = next((f for f in files if 'tb' in os.path.basename(f).lower()), files[0])
            tb_dir = os.path.dirname(resolve_safe_path(tb))
            if os.path.isdir(tb_dir):
                log_dir = tb_dir
        log_path = os.path.join(log_dir, "simulation.log")
        try:
            with open(log_path, "w", encoding="utf-8") as lf:
                lf.write(out)
        except Exception:
            pass

        return f"SIMULATION OUTPUT:\n{out}"
    except Exception as e:
        return f"Error: {e}"


def check_vivado() -> str:
    """Check Vivado availability and project status."""
    if not os.path.exists(VIVADO_PATH):
        return f"ERROR: Vivado not found at {VIVADO_PATH}\nSet VIVADO_PATH environment variable to the correct path."
    try:
        r = subprocess.run(
            f'"{VIVADO_PATH}" -version',
            shell=True, capture_output=True, text=True, timeout=30
        )
        ver = next((l.strip() for l in r.stdout.splitlines() if "Vivado" in l), "version unknown")
        proj_xpr = vivado_service.project_dir / f"{vivado_service.project_name}.xpr"
        proj_status = "EXISTS (previous build available)" if proj_xpr.exists() else "NOT CREATED"
        return f"Vivado: {ver}\nProject: {proj_status}\nProject dir: {vivado_service.project_dir}"
    except Exception as e:
        return f"Vivado check error: {e}"


def prepare_vivado_build(files: list, top_module: str, board: str = "basys3") -> str:
    """Prepare Vivado build TCL. Returns the TCL script path to pass to run_vivado_flow."""
    profile = get_board_profile(board)
    resolved = []
    for f in files:
        full = resolve_safe_path(f)
        if os.path.exists(full):
            resolved.append(full)
        else:
            found, _ = _find_file_in_workspace(f)
            if found and found != "ambiguous":
                resolved.append(found)
    if not resolved:
        return f"Error: no valid files found from {files}"
    xdc_list = [f for f in resolved if f.endswith(".xdc")]
    tcl_path = vivado_service.generate_build_tcl(resolved, top_module, profile["part"])
    xdc_note = f"XDC: {len(xdc_list)} file(s)" if xdc_list else "WARNING: No XDC file — use generate_xdc() first"
    return (
        f"TCL ready: {tcl_path}\n"
        f"Board: {profile['name']} ({profile['part']})\n"
        f"Files: {len(resolved)} source(s)  {xdc_note}\n"
        f"Run: run_vivado_flow(\"{tcl_path}\")"
    )


def run_vivado_flow(tcl_script_path: str) -> str:
    """Run Vivado: synthesis → implementation → bitstream. Takes 10-40 min."""
    path = tcl_script_path.strip("\"'")
    if not os.path.exists(path):
        return f"Error: TCL not found: {path}\nCall prepare_vivado_build() first."
    result = vivado_service.execute_tcl(path)
    s = vivado_service.parse_vivado_log(result["log"])
    log_path = str(vivado_service.workspace_dir / "vivado.log")

    if result["success"] and s["status"] == "Success":
        util = s.get("utilization", {})
        lines = [
            "VIVADO BUILD SUCCESSFUL",
            f"Synthesis: OK  Implementation: OK",
            f"Resources — LUTs: {util.get('LUTs','N/A')}  FFs: {util.get('FFs','N/A')}  BRAM: {util.get('BRAM','N/A')}  DSPs: {util.get('DSPs','N/A')}",
            f"Timing: {s.get('timing','N/A')}",
            f"Log: {log_path}",
            "Next: read_vivado_reports() for details, then program_fpga()",
        ]
        return "\n".join(lines)

    # Failure — extract first 10 errors
    error_lines = [f"  {e}" for e in s.get("errors", [])][:10]
    crit_warn = [f"  {w}" for w in s.get("warnings", [])][:5]
    lines = [
        f"VIVADO BUILD FAILED (synth={'OK' if s['synth_done'] else 'FAILED'}, impl={'OK' if s['impl_done'] else 'FAILED'})",
    ]
    if error_lines:
        lines.append("Errors:")
        lines.extend(error_lines)
    if crit_warn:
        lines.append("Critical warnings:")
        lines.extend(crit_warn)
    lines.append(f"Log: {log_path}")
    return "\n".join(lines)


def read_vivado_reports() -> str:
    """Read synthesis/implementation reports from the last Vivado build."""
    return vivado_service.read_reports()


def program_fpga(board: str = "basys3") -> str:
    """Program connected FPGA with the last built bitstream."""
    tcl_path = vivado_service.generate_program_tcl(board)
    result = vivado_service.execute_tcl(tcl_path)
    log = result["log"]
    if "AKYUZ_PROGRAM_SUCCESS" in log:
        return "FPGA PROGRAMMED SUCCESSFULLY."
    if "AKYUZ_PROGRAM_ERROR" in log:
        m = _re.search(r"AKYUZ_PROGRAM_ERROR: (.+)", log)
        return f"PROGRAMMING ERROR: {m.group(1) if m else 'unknown'}"
    errors = [l for l in log.splitlines() if "ERROR:" in l][:5]
    return f"PROGRAMMING FAILED:\n" + "\n".join(errors) if errors else f"PROGRAMMING FAILED:\n{log[:400]}"


def generate_xdc(path: str, board: str, clk_port: str = "clk",
                 led_ports: list = None, sw_ports: list = None,
                 extra: str = "") -> str:
    """Generate an XDC constraints file mapping design ports to FPGA board pins."""
    profile = get_board_profile(board)
    pins = profile["pins"]
    lines = [
        f"## AkyuzIDE generated XDC — {profile['name']} ({profile['part']})",
        "",
        "## Clock",
    ]
    if clk_port and "clk" in pins:
        lines += [
            f"set_property PACKAGE_PIN {pins['clk']} [get_ports {clk_port}]",
            f"set_property IOSTANDARD LVCMOS33 [get_ports {clk_port}]",
            f"create_clock -add -name sys_clk_pin -period 10.00 -waveform {{0 5}} [get_ports {clk_port}]",
            "",
        ]
    if led_ports:
        pin_list = pins.get("led", [])
        if isinstance(pin_list, str):
            pin_list = [pin_list]
        lines.append("## LEDs")
        for i, port in enumerate(led_ports):
            if i < len(pin_list):
                lines += [
                    f"set_property PACKAGE_PIN {pin_list[i]} [get_ports {{{port}}}]",
                    f"set_property IOSTANDARD LVCMOS33 [get_ports {{{port}}}]",
                ]
        lines.append("")
    if sw_ports:
        pin_list = pins.get("sw", [])
        if isinstance(pin_list, str):
            pin_list = [pin_list]
        lines.append("## Switches")
        for i, port in enumerate(sw_ports):
            if i < len(pin_list):
                lines += [
                    f"set_property PACKAGE_PIN {pin_list[i]} [get_ports {{{port}}}]",
                    f"set_property IOSTANDARD LVCMOS33 [get_ports {{{port}}}]",
                ]
        lines.append("")
    if extra:
        lines += ["## Additional", extra, ""]
    return write_file(path, "\n".join(lines))


def get_board_info(board_name: str) -> str:
    """Get FPGA board pin assignments and XDC examples."""
    profile = get_board_profile(board_name)
    pins = profile["pins"]
    lines = [
        f"Board: {profile['name']}",
        f"Part:  {profile['part']}",
        "",
        "Pin assignments:",
    ]
    if "clk" in pins:
        lines.append(f"  clk     -> {pins['clk']}")
    for sig in ("led", "sw"):
        p = pins.get(sig, [])
        pl = p if isinstance(p, list) else [p]
        for i, pin in enumerate(pl[:16]):
            lines.append(f"  {sig}[{i:2d}] -> {pin}")
    for btn in ("btn_c", "btn_u", "btn_d", "btn_l", "btn_r"):
        if btn in pins:
            lines.append(f"  {btn}  -> {pins[btn]}")
    clk_pin = pins.get("clk", "W5")
    lines += [
        "",
        "XDC example (clock):",
        f"  set_property PACKAGE_PIN {clk_pin} [get_ports clk]",
        f"  set_property IOSTANDARD LVCMOS33 [get_ports clk]",
        f"  create_clock -add -name sys_clk_pin -period 10.00 -waveform {{0 5}} [get_ports clk]",
        "",
        "Use generate_xdc() to auto-generate the full constraints file.",
    ]
    return "\n".join(lines)


def get_vivado_full_log(log_path: str) -> str:
    try:
        with open(log_path, "r", encoding="utf-8") as f:
            return f.read()
    except Exception as e:
        return f"Error: {e}"


def generate_project_plan() -> str:
    return plan_manager.generate_plan_markdown()


def set_workspace_dir(path: str) -> str:
    """Change the active workspace directory. Use when user asks to work in a specific folder."""
    import unicodedata as _uc
    from pathlib import Path as _P

    raw = _uc.normalize("NFC", path.strip().strip('"').strip("'"))

    # Workspace root veya alt klasöre geçişi engelle
    try:
        ws_root = _P(get_workspace()).resolve()

        # Tam path verilmişse (drive letter içeren) direkt karşılaştır
        try:
            given_abs = _P(raw).resolve()
            if given_abs == ws_root:
                return "OK: Already at workspace root. Proceed with your file operations directly."
            if str(given_abs).startswith(str(ws_root) + os.sep) or str(given_abs).startswith(str(ws_root) + "/"):
                rel = str(given_abs.relative_to(ws_root)).replace("\\", "/")
                os.makedirs(str(given_abs), exist_ok=True)
                return (
                    f"OK: Directory '{rel}' is ready. "
                    f"Use write_file('{rel}/filename.v', ...) for all files in this project. "
                    f"Proceed immediately — write the first file now."
                )
        except Exception:
            pass

        # Göreli isim verilmişse workspace altında ara
        candidate_inside = (ws_root / raw).resolve()
        if str(candidate_inside).startswith(str(ws_root) + os.sep) or str(candidate_inside).startswith(str(ws_root) + "/"):
            rel = raw.replace("\\", "/")
            os.makedirs(str(candidate_inside), exist_ok=True)
            return (
                f"OK: Directory '{rel}' is ready. "
                f"Use write_file('{rel}/filename.v', ...) for all files in this project. "
                f"Proceed immediately — write the first file now."
            )
    except Exception:
        pass

    # Try the path as-is first, then search Desktop/common locations
    candidates = [raw]
    try:
        # Alt klasör olarak workspace içinde ara (en yaygın kullanım)
        ws = get_workspace()
        candidates += [
            str(_P(ws) / raw),
        ]
        desktop = _P.home() / "Desktop"
        candidates += [
            str(desktop / raw),
            str(desktop / _uc.normalize("NFC", raw)),
        ]
    except Exception:
        pass

    resolved = None
    for c in candidates:
        try:
            p = _P(c)
            if p.exists() and p.is_dir():
                resolved = str(p)
                break
        except Exception:
            continue

    # Fuzzy component-wise walk for Turkish ı/İ
    if not resolved:
        for c in candidates:
            try:
                parts = _P(c).parts
                if not parts:
                    continue
                cur = _P(parts[0])
                ok = True
                for part in parts[1:]:
                    if not cur.is_dir():
                        ok = False; break
                    children = [x.name for x in cur.iterdir()]
                    match = next((ch for ch in children if _uc.normalize("NFC", ch).lower() == _uc.normalize("NFC", part).lower()), None)
                    if match:
                        cur = cur / match
                    else:
                        ok = False; break
                if ok and cur.exists():
                    resolved = str(cur)
                    break
            except Exception:
                continue

    if not resolved:
        return f"Error: directory not found: {path}. Provide the full path or ensure the folder exists."

    os.environ["WORKSPACE_DIR"] = resolved
    # Update vivado service and plan manager to new workspace
    vivado_service.workspace_dir = str(_P(resolved) / "_vivado")
    vivado_service.project_dir   = _P(resolved) / "_vivado" / vivado_service.project_name
    plan_manager.workspace_dir   = resolved
    return f"OK: workspace changed to {resolved}"


# ──────────────────────────────────────────────
# REGISTRY
# ──────────────────────────────────────────────

AGENT_TOOLS = {
    # File ops
    "list_files": list_files,
    "read_file": read_file,
    "edit_file": edit_file,
    "write_file": write_file,
    "delete_file": delete_file,
    "create_dir": create_dir,
    "rename_file": rename_file,
    # Search
    "grep_files": grep_files,
    "glob_files": glob_files,
    # Shell
    "run_command": run_command,
    # EDA / Icarus
    "compile_verilog": compile_verilog,
    "run_simulation": run_simulation,
    # Vivado
    "check_vivado": check_vivado,
    "get_board_info": get_board_info,
    "generate_xdc": generate_xdc,
    "prepare_vivado_build": prepare_vivado_build,
    "run_vivado_flow": run_vivado_flow,
    "read_vivado_reports": read_vivado_reports,
    "get_vivado_full_log": get_vivado_full_log,
    "program_fpga": program_fpga,
    # Project
    "generate_project_plan": generate_project_plan,
    # Workspace
    "set_workspace_dir": set_workspace_dir,
    "clear_workspace": clear_workspace,
}

PLAN_TOOL_NAMES = {"list_files", "read_file", "grep_files", "glob_files", "get_board_info", "check_vivado", "read_vivado_reports", "generate_project_plan", "get_vivado_full_log", "set_workspace_dir"}

# ──────────────────────────────────────────────
# OLLAMA NATIVE TOOL CALLING SCHEMAS
# ──────────────────────────────────────────────

def _fn(name: str, description: str, properties: dict, required: list = None) -> dict:
    return {
        "type": "function",
        "function": {
            "name": name,
            "description": description,
            "parameters": {
                "type": "object",
                "properties": properties,
                "required": required or [],
            },
        },
    }

_STR = {"type": "string"}
_STRLIST = {"type": "array", "items": {"type": "string"}}

TOOLS_SCHEMA: list = [
    # ── File ops ──
    _fn("list_files", "List files and directories in the workspace. Use '' for root. Always explore before reading.", {"path": {**_STR, "default": ""}}, []),
    _fn("read_file", "Read a file's complete content with line numbers.", {"path": _STR}, ["path"]),
    _fn("edit_file", "Surgical edit: replace old_str with new_str. Must match exactly (whitespace included). Prefer over write_file.",
        {"path": _STR, "old_str": _STR, "new_str": _STR}, ["path", "old_str", "new_str"]),
    _fn("write_file", "Write complete content to a file (creates if missing). Use for new files.",
        {"path": _STR, "content": _STR}, ["path", "content"]),
    _fn("delete_file", "Delete a single file or directory. Cannot delete the workspace root.", {"path": _STR}, ["path"]),
    _fn("clear_workspace",
        "Delete ALL contents of the workspace (files + subdirs). The workspace folder itself stays. "
        "ALWAYS call with confirm='yes'. Use whenever user says 'temizle', 'sil hepsini', 'clear workspace', 'workspace temizle'.",
        {"confirm": {**_STR, "description": "Must be 'yes' to execute"}}, ["confirm"]),
    _fn("create_dir", "Create a directory (and parents).", {"path": _STR}, ["path"]),
    _fn("rename_file", "Rename or move a file/directory within workspace.", {"old_path": _STR, "new_path": _STR}, ["old_path", "new_path"]),
    # ── Search ──
    _fn("grep_files", "Search for a text/regex pattern in files. Returns file:line matches.",
        {"pattern": _STR, "path": {**_STR, "default": ""}, "recursive": {"type": "boolean", "default": True}}, ["pattern"]),
    _fn("glob_files", "Find files by glob pattern (e.g. '**/*.v', 'src/*.ts').", {"pattern": _STR}, ["pattern"]),
    # ── Shell ──
    _fn("run_command", "Run a shell command in workspace directory.", {"command": _STR}, ["command"]),
    # ── EDA / Icarus ──
    _fn("compile_verilog", "Compile Verilog files with iverilog. Returns errors or success.", {"files": _STRLIST}, ["files"]),
    _fn("run_simulation", "Compile + run Verilog simulation with iverilog+vvp. Returns stdout/stderr.", {"files": _STRLIST}, ["files"]),
    # ── Vivado ──
    _fn("check_vivado", "Check if Vivado is installed and return version + project status. Call before any Vivado step.", {}, []),
    _fn("get_board_info", "Get FPGA board part number and pin assignments for XDC generation.",
        {"board_name": {**_STR, "description": "Board ID: basys3 | arty_a7_35t | nexys_a7_100t"}}, ["board_name"]),
    _fn("generate_xdc", "Generate XDC constraints file mapping design ports to board pins.",
        {
            "path": {**_STR, "description": "Output path e.g. 'cpu/constraints.xdc'"},
            "board": {**_STR, "description": "Board ID: basys3 | arty_a7_35t | nexys_a7_100t"},
            "clk_port": {**_STR, "default": "clk", "description": "Clock port name in your design"},
            "led_ports": {**_STRLIST, "description": "LED port names e.g. ['led[0]','led[1]']"},
            "sw_ports": {**_STRLIST, "description": "Switch port names e.g. ['sw[0]','sw[1]']"},
            "extra": {**_STR, "default": "", "description": "Extra raw XDC lines to append"},
        }, ["path", "board"]),
    _fn("prepare_vivado_build",
        "Prepare Vivado build TCL script. Returns the TCL path to pass to run_vivado_flow.",
        {"files": _STRLIST, "top_module": _STR, "board": {**_STR, "default": "basys3"}}, ["files", "top_module"]),
    _fn("run_vivado_flow",
        "Run Vivado: synthesis → implementation → bitstream. Takes 10-40 min. Pass the TCL path from prepare_vivado_build.",
        {"tcl_script_path": _STR}, ["tcl_script_path"]),
    _fn("read_vivado_reports",
        "Read synthesis/implementation reports after run_vivado_flow completes. Shows LUT/FF usage and timing.", {}, []),
    _fn("get_vivado_full_log", "Read full Vivado log file (path returned by run_vivado_flow).", {"log_path": _STR}, ["log_path"]),
    _fn("program_fpga", "Program the connected FPGA with the last built bitstream. REQUIRES USER CONFIRMATION.",
        {"board": {**_STR, "default": "basys3"}}, []),
    # ── Project ──
    _fn("generate_project_plan", "Generate Markdown project plan from workspace state.", {}, []),
    # ── Workspace ──
    _fn("set_workspace_dir",
        "Change active workspace to a different folder. Call this FIRST when user asks to work in a specific folder by name or path.",
        {"path": {**_STR, "description": "Folder name (e.g. 'akyuzide_ilkdeneme') or full path (e.g. 'C:\\\\Users\\\\Taha\\\\Desktop\\\\akyuzide')"}},
        ["path"]),
]

PLAN_TOOLS_SCHEMA = [t for t in TOOLS_SCHEMA if t["function"]["name"] in PLAN_TOOL_NAMES]

# ──────────────────────────────────────────────
# TEXT-BASED TOOL CALLING DESCRIPTIONS (fallback)
# ──────────────────────────────────────────────

TOOL_DOCS = {
    "list_files":           "list_files(path=''):         List workspace directory.",
    "read_file":            "read_file(path):              Read file with line numbers.",
    "edit_file":            "edit_file(path, old_str, new_str): Surgical edit (unique match).",
    "write_file":           "write_file(path, content):   Write/create a file.",
    "delete_file":          "delete_file(path):            Delete a single file or directory (not workspace root).",
    "clear_workspace":      "clear_workspace(confirm='yes'): Delete ALL workspace contents at once. ALWAYS use this (never delete_file in a loop) when user says 'temizle', 'sil hepsini', 'clear', 'workspace temizle'.",
    "create_dir":           "create_dir(path):             Create directory.",
    "rename_file":          "rename_file(old_path, new_path): Rename/move file.",
    "grep_files":           "grep_files(pattern, path='', recursive=True): Regex search.",
    "glob_files":           "glob_files(pattern):          Find files by glob.",
    "run_command":          "run_command(command):          Run shell command in workspace.",
    "compile_verilog":      "compile_verilog(files):        Compile Verilog with iverilog.",
    "run_simulation":       "run_simulation(files):         Compile + simulate (iverilog+vvp).",
    "check_vivado":         "check_vivado():                Check Vivado is available + project status.",
    "get_board_info":       "get_board_info(board_name):    Get FPGA pin map (basys3/arty_a7_35t/nexys_a7_100t).",
    "generate_xdc":         "generate_xdc(path, board, clk_port, led_ports, sw_ports): Generate XDC.",
    "prepare_vivado_build": "prepare_vivado_build(files, top_module, board='basys3'): Prepare build TCL.",
    "run_vivado_flow":      "run_vivado_flow(tcl_script_path): Run Vivado synth→impl→bitstream.",
    "read_vivado_reports":  "read_vivado_reports():         Read synthesis/timing reports.",
    "get_vivado_full_log":  "get_vivado_full_log(log_path): Read full Vivado log file.",
    "program_fpga":         "program_fpga(board='basys3'):  Program FPGA with bitstream.",
    "generate_project_plan":"generate_project_plan():       Generate Markdown project plan.",
    "set_workspace_dir":    "set_workspace_dir(path):       Switch active workspace to a folder by name or full path.",
}


def format_tool_descriptions(tool_names: list) -> str:
    return "\n".join(f"{i+1}. {TOOL_DOCS[n]}" for i, n in enumerate(tool_names) if n in TOOL_DOCS)


TOOL_DESCRIPTIONS = format_tool_descriptions(list(AGENT_TOOLS.keys()))
