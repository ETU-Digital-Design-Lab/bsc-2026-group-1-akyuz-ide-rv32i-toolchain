import json
import re
import sys
from pathlib import Path

ALLOWED_MODES = {"agent", "ask", "plan"}
ALLOWED_TOOLS = {
    "read_file",
    "write_file",
    "run_command",
    "compile_verilog",
    "run_simulation",
    "prepare_vivado_build",
    "run_vivado_flow",
    "program_fpga",
    "get_vivado_full_log",
    "get_board_info",
    "generate_project_plan",
}
TOOL_CALL_RE = re.compile(r"<tool_call>(.*?)</tool_call>", re.DOTALL)


def fail(errors, line_no, msg):
    errors.append(f"[line {line_no}] {msg}")


def validate_line(obj, line_no, errors):
    if not isinstance(obj, dict):
        fail(errors, line_no, "record is not a JSON object")
        return

    for key in ("id", "mode", "messages", "assistant"):
        if key not in obj:
            fail(errors, line_no, f"missing required key: {key}")

    mode = obj.get("mode")
    if mode not in ALLOWED_MODES:
        fail(errors, line_no, f"invalid mode: {mode}")

    messages = obj.get("messages")
    if not isinstance(messages, list) or not messages:
        fail(errors, line_no, "messages must be a non-empty array")
    else:
        for i, msg in enumerate(messages):
            if not isinstance(msg, dict):
                fail(errors, line_no, f"messages[{i}] is not object")
                continue
            role = msg.get("role")
            content = msg.get("content")
            if role not in {"system", "user", "assistant"}:
                fail(errors, line_no, f"messages[{i}].role invalid: {role}")
            if not isinstance(content, str):
                fail(errors, line_no, f"messages[{i}].content must be string")

    assistant = obj.get("assistant")
    if not isinstance(assistant, str) or not assistant.strip():
        fail(errors, line_no, "assistant must be non-empty string")
        return

    if "```" in assistant:
        fail(errors, line_no, "assistant contains markdown code fence ```")

    tool_calls = TOOL_CALL_RE.findall(assistant)
    if mode == "ask":
        if tool_calls:
            fail(errors, line_no, "ask mode should not contain tool_call")
        return

    if mode in {"agent", "plan"} and len(tool_calls) > 1:
        fail(errors, line_no, "assistant contains multiple tool_call blocks")

    if len(tool_calls) == 1:
        raw = tool_calls[0].strip()
        try:
            call = json.loads(raw)
        except Exception as ex:
            fail(errors, line_no, f"tool_call JSON parse failed: {ex}")
            return
        if not isinstance(call, dict):
            fail(errors, line_no, "tool_call must decode to object")
            return
        tool = call.get("tool")
        args = call.get("args")
        if tool not in ALLOWED_TOOLS:
            fail(errors, line_no, f"tool not allowed: {tool}")
        if not isinstance(args, dict):
            fail(errors, line_no, "tool args must be JSON object")


def validate_file(path: Path) -> int:
    errors = []
    ids = set()
    with path.open("r", encoding="utf-8") as f:
        for line_no, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception as ex:
                fail(errors, line_no, f"invalid JSON: {ex}")
                continue
            rec_id = obj.get("id")
            if isinstance(rec_id, str):
                if rec_id in ids:
                    fail(errors, line_no, f"duplicate id: {rec_id}")
                ids.add(rec_id)
            validate_line(obj, line_no, errors)

    if errors:
        print(f"Validation FAILED for {path}")
        for err in errors:
            print(f" - {err}")
        return 1

    print(f"Validation OK for {path} ({len(ids)} records)")
    return 0


def main():
    if len(sys.argv) != 2:
        print("Usage: python validate_dataset.py <jsonl_path>")
        raise SystemExit(2)
    path = Path(sys.argv[1]).resolve()
    if not path.exists():
        print(f"File not found: {path}")
        raise SystemExit(2)
    raise SystemExit(validate_file(path))


if __name__ == "__main__":
    main()
