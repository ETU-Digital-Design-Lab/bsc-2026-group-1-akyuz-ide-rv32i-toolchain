"""Main agent loop with streaming support."""
from __future__ import annotations
import json
import re
import datetime
import threading
from typing import AsyncIterator

import services.data_collector as _dc

from services.providers.base import LLMProvider, LLMResponse
from services.agent.registry import get_schemas_for_mode, get_tool_descriptions, get_tool_meta
from services.agent.prompts import get_system_prompt
from services.agent.mode_detector import detect_mode

# Import all tool handlers
from services.tools.files import list_files, read_file, write_file, edit_file, delete_file
from services.tools.search import grep_files, glob_files
from services.tools.shell import run_command
from services.tools.eda import compile_verilog, run_simulation
from services.tools.fpga import (check_vivado, get_board_info, generate_xdc,
                                   prepare_vivado_build, run_vivado_flow,
                                   read_vivado_reports, get_vivado_full_log, program_fpga)
from services.tools.workspace import clear_workspace, create_dir, rename_file, set_workspace_dir
from services.tools.fpga import check_resource_fit
from services.smart_router import optimize_context

import services.snapshot_service as _snap
import os as _os

def _take_snapshot(label: str) -> str:
    ws = _os.getenv("WORKSPACE_DIR", _os.path.join(_os.getcwd(), "workspace"))
    return _snap.take_snapshot(label, ws)

def _list_snapshots() -> str:
    ws = _os.getenv("WORKSPACE_DIR", _os.path.join(_os.getcwd(), "workspace"))
    return _snap.list_snapshots(ws)

def _restore_snapshot(label_or_index: str) -> str:
    ws = _os.getenv("WORKSPACE_DIR", _os.path.join(_os.getcwd(), "workspace"))
    return _snap.restore_snapshot(label_or_index, ws)

ALL_TOOLS: dict = {
    "list_files": list_files,
    "read_file": read_file,
    "write_file": write_file,
    "edit_file": edit_file,
    "delete_file": delete_file,
    "create_dir": create_dir,
    "rename_file": rename_file,
    "grep_files": grep_files,
    "glob_files": glob_files,
    "run_command": run_command,
    "compile_verilog": compile_verilog,
    "run_simulation": run_simulation,
    "check_vivado": check_vivado,
    "get_board_info": get_board_info,
    "generate_xdc": generate_xdc,
    "prepare_vivado_build": prepare_vivado_build,
    "run_vivado_flow": run_vivado_flow,
    "read_vivado_reports": read_vivado_reports,
    "get_vivado_full_log": get_vivado_full_log,
    "program_fpga": program_fpga,
    "set_workspace_dir": set_workspace_dir,
    "clear_workspace": clear_workspace,
    "check_resource_fit": check_resource_fit,
    "take_snapshot":    _take_snapshot,
    "list_snapshots":   _list_snapshots,
    "restore_snapshot": _restore_snapshot,
}

FILE_OP_TOOLS = {"write_file", "edit_file", "delete_file", "create_dir", "rename_file"}

MAX_ITERATIONS = 30

_HW_EXTS = (".v", ".sv", ".vhd", ".vhdl")


def _is_hw_file(path: str) -> bool:
    return any(path.endswith(ext) for ext in _HW_EXTS)


def _extract_utilization(text: str) -> dict:
    """Pull LUT/FF/BRAM/DSP numbers from vivado flow result text."""
    out: dict = {}
    for key, pattern in (
        ("LUTs",    r"LUT[^:]*:\s*(\d+)"),
        ("FFs",     r"(?:FF|Register)[^:]*:\s*(\d+)"),
        ("BRAM",    r"BRAM[^:]*:\s*(\d+)"),
        ("DSPs",    r"DSP[^:]*:\s*(\d+)"),
    ):
        m = re.search(pattern, text, re.IGNORECASE)
        if m:
            out[key] = int(m.group(1))
    return out


