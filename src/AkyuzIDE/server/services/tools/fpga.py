"""FPGA/Vivado tools."""
import os
import re as _re
import subprocess
from datetime import datetime
from .shared import get_workspace, resolve_safe_path, find_file_in_workspace

VIVADO_PATH = os.getenv("VIVADO_PATH", "/home/tahatahsinakyuz/2025.2/Vivado/bin/vivado")

from services.vivado import VivadoService
from services.boards import get_board_profile
import services.activity_logger as _log

_vivado_service = None

def _get_vivado_service():
    global _vivado_service
    if _vivado_service is None:
        ws = os.getenv("WORKSPACE_DIR", os.path.join(os.getcwd(), "workspace"))
        _vivado_service = VivadoService(
            workspace_dir=os.path.join(ws, "_vivado"),
            vivado_path=VIVADO_PATH,
        )
    return _vivado_service


def check_vivado() -> str:
    if not os.path.exists(VIVADO_PATH):
        return (f"Vivado: bulunamadı\n"
                f"Proje dizini: {_get_vivado_service().project_dir}\n"
                f"VIVADO_PATH değişkenini .env dosyasında ayarlayın veya Vivado kurun.")
    try:
        r = subprocess.run(f'"{VIVADO_PATH}" -version',
                           shell=True, capture_output=True, text=True, timeout=30)
        ver = next((l.strip() for l in r.stdout.splitlines() if "Vivado" in l), "versiyon bilinmiyor")
        svc = _get_vivado_service()
        proj_xpr = svc.project_dir / f"{svc.project_name}.xpr"
        status = "MEVCUT" if proj_xpr.exists() else "HENÜZ OLUŞTURULMADI"
        return f"Vivado: {ver}\nProje: {status}\nProje dizini: {svc.project_dir}"
    except Exception as e:
        return f"Vivado kontrol hatası: {e}"


def get_board_info(board_name: str) -> str:
    profile = get_board_profile(board_name)
    pins = profile["pins"]
    lines = [f"Kart: {profile['name']}", f"Part: {profile['part']}", "", "Pin atamaları:"]
    if "clk" in pins:
        lines.append(f"  clk     -> {pins['clk']}")
    for sig in ("led", "sw"):
        p = pins.get(sig, [])
        for i, pin in enumerate((p if isinstance(p, list) else [p])[:16]):
            lines.append(f"  {sig}[{i:2d}] -> {pin}")
    lines += ["", "XDC dosyası için generate_xdc() kullanın."]
    return "\n".join(lines)


def generate_xdc(path: str, board: str, clk_port: str = "clk",
                 led_ports: list = None, sw_ports: list = None, extra: str = "") -> str:
    from services.tools.files import write_file
    profile = get_board_profile(board)
    pins = profile["pins"]
    lines = [f"## AkyuzIDE otomatik üretilmiş XDC — {profile['name']} ({profile['part']})", ""]
    if clk_port and "clk" in pins:
        lines += [
            "## Saat",
            f"set_property PACKAGE_PIN {pins['clk']} [get_ports {clk_port}]",
            f"set_property IOSTANDARD LVCMOS33 [get_ports {clk_port}]",
            f"create_clock -add -name sys_clk_pin -period 10.00 -waveform {{0 5}} [get_ports {clk_port}]", "",
        ]
    if led_ports:
        pin_list = pins.get("led", [])
        lines.append("## LED'ler")
        for i, port in enumerate(led_ports):
            if i < len(pin_list):
                lines += [f"set_property PACKAGE_PIN {pin_list[i]} [get_ports {{{port}}}]",
                          f"set_property IOSTANDARD LVCMOS33 [get_ports {{{port}}}]"]
        lines.append("")
    if sw_ports:
        pin_list = pins.get("sw", [])
        lines.append("## Anahtarlar")
        for i, port in enumerate(sw_ports):
            if i < len(pin_list):
                lines += [f"set_property PACKAGE_PIN {pin_list[i]} [get_ports {{{port}}}]",
                          f"set_property IOSTANDARD LVCMOS33 [get_ports {{{port}}}]"]
        lines.append("")
    if extra:
        lines += ["## Ek kısıtlamalar", extra, ""]
    result = write_file(path, "\n".join(lines))
    _log.log_vivado("xdc_generate", True, f"board={board} path={path}")
    return result


