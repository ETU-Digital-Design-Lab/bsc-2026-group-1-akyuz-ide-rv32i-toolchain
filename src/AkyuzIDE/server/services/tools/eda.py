"""EDA tools: Icarus Verilog compile + simulate."""
import os
import subprocess
from .shared import get_workspace, resolve_safe_path
import services.activity_logger as _log

IVERILOG = os.getenv("IVERILOG_PATH", r"C:\iverilog\bin\iverilog.exe")
VVP      = os.getenv("VVP_PATH",      r"C:\iverilog\bin\vvp.exe")


def compile_verilog(files: list) -> str:
    ws = get_workspace()
    resolved = [resolve_safe_path(f) for f in files]
    quoted = " ".join(f'"{r}"' for r in resolved)
    cmd = f'"{IVERILOG}" -g2012 -o sim.out {quoted}'
    try:
        r = subprocess.run(cmd, shell=True, cwd=ws, capture_output=True, text=True, timeout=60)
        if r.returncode != 0:
            _log.log_simulation(files, False, r.stderr)
            return f"DERLEME BAŞARISIZ:\n{r.stderr}"
        _log.log_simulation(files, True, "derleme tamam")
        return "DERLEME BAŞARILI. Binary: sim.out"
    except Exception as e:
        return f"Hata: {e}"


def run_simulation(files: list) -> str:
    result = compile_verilog(files)
    if "BAŞARISIZ" in result or "FAILED" in result:
        return result
    ws = get_workspace()

    # Tasarım klasörünü belirle (testbench'in bulunduğu yer)
    log_dir = ws
    if files:
        tb = next((f for f in files if "tb" in os.path.basename(f).lower()), files[0])
        tb_dir = os.path.dirname(resolve_safe_path(tb))
        if os.path.isdir(tb_dir):
            log_dir = tb_dir

    try:
        # VVP'yi log_dir içinde çalıştır; $dumpfile() çağrıları buraya yazar
        r = subprocess.run(f'"{VVP}" {os.path.join(ws, "sim.out")}', shell=True, cwd=log_dir,
                           capture_output=True, text=True, timeout=60)
        out = f"{r.stdout}\n{r.stderr}".strip()

        # Simülasyon logunu kaydet
        try:
            with open(os.path.join(log_dir, "simulation.log"), "w", encoding="utf-8") as lf:
                lf.write(out)
        except Exception:
            pass

        # VCD dosyası var mı bak (testbench $dumpfile ile oluşturur)
        vcd_path = None
        for fname in os.listdir(log_dir):
            if fname.endswith(".vcd"):
                vcd_path = os.path.join(log_dir, fname)
                break

        success = r.returncode == 0 and "error" not in out.lower()
        _log.log_simulation(files, success, out[:300])

        result_text = f"SİMÜLASYON ÇIKTISI:\n{out}"
        if vcd_path:
            result_text += f"\n\nVCD dosyası oluşturuldu: {vcd_path}\nDalga görüntüleyici için: 'sinyalleri göster' yazın."
        return result_text
    except Exception as e:
        return f"Hata: {e}"