def _extract_timing(text: str) -> str:
    """Pull WNS/slack line from result text."""
    m = re.search(r"WNS[^:\n]*:\s*(-?[\d.]+\s*ns[^\n]*)", text, re.IGNORECASE)
    return m.group(1).strip() if m else "N/A"


class AgentEngine:
    def __init__(
        self,
        provider: LLMProvider,
        message: str,
        history: list[dict] | None = None,
        mode: str | None = None,
        extra_context: str | None = None,
        session_id: str | None = None,
        pending_store: dict | None = None,
        model_name: str = "",
        max_ctx_tokens: int = 6144,
    ):
        self.provider = provider
        self.mode = mode or detect_mode(message)
        self.session_id = session_id
        self.pending_store = pending_store

        tool_docs = get_tool_descriptions(self.mode)
        system_content = get_system_prompt(self.mode, tool_docs)
        if extra_context:
            system_content += f"\n\n--- Oturum bağlamı ---\n{extra_context.strip()}"

        self.messages: list[dict] = [{"role": "system", "content": system_content}]
        for m in (history or []):
            if m.get("role") in ("user", "assistant") and m.get("content"):
                self.messages.append({"role": m["role"], "content": m["content"]})

        self.schemas = get_schemas_for_mode(self.mode)
        self._changed_files: list[str] = []
        self.max_ctx_tokens: int = max_ctx_tokens

        # Data collection state
        self._original_instruction: str = message.strip()
        self._model_name: str = model_name
        self._last_written_files: dict[str, str] = {}   # path → latest content
        self._code_before_edit: dict[str, str] = {}     # path → pre-fix content
        self._last_error: str = ""
        self._pending_error_fix: bool = False
        self._last_board: str = "unknown"

    # ── helpers ──────────────────────────────────────────────────────────────

    def _extract_tool_from_text(self, text: str) -> dict | None:
        """Fallback: parse JSON tool call from text response."""
        m = re.search(r"<tool_call>(.*?)</tool_call>", text, re.DOTALL)
        raw = m.group(1) if m else None
        if not raw:
            m = re.search(r"\{", text)
            if not m:
                return None
            depth, start = 0, m.start()
            for i, ch in enumerate(text[start:]):
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
                    if depth == 0:
                        raw = text[start: start + i + 1]
                        break
        if not raw:
            return None
        try:
            raw = re.sub(r"```(json)?", "", raw).replace("```", "").strip()
            obj = json.loads(raw)
            if "tool" in obj and "args" in obj:
                return {"name": obj["tool"], "arguments": obj["args"]}
            if "name" in obj and "arguments" in obj:
                return obj
        except Exception:
            pass
        return None

    def _execute_tool(self, name: str, args: dict) -> tuple[str, bool]:
        """Execute a tool handler. Returns (result_text, file_changed)."""
        handler = ALL_TOOLS.get(name)
        if not handler:
            return f"Unknown tool: '{name}'. Available: {', '.join(ALL_TOOLS)}", False
        # Check mode permission
        meta = get_tool_meta(name)
        if self.mode not in meta["modes"]:
            return f"Tool '{name}' is not available in {self.mode} mode.", False
        try:
            result = handler(**args)
        except TypeError as e:
            result = f"Tool argument error: {e}"
        except Exception as e:
            result = f"Tool error: {e}"
        file_changed = name in {"write_file", "edit_file", "delete_file",
                                 "create_dir", "run_command", "compile_verilog", "run_simulation"}
        self._collect_after_tool(name, args, str(result))
        return str(result), file_changed

    # ── data collection helpers ───────────────────────────────────────────────

    def _get_best_code(self) -> str | None:
        """Return the largest hardware file content seen this session."""
        if not self._last_written_files:
            return None
        return max(self._last_written_files.values(), key=len, default=None)

    def _get_best_before_code(self) -> str | None:
        if not self._code_before_edit:
            return None
        return max(self._code_before_edit.values(), key=len, default=None)

    def _trigger_error_fix_bg(self, code_after: str | None) -> None:
        code_before = self._get_best_before_code()
        if not code_after or not code_before or code_before == code_after:
            return
        if not self._last_error:
            return
        threading.Thread(
            target=_dc.record_error_fix,
            kwargs={
                "instruction": self._original_instruction,
                "error_message": self._last_error,
                "code_before": code_before,
                "code_after": code_after,
                "board": self._last_board,
                "model_name": self._model_name,
            },
            daemon=True,
        ).start()

    def _collect_after_tool(self, name: str, args: dict, result: str) -> None:
        """Silent background data collection — must never raise."""
        try:
            if name == "write_file":
                path = args.get("path", "")
                content = args.get("content", "")
                if _is_hw_file(path) and content:
                    if self._pending_error_fix and path not in self._code_before_edit:
                        # Snapshot buggy version before the fix
                        if path in self._last_written_files:
                            self._code_before_edit[path] = self._last_written_files[path]
                    self._last_written_files[path] = content

            elif name == "edit_file":
                path = args.get("path", "")
                old_str = args.get("old_str", "")
                new_str = args.get("new_str", "")
                edit_ok = "error" not in result.lower() and "hata" not in result.lower()
                if _is_hw_file(path) and edit_ok:
                    if self._pending_error_fix and path not in self._code_before_edit:
                        if path in self._last_written_files:
                            self._code_before_edit[path] = self._last_written_files[path]
                    if path in self._last_written_files and old_str:
                        new_content = self._last_written_files[path].replace(old_str, new_str, 1)
                        self._last_written_files[path] = new_content

            elif name in ("generate_xdc", "prepare_vivado_build"):
                board = args.get("board", "")
                if board:
                    self._last_board = board

            elif name in ("compile_verilog", "run_simulation"):
                rl = result.lower()
                has_error = any(kw in rl for kw in ("error", "hata", "fail"))
                sim_pass = (name == "run_simulation") and (
                    "pass" in rl or "testbench tamamlandı" in rl or "başarılı" in rl
                )

                if sim_pass:
                    last_code = self._get_best_code()
                    if last_code:
                        threading.Thread(
                            target=_dc.record_silver,
                            args=(self._original_instruction, last_code, result,
                                  self._last_board, self._model_name),
                            daemon=True,
                        ).start()
                    if self._pending_error_fix and self._code_before_edit:
                        self._trigger_error_fix_bg(last_code)
                    self._pending_error_fix = False
                    self._code_before_edit = {}
                    self._last_error = ""

                elif has_error:
                    if not self._pending_error_fix:
                        self._code_before_edit = {}
                    self._last_error = result
                    self._pending_error_fix = True

                else:
                    # compile_verilog success (no error keywords, not a sim)
                    if self._pending_error_fix and self._code_before_edit:
                        self._trigger_error_fix_bg(self._get_best_code())
                    self._pending_error_fix = False
                    self._code_before_edit = {}
                    self._last_error = ""

            elif name == "run_vivado_flow":
                is_success = any(kw in result for kw in (
                    "BAŞARILI", "AKYUZ_BITSTREAM_DONE", "bitstream başarıyla"
                ))
                is_error = "HATA" in result or ("ERROR" in result and "AKYUZ" not in result)

                if is_success:
                    last_code = self._get_best_code()
                    if last_code:
                        threading.Thread(
                            target=_dc.record_gold,
                            kwargs={
                                "instruction": self._original_instruction,
                                "output_code": last_code,
                                "board": self._last_board,
                                "utilization": _extract_utilization(result),
                                "timing": _extract_timing(result),
                                "model_name": self._model_name,
                            },
                            daemon=True,
                        ).start()
                    if self._pending_error_fix and self._code_before_edit:
                        self._trigger_error_fix_bg(last_code)
                    self._pending_error_fix = False
                    self._code_before_edit = {}
                    self._last_error = ""

                elif is_error:
                    if not self._pending_error_fix:
                        self._code_before_edit = {}
                    self._last_error = result
                    self._pending_error_fix = True

        except Exception:
            pass  # Collection must never affect agent operation

    def _make_confirm_payload(self, name: str, args: dict) -> dict:
        """Build the confirm_request event payload."""
        meta = get_tool_meta(name)
        risk = meta["risk"]
        label = meta.get("label", name)

        # Build human-readable detail
        detail_parts = []
        if "path" in args:
            detail_parts.append(f"Yol: {args['path']}")
        if "content" in args:
            lines = args["content"].splitlines()
            detail_parts.append(f"{len(lines)} satır")
            detail_parts.append("\n".join(lines[:5]) + ("\n…" if len(lines) > 5 else ""))
        if "old_str" in args:
            detail_parts.append(f"Değiştirilecek:\n{args['old_str'][:100]}")
        if "new_str" in args:
            detail_parts.append(f"Yeni:\n{args['new_str'][:100]}")
        if "command" in args:
            detail_parts.append(f"Komut: {args['command']}")
        if "files" in args:
            detail_parts.append("Dosyalar:\n" + "\n".join(args.get("files", [])))
        if not detail_parts:
            detail_parts = [str(args)[:200]]

        return {
            "type": "confirm_request",
            "session_id": self.session_id,
            "tool": name,
            "args": args,
            "confirm": {
                "title": label,
                "detail": "\n".join(detail_parts),
                "risk": risk,
            },
        }

    # ── main streaming loop ──────────────────────────────────────────────────

    async def run_stream(self, user_message: str | None = None, iterations: int = 0) -> AsyncIterator[dict]:
        if iterations >= MAX_ITERATIONS:
            yield {"type": "done", "content": "Maksimum adım sayısına ulaşıldı.", "mode": self.mode}
            return

        if user_message and iterations == 0:
            self.messages.append({"role": "user", "content": user_message})

        # Context optimizasyonu — token israfını önle
        optimized = optimize_context(self.messages, self.max_ctx_tokens)

        # Call LLM
        try:
            response: LLMResponse = await self.provider.chat(
                optimized,
                tools=self.schemas if self.mode != "ask" else None,
            )
        except Exception as e:
            yield {"type": "error", "content": f"LLM bağlantı hatası: {e}"}
            return

        # Determine what the model wants to do
        tool_calls = response.tool_calls
        text_content = response.content or ""

        # Fallback: try to parse tool call from text
        if not tool_calls and text_content and self.mode != "ask":
            parsed = self._extract_tool_from_text(text_content)
            if parsed:
                from services.providers.base import ToolCall
                tool_calls = [ToolCall(name=parsed["name"], arguments=parsed.get("arguments", {}))]
                # Strip the JSON from the display text
                for marker in ("<tool_call>", '{"tool"', '{"name"'):
                    idx = text_content.find(marker)
                    if idx > 0:
                        text_content = text_content[:idx].strip()
                        break
                    elif idx == 0:
                        text_content = ""
                        break

        # Emit reasoning/thinking text if any
        if text_content and tool_calls:
            yield {"type": "reasoning", "content": text_content}

        # PATH 1: Tool calls
        if tool_calls:
            assistant_msg = {
                "role": "assistant",
                "content": text_content,
            }
            # Add tool_calls to message for Ollama compatibility
            self.messages.append(assistant_msg)

            for tc in tool_calls:
                name = tc.name
                args = tc.arguments if isinstance(tc.arguments, dict) else {}

                # Build and emit tool_call event
                preview = str(next(iter(args.values()), ""))[:60] if args else ""
                tc_event: dict = {
                    "type": "tool_call",
                    "tool": name,
                    "content": f"{name}({preview})",
                }
                if name in FILE_OP_TOOLS:
                    tc_event["args"] = args
                yield tc_event

                # Emit confirm_request and pause — for EVERY tool
                if self.session_id and self.pending_store is not None:
                    self.pending_store[self.session_id] = {
                        "engine": self,
                        "tool": name,
                        "args": args,
                        "iterations": iterations + 1,
                    }
                    yield self._make_confirm_payload(name, args)
                    return  # Pause — resume via /api/agent/confirm

                # No session (shouldn't happen in normal flow) — execute directly
                result, file_changed = self._execute_tool(name, args)
                result_preview = result[:600] + "…" if len(result) > 600 else result
                yield {"type": "tool_result", "tool": name, "content": result_preview}
                if file_changed:
                    yield {"type": "file_changed"}
                self.messages.append({"role": "tool", "content": result})

            # Continue loop after all tool calls
            async for event in self.run_stream(iterations=iterations + 1):
                yield event
            return

        # PATH 2: Text response (final answer)
        self.messages.append({"role": "assistant", "content": text_content})
        yield {"type": "done", "content": text_content, "mode": self.mode}

    async def resume_stream(self, confirmed: bool, iterations: int) -> AsyncIterator[dict]:
        """Called after user confirms or rejects a tool."""
        pending = self.pending_store.pop(self.session_id, {}) if self.pending_store else {}
        tool_name = pending.get("tool", "")
        args = pending.get("args", {})

        if not confirmed:
            # Tell the LLM the tool was rejected, then ask for a plain text response (no tools)
            self.messages.append({"role": "tool", "content": f"User rejected: {tool_name}"})
            yield {"type": "tool_result", "tool": tool_name, "content": "Kullanıcı bu işlemi reddetti."}
            # Switch to ask mode so LLM responds with text only, no further tool calls
            saved_mode = self.mode
            saved_schemas = self.schemas
            self.mode = "ask"
            self.schemas = []
            async for event in self.run_stream(iterations=iterations):
                yield event
            self.mode = saved_mode
            self.schemas = saved_schemas
        else:
            result, file_changed = self._execute_tool(tool_name, args)
            result_preview = result[:600] + "…" if len(result) > 600 else result
            yield {"type": "tool_result", "tool": tool_name, "content": result_preview}
            if file_changed:
                yield {"type": "file_changed"}
            self.messages.append({"role": "tool", "content": result})
            async for event in self.run_stream(iterations=iterations):
                yield event