def check_resource_fit(board: str, lut_count: int = 0, ff_count: int = 0,
                       bram_count: int = 0, dsp_count: int = 0) -> str:
    """Tasarımın seçilen kartın kapasitesine sığıp sığmadığını kontrol eder."""
    profile = get_board_profile(board)
    limits = profile.get("resources", {})
    if not limits:
        return f"{profile['name']} için kaynak limiti bilgisi yok."

    lines = [f"KAYNAK UYUM KONTROLÜ — {profile['name']}"]
    lines.append("─" * 40)
    warnings = []

    checks = [
        ("LUT",      lut_count,  limits.get("LUTs", 0)),
        ("FF",       ff_count,   limits.get("FFs", 0)),
        ("BRAM_36K", bram_count, limits.get("BRAM_36K", 0)),
        ("DSP",      dsp_count,  limits.get("DSPs", 0)),
    ]
    for name, used, cap in checks:
        if cap == 0:
            continue
        pct = (used / cap * 100) if used > 0 else 0
        bar = "█" * int(pct / 10) + "░" * (10 - int(pct / 10))
        status = "⚠" if pct > 80 else "✓"
        lines.append(f"{status} {name:8s}: {used:6d} / {cap:6d}  [{bar}] {pct:.1f}%")
        if pct > 95:
            warnings.append(f"{name} kullanımı kritik ({pct:.0f}%) — tasarım karta sığmayabilir")
        elif pct > 80:
            warnings.append(f"{name} kullanımı yüksek ({pct:.0f}%) — optimizasyon önerilir")

    if warnings:
        lines.append("")
        lines.append("UYARILAR:")
        for w in warnings:
            lines.append(f"  • {w}")
        lines.append("")
        lines.append("OPTİMİZASYON ÖNERİLERİ:")
        if any("LUT" in w for w in warnings):
            lines.append("  • Gereksiz register aşamaları azaltın")
            lines.append("  • Çok geniş case ifadelerini one-hot encode edin")
            lines.append("  • Kullanılmayan sinyalleri kaldırın")
        if any("BRAM" in w for w in warnings):
            lines.append("  • Büyük dizileri dış belleğe (DDR/SRAM) taşıyın")
            lines.append("  • Bellek derinliğini azaltın")
    else:
        lines.append("\n✓ Tasarım bu karta rahatlıkla sığar.")

    return "\n".join(lines)


def prepare_vivado_build(files: list, top_module: str, board: str = "basys3") -> str:
    svc = _get_vivado_service()
    profile = get_board_profile(board)
    resolved = []
    for f in files:
        full = resolve_safe_path(f)
        if os.path.exists(full):
            resolved.append(full)
        else:
            found, _ = find_file_in_workspace(f)
            if found and found != "ambiguous":
                resolved.append(found)
    if not resolved:
        return f"Hata: geçerli dosya bulunamadı — {files}"

    # TCL scriptini tasarım dosyalarının yanına kaydet
    project_dir = os.path.dirname(resolved[0])
    tcl_path = svc.generate_build_tcl(
        resolved, top_module, profile["part"],
        output_dir=project_dir,
    )

    xdc_count = len([f for f in resolved if f.endswith(".xdc")])
    xdc_note = f"XDC: {xdc_count} dosya" if xdc_count else "UYARI: XDC dosyası yok — önce generate_xdc() çağırın"
    limits = profile.get("resources", {})
    res_note = (f"Kart kapasitesi: {limits.get('LUTs','?')} LUT / "
                f"{limits.get('FFs','?')} FF / {limits.get('BRAM_36K','?')} BRAM")

    _log.log_vivado("build_prepare", True,
                    f"board={board} top={top_module} files={len(resolved)} tcl={tcl_path}")
    return (
        f"TCL hazır: {tcl_path}\n"
        f"Kart: {profile['name']} ({profile['part']})\n"
        f"{res_note}\n"
        f"Kaynak: {len(resolved)} dosya  {xdc_note}\n"
        f"Çalıştırmak için: run_vivado_flow(\"{tcl_path}\")"
    )


