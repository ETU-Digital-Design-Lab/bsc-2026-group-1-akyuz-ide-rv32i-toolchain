import argparse
import json
from pathlib import Path
from typing import Dict, List


def load_jsonl(path: Path) -> List[Dict]:
    rows: List[Dict] = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def record_key(rec: Dict) -> str:
    mode = rec.get("mode", "")
    msgs = rec.get("messages", [])
    user_txt = ""
    if isinstance(msgs, list):
        for m in msgs:
            if isinstance(m, dict) and m.get("role") == "user":
                user_txt = str(m.get("content", "")).strip()
                break
    assistant = str(rec.get("assistant", "")).strip()
    return f"{mode}|||{user_txt}|||{assistant}"


def main() -> None:
    ap = argparse.ArgumentParser(description="Build merged training dataset with de-dup")
    ap.add_argument("--seed", required=True, help="Path to train.seed.jsonl")
    ap.add_argument("--generated", required=True, help="Path to generated.batch*.jsonl")
    ap.add_argument("--out", required=True, help="Path to output train.full.jsonl")
    args = ap.parse_args()

    seed_path = Path(args.seed).resolve()
    gen_path = Path(args.generated).resolve()
    out_path = Path(args.out).resolve()

    seed_rows = load_jsonl(seed_path)
    gen_rows = load_jsonl(gen_path)

    merged: List[Dict] = []
    seen = set()

    # Keep seed first (higher trust), then add generated if unique.
    for rec in seed_rows + gen_rows:
        k = record_key(rec)
        if k in seen:
            continue
        seen.add(k)
        merged.append(rec)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        for rec in merged:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    print(f"seed={len(seed_rows)} generated={len(gen_rows)} merged={len(merged)}")
    print(f"wrote: {out_path}")


if __name__ == "__main__":
    main()