# ── Smart Model Routing ───────────────────────────────────────────────────────

SIMPLE_MODEL = "llama3.1:8b"
COMPLEX_MODEL = "akyuz-qwen25-coder:14b"

_CLASSIFY_PROMPT = (
    "Classify this user message as 'simple' or 'complex'. Reply with exactly one word.\n\n"
    "simple = general questions, short explanations, quick lookups, basic code snippets\n"
    "complex = multi-file code generation, FPGA/Verilog design, algorithm implementation, "
    "debugging, architecture decisions, RISC-V, simulation, large refactors\n\n"
    "Message: {message}\n\nAnswer:"
)


async def route_request(
    message: str,
    performance_mode: str = "auto",
    host: str = "http://127.0.0.1:11434",
) -> tuple[str, str]:
    """Pick the best model for this request. Returns (model_id, reason)."""
    if performance_mode == "low":
        return SIMPLE_MODEL, "manual-low"
    if performance_mode == "high":
        return COMPLEX_MODEL, "manual-high"

    # Auto mode: fast LLM classification using the lightweight model
    prompt = _CLASSIFY_PROMPT.format(message=message[:600])
    try:
        import httpx as _httpx
        async with _httpx.AsyncClient(timeout=8.0, trust_env=False) as client:
            resp = await client.post(
                f"{host}/api/generate",
                json={
                    "model": SIMPLE_MODEL,
                    "prompt": prompt,
                    "stream": False,
                    "options": {"num_predict": 5, "temperature": 0},
                },
            )
            if resp.status_code == 200:
                label = resp.json().get("response", "").strip().lower()
                if "complex" in label:
                    return COMPLEX_MODEL, "auto-complex"
                return SIMPLE_MODEL, "auto-simple"
    except Exception:
        pass

    # Fallback: use complex model if classification call fails
    return COMPLEX_MODEL, "auto-fallback"
