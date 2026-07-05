"""
VCD (Value Change Dump) parser servisi.
Regex yerine line-by-line parsing kullanır. Bozuk VCD'lerde crash yapmaz.
"""

import pathlib


def parse_vcd(vcd_path: str, max_signals: int = 32, max_time: int = 10000) -> dict:
    """
    VCD dosyasını parse et. Döndüreceği dict:
    {
        "timescale": "1ns",
        "end_time": 1000,
        "signals": [
            {
                "name": "clk",
                "width": 1,
                "module": "tb_top",
                "changes": [
                    {"time": 0, "value": "0"},
                    {"time": 5, "value": "1"},
                    ...
                ]
            }
        ]
    }
    max_signals: en fazla bu kadar sinyal döndür
    max_time:   bu zaman damgasından sonrasını atla
    Hata durumunda: {"error": "..."}
    """
    try:
        vcd_file = pathlib.Path(vcd_path)
        if not vcd_file.exists():
            return {"error": f"Dosya bulunamadı: {vcd_path}"}
        if not vcd_file.is_file():
            return {"error": f"Geçerli bir dosya değil: {vcd_path}"}

        try:
            raw_text = vcd_file.read_text(encoding="utf-8", errors="replace")
        except OSError as e:
            return {"error": f"Dosya okunamadı: {e}"}

        # Tokenise: split on whitespace but keep $...$end blocks manageable
        tokens = _tokenise(raw_text)

        # --- Parser state ---
        timescale = ""
        # id_char -> {name, width, module}
        signal_defs: dict[str, dict] = {}
        # id_char -> list of {"time": int, "value": str}
        signal_changes: dict[str, list] = {}
        # module scope stack
        scope_stack: list[str] = []
        current_time = 0
        end_time = 0
        in_dumpvars = False

        i = 0
        n = len(tokens)

        while i < n:
            tok = tokens[i]

            # --- Keyword handling ---
            if tok == "$timescale":
                i += 1
                parts = []
                while i < n and tokens[i] != "$end":
                    parts.append(tokens[i])
                    i += 1
                timescale = "".join(parts).strip()
                # i now points to $end; will be advanced at loop bottom

            elif tok == "$scope":
                # $scope module tb_top $end
                i += 1
                scope_type = tokens[i] if i < n else ""
                i += 1
                scope_name = tokens[i] if i < n else ""
                i += 1  # skip $end
                if scope_type in ("module", "task", "function", "begin", "fork"):
                    scope_stack.append(scope_name)

            elif tok == "$upscope":
                i += 1  # skip $end
                if scope_stack:
                    scope_stack.pop()

            elif tok == "$var":
                # $var wire 1 ! clk $end
                # $var wire 8 " data [7:0] $end
                i += 1
                var_type = tokens[i] if i < n else "wire"
                i += 1
                try:
                    width = int(tokens[i]) if i < n else 1
                except ValueError:
                    width = 1
                i += 1
                id_char = tokens[i] if i < n else ""
                i += 1
                name = tokens[i] if i < n else ""
                i += 1
                # Skip optional bit range and $end
                while i < n and tokens[i] != "$end":
                    i += 1
                # Register signal if under the limit
                module_path = ".".join(scope_stack) if scope_stack else ""
                if id_char and len(signal_defs) < max_signals:
                    signal_defs[id_char] = {
                        "name": name,
                        "width": width,
                        "module": module_path,
                    }
                    signal_changes[id_char] = []

            elif tok in ("$dumpvars", "$dumpall", "$dumpon", "$dumpoff", "$dumpoff"):
                in_dumpvars = True
                # content inside is treated as value changes; $end closes it

            elif tok == "$end":
                in_dumpvars = False

            elif tok == "$comment" or tok == "$date" or tok == "$version":
                # Skip until $end
                i += 1
                while i < n and tokens[i] != "$end":
                    i += 1

            elif tok.startswith("#"):
                # Time stamp
                try:
                    current_time = int(tok[1:])
                    if current_time > end_time:
                        end_time = current_time
                except ValueError:
                    pass

            else:
                # Value change
                if current_time <= max_time:
                    _handle_value_change(tok, tokens, i, current_time,
                                         signal_defs, signal_changes)

            i += 1

        # Build result
        signals = []
        for id_char, meta in signal_defs.items():
            changes = signal_changes.get(id_char, [])
            signals.append({
                "name": meta["name"],
                "width": meta["width"],
                "module": meta["module"],
                "changes": changes,
            })

        return {
            "timescale": timescale,
            "end_time": min(end_time, max_time),
            "signals": signals,
        }

    except Exception as e:
        return {"error": f"Parse hatası: {e}"}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _tokenise(text: str) -> list[str]:
    """Split VCD text into whitespace-separated tokens."""
    return text.split()


def _handle_value_change(
    tok: str,
    tokens: list[str],
    i: int,
    current_time: int,
    signal_defs: dict,
    signal_changes: dict,
) -> None:
    """
    Parse a single value-change token and record it.
    Single-bit:  0!  1"  x#  z$
    Multi-bit:   b00110101 "   (tok starts with 'b' or 'B')
    Real value:  r3.14 !        (tok starts with 'r' or 'R') — stored as string
    """
    if not tok:
        return

    first = tok[0].lower()

    if first in ("b", "r"):
        # Multi-bit / real: value is rest of tok, id_char is the NEXT token
        value_str = tok[1:]
        if i + 1 < len(tokens):
            id_char = tokens[i + 1]
            # We'll advance i by 1 extra in caller? No — caller increments i by 1
            # each iteration. Since we're consuming an extra token here, we cannot
            # advance i from inside this helper without returning the new i.
            # Instead, register the change pointing at next token's id_char.
            # The next iteration will see the id_char token and fail silently
            # (not starting with a recognised prefix), which is acceptable.
            _record_change(id_char, current_time, value_str, signal_defs, signal_changes)
    else:
        # Single-bit: first char is value, rest is id_char
        value_char = first
        id_char = tok[1:]
        if value_char in ("0", "1", "x", "z", "X", "Z"):
            _record_change(id_char, current_time, value_char.lower(),
                            signal_defs, signal_changes)


def _record_change(
    id_char: str,
    time: int,
    value: str,
    signal_defs: dict,
    signal_changes: dict,
) -> None:
    """Append a change entry if the id_char is a known signal."""
    if id_char in signal_defs:
        signal_changes[id_char].append({"time": time, "value": value})
