#!/usr/bin/env python3
"""
Release gate for AkyuzIDE model benchmarks.

This script applies strict production-style thresholds and prints GO / NO-GO.
It exits with code 0 on GO, 2 on NO-GO.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List

# Reuse the benchmark parser/checker to avoid duplicated logic.
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from analyze_results import analyze_row, read_summary, summarize_model  # type: ignore


DEFAULT_THRESHOLDS = {
    "min_pass_rate": 90.0,
    "max_empty_outputs": 0,
    "max_p90_wall_ms": 15000,
    "max_total_errors": 2,
}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Production release gate for benchmark runs.")
    p.add_argument("--run-dir", required=True, help="Benchmark directory with summary.csv")
    p.add_argument(
        "--json-out",
        default="",
        help="Optional JSON file with detailed gate results",
    )
    p.add_argument("--min-pass-rate", type=float, default=DEFAULT_THRESHOLDS["min_pass_rate"])
    p.add_argument("--max-empty-outputs", type=int, default=DEFAULT_THRESHOLDS["max_empty_outputs"])
    p.add_argument("--max-p90-wall-ms", type=int, default=DEFAULT_THRESHOLDS["max_p90_wall_ms"])
    p.add_argument("--max-total-errors", type=int, default=DEFAULT_THRESHOLDS["max_total_errors"])
    return p.parse_args()


def evaluate_model(model: str, s: Dict[str, object], args: argparse.Namespace) -> List[str]:
    fails: List[str] = []
    if float(s["pass_rate"]) < float(args.min_pass_rate):
        fails.append(f"pass_rate<{args.min_pass_rate}")
    if int(s["empty_outputs"]) > int(args.max_empty_outputs):
        fails.append(f"empty_outputs>{args.max_empty_outputs}")
    p90 = s["p90_wall_ms"]
    if p90 is not None and int(p90) > int(args.max_p90_wall_ms):
        fails.append(f"p90_wall_ms>{args.max_p90_wall_ms}")
    if int(s["total_errors"]) > int(args.max_total_errors):
        fails.append(f"total_errors>{args.max_total_errors}")
    return fails


def main() -> None:
    args = parse_args()
    run_dir = Path(args.run_dir)
    rows = read_summary(run_dir / "summary.csv")
    checks = [analyze_row(r, run_dir) for r in rows]

    by_model: Dict[str, List[object]] = {}
    for c in checks:
        by_model.setdefault(c.model, []).append(c)

    model_results = {}
    failing_models = []
    print("=== Release Gate ===")
    for model in sorted(by_model):
        summary = summarize_model(by_model[model])  # type: ignore[arg-type]
        reasons = evaluate_model(model, summary, args)
        passed = len(reasons) == 0
        model_results[model] = {
            "passed": passed,
            "reasons": reasons,
            "summary": summary,
        }
        verdict = "PASS" if passed else "FAIL"
        print(f"- {model}: {verdict}")
        if reasons:
            print(f"  reasons: {', '.join(reasons)}")
        print(
            f"  metrics: pass_rate={summary['pass_rate']}% empty={summary['empty_outputs']} "
            f"p90={summary['p90_wall_ms']}ms total_errors={summary['total_errors']}"
        )
        if not passed:
            failing_models.append(model)

    overall_go = len(failing_models) == 0
    print("")
    print("GO" if overall_go else "NO-GO")

    report = {
        "overall_go": overall_go,
        "thresholds": {
            "min_pass_rate": args.min_pass_rate,
            "max_empty_outputs": args.max_empty_outputs,
            "max_p90_wall_ms": args.max_p90_wall_ms,
            "max_total_errors": args.max_total_errors,
        },
        "models": model_results,
        "failing_models": failing_models,
    }
    if args.json_out:
        out = Path(args.json_out)
        out.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"Gate JSON written: {out}")

    raise SystemExit(0 if overall_go else 2)


if __name__ == "__main__":
    main()
