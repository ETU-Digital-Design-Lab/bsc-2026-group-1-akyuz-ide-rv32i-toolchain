"""Tool registry: schemas, handlers, risk levels, and mode permissions."""
from __future__ import annotations
import os

# ── Schema helpers ────────────────────────────────────────────────────────────
_S = {"type": "string"}
_SL = {"type": "array", "items": {"type": "string"}}

def _fn(name: str, desc: str, props: dict, required: list) -> dict:
    return {
        "type": "function",
        "function": {
            "name": name,
            "description": desc,
            "parameters": {
                "type": "object",
                "properties": props,
                "required": required,
            },
        },
    }

# ── Tool metadata ─────────────────────────────────────────────────────────────
# risk: "low" | "medium" | "high"
# modes: set of modes that can use this tool
TOOL_META: dict[str, dict] = {
    # Snapshot — design history
    "take_snapshot":    {"risk": "low",    "modes": {"agent"},         "label": "Snapshot Al"},
    "list_snapshots":   {"risk": "low",    "modes": {"agent", "plan"}, "label": "Snapshot Listesi"},
    "restore_snapshot": {"risk": "medium", "modes": {"agent"},         "label": "Snapshot Geri Yükle"},
    # Resource check
    "check_resource_fit":{"risk":"low",   "modes": {"agent", "plan"}, "label": "Kaynak Uyum Kontrolü"},
    # File read/list — low risk
    "list_files":       {"risk": "low",    "modes": {"agent", "plan"}, "label": "Dosyaları Listele"},
    "read_file":        {"risk": "low",    "modes": {"agent", "plan"}, "label": "Dosya Oku"},
    "glob_files":       {"risk": "low",    "modes": {"agent", "plan"}, "label": "Dosya Ara (glob)"},
    "grep_files":       {"risk": "low",    "modes": {"agent", "plan"}, "label": "Kod İçinde Ara"},
    # File write — medium risk
    "write_file":       {"risk": "medium", "modes": {"agent"},         "label": "Dosya Yaz"},
    "edit_file":        {"risk": "medium", "modes": {"agent"},         "label": "Dosya Düzenle"},
    "create_dir":       {"risk": "medium", "modes": {"agent"},         "label": "Klasör Oluştur"},
    "rename_file":      {"risk": "medium", "modes": {"agent"},         "label": "Dosya Taşı/Yeniden Adlandır"},
    # Workspace
    "set_workspace_dir":{"risk": "low",    "modes": {"agent"},         "label": "Klasör Seç"},
    "clear_workspace":  {"risk": "high",   "modes": {"agent"},         "label": "Workspace Temizle"},
    # File delete
    "delete_file":      {"risk": "high",   "modes": {"agent"},         "label": "Dosya Sil"},
    # Shell
    "run_command":      {"risk": "medium", "modes": {"agent"},         "label": "Komut Çalıştır"},
    # EDA
    "compile_verilog":  {"risk": "medium", "modes": {"agent"},         "label": "Verilog Derle"},
    "run_simulation":   {"risk": "medium", "modes": {"agent"},         "label": "Simülasyon Çalıştır"},
    # FPGA
    "check_vivado":     {"risk": "low",    "modes": {"agent", "plan"}, "label": "Vivado Kontrol"},
    "get_board_info":   {"risk": "low",    "modes": {"agent", "plan"}, "label": "Kart Bilgisi"},
    "generate_xdc":     {"risk": "medium", "modes": {"agent"},         "label": "XDC Oluştur"},
    "prepare_vivado_build":{"risk":"medium","modes": {"agent"},        "label": "Vivado Build Hazırla"},
    "run_vivado_flow":  {"risk": "high",   "modes": {"agent"},         "label": "Vivado Akışı Başlat"},
    "read_vivado_reports":{"risk":"low",   "modes": {"agent", "plan"}, "label": "Vivado Raporu Oku"},
    "get_vivado_full_log":{"risk":"low",   "modes": {"agent", "plan"}, "label": "Vivado Log Oku"},
    "program_fpga":     {"risk": "high",   "modes": {"agent"},         "label": "FPGA Programla"},
}