def run_vivado_flow(tcl_script_path: str) -> str:
    """Vivado'yu batch modda çalıştırır; sentez, impl ve bitstream fazlarını raporlar."""
    svc = _get_vivado_service()
    path = tcl_script_path.strip("\"'")
    if not os.path.exists(path):
        return f"Hata: TCL bulunamadı: {path}\nÖnce prepare_vivado_build() çağırın."

    if not os.path.exists(VIVADO_PATH):
        return f"Hata: Vivado bulunamadı: {VIVADO_PATH}\nVIVADO_PATH değişkenini .env dosyasında ayarlayın."

    _log.log_vivado("flow_start", True, f"tcl={path}")
    t_start = datetime.now()

    # Vivado'yu Popen ile başlat — stdout'u satır satır işle
    cmd = [VIVADO_PATH, "-mode", "batch", "-source", path]
    log_lines = []
    phase_times: dict = {}

    try:
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, cwd=svc.workspace_dir, encoding="utf-8", errors="replace",
        )
        for line in proc.stdout:
            log_lines.append(line)
            stripped = line.strip()

            if "AKYUZ_SYNTH_DONE" in stripped:
                phase_times["synth_done"] = datetime.now()
                _log.log_vivado("synth", True, f"süre={(datetime.now()-t_start).seconds}s")

            elif "AKYUZ_SYNTH_FAILED" in stripped:
                phase_times["synth_failed"] = datetime.now()
                _log.log_vivado("synth", False, "sentezleme başarısız")

            elif "AKYUZ_IMPL_DONE" in stripped:
                phase_times["impl_done"] = datetime.now()
                elapsed = (datetime.now() - t_start).seconds
                _log.log_vivado("impl", True, f"süre={elapsed}s")

            elif "AKYUZ_IMPL_FAILED" in stripped:
                phase_times["impl_failed"] = datetime.now()
                _log.log_vivado("impl", False, "yerleşim başarısız")

            elif "AKYUZ_BITSTREAM_DONE" in stripped:
                phase_times["bitstream_done"] = datetime.now()
                _log.log_vivado("bitstream", True)

            elif "AKYUZ_BUILD_SUCCESS" in stripped:
                phase_times["build_success"] = datetime.now()

        proc.wait(timeout=10)
        returncode = proc.returncode
    except subprocess.TimeoutExpired:
        proc.kill()
        return "Hata: Vivado zaman aşımına uğradı (30 dakika)."
    except Exception as e:
        return f"Vivado başlatma hatası: {e}"

    full_log = "".join(log_lines)
    t_total = int((datetime.now() - t_start).total_seconds())

    # Log dosyasını proje dizinine de kaydet
    log_dir = os.path.dirname(path)
    log_file = os.path.join(log_dir, "vivado_run.log")
    try:
        with open(log_file, "w", encoding="utf-8") as f:
            f.write(full_log)
    except Exception:
        pass

    # Log'u parse et
    parsed = svc.parse_vivado_log(full_log)
    errors = parsed.get("errors", [])[:8]
    warnings = parsed.get("warnings", [])[:3]

    # Sonuç raporu oluştur
    lines = [f"VIVADO AKIŞ RAPORU  ({t_total}s)"]
    lines.append("─" * 40)

    synth_ok = "synth_done" in phase_times
    impl_ok = "impl_done" in phase_times or "build_success" in phase_times
    bit_ok = "bitstream_done" in phase_times or "build_success" in phase_times

    lines.append(f"{'✓' if synth_ok else '✗'} Sentezleme (Synthesis): {'BAŞARILI' if synth_ok else 'BAŞARISIZ'}")
    lines.append(f"{'✓' if impl_ok else '✗'} Yerleşim (Implementation): {'BAŞARILI' if impl_ok else 'BAŞARISIZ'}")
    lines.append(f"{'✓' if bit_ok else '✗'} Bitstream üretimi: {'BAŞARILI' if bit_ok else 'BAŞARISIZ'}")
    lines.append("")

    if bit_ok:
        util = parsed.get("utilization", {})
        timing = parsed.get("timing", "N/A")
        lines.append("KAYNAK KULLANIMI:")
        if util.get("LUTs"):
            lines.append(f"  LUT:  {util['LUTs']}")
        if util.get("FFs"):
            lines.append(f"  FF:   {util['FFs']}")
        if util.get("BRAM"):
            lines.append(f"  BRAM: {util['BRAM']}")
        if util.get("DSPs"):
            lines.append(f"  DSP:  {util['DSPs']}")
        lines.append(f"TIMING: {timing}")
        lines.append("")
        lines.append(f"Log: {log_file}")
        _log.log_vivado("flow_complete", True, f"total={t_total}s luts={util.get('LUTs','?')} timing={timing}")
    else:
        if errors:
            lines.append("HATALAR:")
            for e in errors:
                lines.append(f"  • {e}")
        if warnings:
            lines.append("KRİTİK UYARILAR:")
            for w in warnings:
                lines.append(f"  • {w}")

        # Hata Analiz Motoru — spesifik hata kodları için öneri
        hints = parsed.get("error_hints", [])
        if hints:
            lines.append("")
            lines.append("HATA ANALİZİ:")
            for h in hints[:5]:
                lines.append(f"  [{h['code']}] {h['desc']}")
                if h.get("context"):
                    lines.append(f"    Konum: {h['context']}")
                lines.append(f"    Öneri: {h['fix']}")
            lines.append("")
            lines.append("→ Bu hataları düzeltmemi ister misiniz?")

        lines.append(f"\nTam log: {log_file}")
        _log.log_vivado("flow_complete", False, f"errors={len(errors)}")

    return "\n".join(lines)


def read_vivado_reports() -> str:
    return _get_vivado_service().read_reports()


def get_vivado_full_log(log_path: str) -> str:
    try:
        with open(log_path, "r", encoding="utf-8") as f:
            return f.read()
    except Exception as e:
        return f"Hata: {e}"


def program_fpga(board: str = "basys3") -> str:
    svc = _get_vivado_service()
    tcl_path = svc.generate_program_tcl(board)
    _log.log_vivado("program_start", True, f"board={board}")
    result = svc.execute_tcl(tcl_path)
    log = result["log"]
    if "AKYUZ_PROGRAM_SUCCESS" in log:
        _log.log_vivado("program", True, f"board={board}")
        return "FPGA BAŞARIYLA PROGRAMLANDI."
    errors = [l for l in log.splitlines() if "ERROR:" in l][:5]
    _log.log_vivado("program", False, f"board={board}")
    return "PROGRAMLAMA BAŞARISIZ:\n" + "\n".join(errors) if errors else f"PROGRAMLAMA BAŞARISIZ:\n{log[:400]}"
