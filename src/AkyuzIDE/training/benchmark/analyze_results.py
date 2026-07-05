#!/usr/bin/env python3
"""
AkyuzIDE benchmark output analyzer.

Reads benchmark `summary.csv` + `Pxx__*.txt` files and produces:
- model-level latency and output metrics
- prompt-rule compliance checks (tool-only / no-tool / list-length / non-empty)
- per-run and per-model pass rates

Usage:
  python training/benchmark/analyze_results.py --run-dir "C:\\Users\\Taha\\Desktop\\akyuz_benchmark_20260425_111222"
  python training/benchmark/analyze_results.py --run-dir "..." --json-out report.json
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import statistics
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple


TOOL_ONLY_PROMPTS = {3, 4, 5, 9}
NO_TOOL_PROMPTS = {1, 2, 6, 7, 8, 10, 11}
EXPECTED_LIST_ITEMS = {
    1: 8,
    2: 6,
    6: 3,
    7: 5,
    10: 5,
    11: 6,
}


@dataclass
class RunCheck:
    prompt_index: int
    model: str
    output_file: str
    wall_ms: int
    out_chars: int
    empty_output_csv: bool
    has_tool_call_tag_csv: bool
    ok_csv: bool
    errors: List[str]
    warnings: List[str]
    passed: bool


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Analyze AkyuzIDE benchmark results.")
    parser.add_argument("--run-dir", required=True, help="Benchmark output directory containing summary.csv")
    parser.add_argument("--json-out", default="", help="Optional path to write full JSON report")
    return parser.parse_args()


def read_summary(path: Path) -> List[Dict[str, str]]:
    if not path.exists():
        raise FileNotFoundError(f"summary.csv not found: {path}")
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def strip_header(raw: str) -> str:
    lines = raw.splitlines()
    i = 0
    while i < len(lines) and not lines[i].startswith("WALL_MS="):
        i += 1
    if i < len(lines):
        i += 1
    while i < len(lines) and not lines[i].strip():
        i += 1
    return "\n".join(lines[i:]).strip()


def detect_tool_call(body: str) -> bool:
    if re.search(r"<tool_call>", body, flags=re.IGNORECASE):
        return True
    if re.search(r'"type"\s*:\s*"tool_call"', body):
        return True
    return False


def looks_json_object(body: str) -> bool:
    s = body.strip()
    return s.startswith("{") and s.endswith("}")


def count_list_items(body: str) -> int:
    count = 0
    for line in body.splitlines():
        if re.match(r"^\s*(?:[-*]|\d+[.)])\s+", line):
            count += 1
    return count


def classify_prompt_rules(prompt_index: int) -> Tuple[bool, bool]:
    return (prompt_index in TOOL_ONLY_PROMPTS, prompt_index in NO_TOOL_PROMPTS)


def analyze_row(row: Dict[str, str], run_dir: Path) -> RunCheck:
    prompt_index = int(row["prompt_index"])
    model = row["model"]
    output_file = row["output_file"]
    wall_ms = int(row["wall_ms"])
    out_chars = int(row["out_chars"])
    empty_output_csv = row["empty_output"].lower() == "true"
    has_tool_call_tag_csv = row["has_tool_call_tag"].lower() == "true"
    ok_csv = row["ok"].lower() == "true"

    # Resolve output path robustly.
    out_path = Path(output_file)
    if not out_path.exists():
        out_path = run_dir / Path(output_file).name
    body = ""
    if out_path.exists():
        body = strip_header(out_path.read_text(encoding="utf-8", errors="replace"))

    errors: List[str] = []
    warnings: List[str] = []

    if not ok_csv:
        errors.append("request_failed")

    if empty_output_csv or not body.strip():
        errors.append("empty_output")

    is_tool_only, is_no_tool = classify_prompt_rules(prompt_index)
    has_tool_call_detected = detect_tool_call(body)
    if is_tool_only and not has_tool_call_detected:
        errors.append("expected_tool_call_missing")
    if is_no_tool and has_tool_call_detected:
        errors.append("unexpected_tool_call")

    if is_tool_only:
        # Tool-only prompt should be "just one tool call", not free-form.
        if "\n" in body.strip() and not looks_json_object(body):
            warnings.append("tool_only_prompt_has_extra_multiline_text")

    expected_items = EXPECTED_LIST_ITEMS.get(prompt_index)
    if expected_items and body.strip():
        item_count = count_list_items(body)
        # Soft warning: allow models that answer correctly but not exact markdown bullets.
        if item_count and item_count < expected_items:
            warnings.append(f"list_item_count_low:{item_count}/{expected_items}")

    # Common structure sanity checks for this benchmark set
    if prompt_index == 8 and detect_tool_call(body):
        errors.append("plan_prompt_should_not_use_tool")

    passed = len(errors) == 0
    return RunCheck(
        prompt_index=prompt_index,
        model=model,
        output_file=str(out_path),
        wall_ms=wall_ms,
        out_chars=out_chars,
        empty_output_csv=empty_output_csv,
        has_tool_call_tag_csv=has_tool_call_tag_csv,
        ok_csv=ok_csv,
        errors=errors,
        warnings=warnings,
        passed=passed,
    )


def percentile(values: List[int], p: float) -> Optional[float]:
    if not values:
        return None
    if len(values) == 1:
        return float(values[0])
    k = max(0, min(len(values) - 1, int(round((len(values) - 1) * p))))
    return float(sorted(values)[k])


def summarize_model(checks: List[RunCheck]) -> Dict[str, object]:
    walls = [c.wall_ms for c in checks]
    chars = [c.out_chars for c in checks]
    passed = [c for c in checks if c.passed]
    failed = [c for c in checks if not c.passed]
    return {
        "runs": len(checks),
        "pass_count": len(passed),
        "fail_count": len(failed),
        "pass_rate": round((len(passed) / len(checks)) * 100.0, 2) if checks else 0.0,
        "empty_outputs": sum(1 for c in checks if "empty_output" in c.errors),
        "median_wall_ms": int(statistics.median(walls)) if walls else None,
        "p90_wall_ms": int(percentile(walls, 0.90) or 0) if walls else None,
        "max_wall_ms": max(walls) if walls else None,
        "median_out_chars": int(statistics.median(chars)) if chars else None,
        "total_errors": sum(len(c.errors) for c in checks),
        "total_warnings": sum(len(c.warnings) for c in checks),
    }


def print_console_report(all_checks: List[RunCheck]) -> None:
    by_model: Dict[str, List[RunCheck]] = {}
    for c in all_checks:
        by_model.setdefault(c.model, []).append(c)

    print("\n=== Model Summary ===")
    for model in sorted(by_model):
        s = summarize_model(by_model[model])
        print(
            f"- {model}: pass={s['pass_count']}/{s['runs']} ({s['pass_rate']}%), "
            f"empty={s['empty_outputs']}, median={s['median_wall_ms']}ms, "
            f"p90={s['p90_wall_ms']}ms, max={s['max_wall_ms']}ms"
        )

    failures = [c for c in all_checks if not c.passed]
    print("\n=== Failures ===")
    if not failures:
        print("- None")
    else:
        for c in sorted(failures, key=lambda x: (x.prompt_index, x.model)):
            print(
                f"- P{c.prompt_index:02d} | {c.model} | errors={','.join(c.errors)} | file={Path(c.output_file).name}"
            )

    print("\n=== Warnings (top) ===")
    warning_rows = [c for c in all_checks if c.warnings]
    if not warning_rows:
        print("- None")
    else:
        for c in sorted(warning_rows, key=lambda x: (x.prompt_index, x.model))[:20]:
            print(
                f"- P{c.prompt_index:02d} | {c.model} | warnings={','.join(c.warnings)} | file={Path(c.output_file).name}"
            )


def build_json_report(all_checks: List[RunCheck]) -> Dict[str, object]:
    by_model: Dict[str, List[RunCheck]] = {}
    for c in all_checks:
        by_model.setdefault(c.model, []).append(c)
    return {
        "models": {m: summarize_model(cs) for m, cs in sorted(by_model.items())},
        "runs": [
            {
                "prompt_index": c.prompt_index,
                "model": c.model,
                "output_file": c.output_file,
                "wall_ms": c.wall_ms,
                "out_chars": c.out_chars,
                "passed": c.passed,
                "errors": c.errors,
                "warnings": c.warnings,
                "csv_flags": {
                    "empty_output": c.empty_output_csv,
                    "has_tool_call_tag": c.has_tool_call_tag_csv,
                    "ok": c.ok_csv,
                },
            }
            for c in sorted(all_checks, key=lambda x: (x.prompt_index, x.model))
        ],
    }


def main() -> None:
    args = parse_args()
    run_dir = Path(args.run_dir)
    rows = read_summary(run_dir / "summary.csv")
    checks = [analyze_row(r, run_dir) for r in rows]
    print_console_report(checks)

    if args.json_out:
        report = build_json_report(checks)
        out_path = Path(args.json_out)
        out_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"\nJSON report written: {out_path}")


if __name__ == "__main__":
    main()