# ── JSON Schemas ──────────────────────────────────────────────────────────────
ALL_SCHEMAS: list[dict] = [
    _fn("take_snapshot",    "Save a design snapshot with a label.", {"label": _S}, ["label"]),
    _fn("list_snapshots",   "List all saved design snapshots.", {}, []),
    _fn("restore_snapshot", "Restore a snapshot by label or index number.", {"label_or_index": _S}, ["label_or_index"]),
    _fn("check_resource_fit", "Check if design fits the selected board.",
        {"board": _S, "lut_count": {"type": "integer", "default": 0},
         "ff_count": {"type": "integer", "default": 0},
         "bram_count": {"type": "integer", "default": 0},
         "dsp_count": {"type": "integer", "default": 0}}, ["board"]),
    _fn("list_files",    "List workspace directory contents.", {"path": {**_S, "default": ""}}, []),
    _fn("read_file",     "Read a file with line numbers.", {"path": _S}, ["path"]),
    _fn("write_file",    "Write/create a file.", {"path": _S, "content": _S}, ["path", "content"]),
    _fn("edit_file",     "Surgical edit: replace old_str with new_str.", {"path": _S, "old_str": _S, "new_str": _S}, ["path", "old_str", "new_str"]),
    _fn("delete_file",   "Delete a file or directory.", {"path": _S}, ["path"]),
    _fn("create_dir",    "Create a directory.", {"path": _S}, ["path"]),
    _fn("rename_file",   "Rename/move a file.", {"old_path": _S, "new_path": _S}, ["old_path", "new_path"]),
    _fn("grep_files",    "Regex search in files.", {"pattern": _S, "path": {**_S, "default": ""}, "recursive": {"type": "boolean", "default": True}}, ["pattern"]),
    _fn("glob_files",    "Find files by glob pattern.", {"pattern": _S}, ["pattern"]),
    _fn("run_command",   "Run a shell command in workspace.", {"command": _S}, ["command"]),
    _fn("compile_verilog","Compile Verilog with iverilog. Include ALL files (design + testbench).", {"files": _SL}, ["files"]),
    _fn("run_simulation", "Compile + simulate with iverilog+vvp.", {"files": _SL}, ["files"]),
    _fn("check_vivado",  "Check Vivado availability.", {}, []),
    _fn("get_board_info","Get FPGA board pin map.", {"board_name": _S}, ["board_name"]),
    _fn("generate_xdc",  "Generate XDC constraints file.", {"path": _S, "board": _S, "clk_port": _S, "led_ports": _SL, "sw_ports": _SL}, ["path", "board"]),
    _fn("prepare_vivado_build", "Prepare Vivado TCL build script.", {"files": _SL, "top_module": _S, "board": {**_S, "default": "basys3"}}, ["files", "top_module"]),
    _fn("run_vivado_flow","Run Vivado synth→impl→bitstream.", {"tcl_script_path": _S}, ["tcl_script_path"]),
    _fn("read_vivado_reports", "Read synthesis/timing reports.", {}, []),
    _fn("get_vivado_full_log", "Read full Vivado log.", {"log_path": _S}, ["log_path"]),
    _fn("program_fpga",  "Program FPGA with bitstream.", {"board": {**_S, "default": "basys3"}}, []),
    _fn("set_workspace_dir", "Switch to a project subdirectory.", {"path": _S}, ["path"]),
    _fn("clear_workspace","Delete ALL workspace contents. Always call with confirm='yes'.", {"confirm": _S}, ["confirm"]),
]

_SCHEMA_MAP: dict[str, dict] = {s["function"]["name"]: s for s in ALL_SCHEMAS}

# ── Text descriptions for system prompt ───────────────────────────────────────
TOOL_DOCS: dict[str, str] = {
    "take_snapshot":        "take_snapshot(label) — Save current design files as a snapshot",
    "list_snapshots":       "list_snapshots() — List all design snapshots",
    "restore_snapshot":     "restore_snapshot(label_or_index) — Restore a design snapshot",
    "check_resource_fit":   "check_resource_fit(board, lut_count, ff_count, bram_count, dsp_count) — Check if design fits board",
    "list_files":           "list_files(path='') — List workspace directory",
    "read_file":            "read_file(path) — Read file with line numbers",
    "write_file":           "write_file(path, content) — Write/create a file",
    "edit_file":            "edit_file(path, old_str, new_str) — Surgical edit",
    "delete_file":          "delete_file(path) — Delete a file/dir",
    "create_dir":           "create_dir(path) — Create directory",
    "rename_file":          "rename_file(old_path, new_path) — Rename/move",
    "grep_files":           "grep_files(pattern, path='') — Regex search in files",
    "glob_files":           "glob_files(pattern) — Find files by glob",
    "run_command":          "run_command(command) — Run shell command in workspace",
    "compile_verilog":      "compile_verilog(files) — Compile Verilog (include ALL files)",
    "run_simulation":       "run_simulation(files) — Compile + simulate",
    "check_vivado":         "check_vivado() — Check Vivado availability",
    "get_board_info":       "get_board_info(board_name) — FPGA pin map",
    "generate_xdc":         "generate_xdc(path, board, clk_port, led_ports, sw_ports) — XDC file",
    "prepare_vivado_build": "prepare_vivado_build(files, top_module, board) — Prepare TCL",
    "run_vivado_flow":      "run_vivado_flow(tcl_script_path) — Vivado synth→impl→bit",
    "read_vivado_reports":  "read_vivado_reports() — Read synthesis/timing reports",
    "get_vivado_full_log":  "get_vivado_full_log(log_path) — Full Vivado log",
    "program_fpga":         "program_fpga(board='basys3') — Program FPGA",
    "set_workspace_dir":    "set_workspace_dir(path) — Switch to project subdirectory",
    "clear_workspace":      "clear_workspace(confirm='yes') — Delete ALL workspace contents",
}

def get_schemas_for_mode(mode: str) -> list[dict]:
    """Return tool schemas allowed for the given mode."""
    return [
        _SCHEMA_MAP[name]
        for name, meta in TOOL_META.items()
        if mode in meta["modes"] and name in _SCHEMA_MAP
    ]

def get_tool_descriptions(mode: str) -> str:
    """Return numbered text description of tools for system prompt."""
    names = [n for n, m in TOOL_META.items() if mode in m["modes"]]
    return "\n".join(f"{i+1}. {TOOL_DOCS[n]}" for i, n in enumerate(names) if n in TOOL_DOCS)

def get_tool_meta(name: str) -> dict:
    return TOOL_META.get(name, {"risk": "medium", "modes": set(), "label": name})
