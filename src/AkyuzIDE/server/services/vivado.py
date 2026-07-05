"""
server/services/vivado.py — AkyuzIDE Vivado Project Mode Service
============================================================
Handles persistent project creation and management for Xilinx Vivado.
"""

import os
import subprocess
import re
from pathlib import Path
from typing import List, Dict, Optional, Any

class VivadoService:
    def __init__(self, workspace_dir: str, vivado_path: Optional[str] = None):
        self.workspace_dir = Path(workspace_dir)
        self.workspace_dir.mkdir(parents=True, exist_ok=True)
        self.vivado_path = vivado_path or os.getenv("VIVADO_PATH", "C:\\Xilinx\\Vivado\\2024.1\\bin\\vivado.bat")
        self.project_name = "akyuz_project"
        self.project_dir = self.workspace_dir / self.project_name

    def generate_init_tcl(self, board_part: str) -> str:
        """Generates TCL to create a new persistent project."""
        tcl_project_dir = str(self.project_dir).replace("\\", "/")
        tcl_content = f"""
# AkyuzIDE Project Initialization
create_project -force {self.project_name} {tcl_project_dir} -part {board_part}
set_property board_part_repo_paths {{}} [current_project]
# Add workspace files automatically later
exit
"""
        tcl_file = self.workspace_dir / "init_project.tcl"
        tcl_file.write_text(tcl_content, encoding="utf-8")
        return str(tcl_file)

    def generate_build_tcl(self, files: List[str], top_module: str, part: str,
                           output_dir: Optional[str] = None) -> str:
        """Generates a TCL script for Project Mode build (Synthesis -> Implementation -> Bitstream).

        output_dir: if given, saves the TCL file there (alongside the design files).
        """
        tcl_project_dir = str(self.project_dir).replace("\\", "/")
        tcl_project_file = f"{tcl_project_dir}/{self.project_name}.xpr"
        tcl_files = [f.replace("\\", "/") for f in files]
        src_files = " ".join(f'"{f}"' for f in tcl_files if f.endswith((".v", ".sv", ".vhd")))
        xdc_files = " ".join(f'"{f}"' for f in tcl_files if f.endswith(".xdc"))

        src_add = (f"add_files -norecurse -fileset [get_filesets sources_1] [list {src_files}]"
                   if src_files else "# kaynak dosya yok")
        xdc_add = (f"add_files -norecurse -fileset [get_filesets constrs_1] [list {xdc_files}]"
                   if xdc_files else "# kısıtlama dosyası yok")

        tcl_content = f"""# AkyuzIDE Proje Derleme Scripti — otomatik oluşturuldu
# Üst modül : {top_module}
# Hedef part: {part}
# Oluşturma : [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]

set proj_file "{tcl_project_file}"
set proj_dir  "{tcl_project_dir}"

if {{ [file exists $proj_file] }} {{
    open_project $proj_file
}} else {{
    create_project -force {self.project_name} $proj_dir -part {part}
}}

# Kaynak dosyaları ekle
{src_add}

# Kısıtlama dosyaları ekle
{xdc_add}

update_compile_order -fileset sources_1
set_property top {top_module} [current_fileset]

# ── Aşama 1: Sentezleme ──────────────────────────────────────────────────────
puts "AKYUZ_PHASE: Sentezleme başlatılıyor..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {{ [get_property PROGRESS [get_runs synth_1]] != "100%" }} {{
    puts "AKYUZ_SYNTH_FAILED"
    exit 1
}}
puts "AKYUZ_SYNTH_DONE"

report_utilization    -file "$proj_dir/utilization_synth.rpt"
report_timing_summary -max_paths 10 -file "$proj_dir/timing_synth.rpt"

# ── Aşama 2: Yerleşim & Yönlendirme ─────────────────────────────────────────
puts "AKYUZ_PHASE: Yerleşim başlatılıyor..."
launch_runs impl_1 -jobs 4
wait_on_run impl_1
if {{ [get_property PROGRESS [get_runs impl_1]] != "100%" }} {{
    puts "AKYUZ_IMPL_FAILED"
    exit 1
}}
puts "AKYUZ_IMPL_DONE"

report_utilization    -file "$proj_dir/utilization_impl.rpt"
report_timing_summary -max_paths 10 -file "$proj_dir/timing_impl.rpt"
report_power          -file "$proj_dir/power.rpt"

# ── Aşama 3: Bitstream ───────────────────────────────────────────────────────
puts "AKYUZ_PHASE: Bitstream üretiliyor..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {{ [get_property PROGRESS [get_runs impl_1]] != "100%" }} {{
    puts "AKYUZ_BITSTREAM_FAILED"
    exit 1
}}
puts "AKYUZ_BITSTREAM_DONE"
puts "AKYUZ_BUILD_SUCCESS"
exit
"""
        # Kaydet: öncelik output_dir (proje klasörü), yoksa workspace
        if output_dir and os.path.isdir(output_dir):
            tcl_file = Path(output_dir) / "build_project.tcl"
        else:
            tcl_file = self.workspace_dir / "build_project.tcl"
        tcl_file.write_text(tcl_content, encoding="utf-8")
        return str(tcl_file)

    def generate_program_tcl(self, board: str = "basys3", device_index: int = 0) -> str:
        """Generates script to program hardware from the last built bitstream in the project."""
        tcl_project_dir = str(self.project_dir).replace("\\", "/")
        tcl_project_file = f"{tcl_project_dir}/{self.project_name}.xpr"

        tcl_content = f"""# AkyuzIDE FPGA Programming Script
open_project {{{tcl_project_file}}}
set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set top_name [get_property top [current_fileset]]
set bit_file "$impl_dir/$top_name.bit"
if {{ ![file exists $bit_file] }} {{
    puts "AKYUZ_PROGRAM_ERROR: bitstream not found at $bit_file"
    exit 1
}}
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set device [lindex [get_hw_devices] {device_index}]
current_hw_device $device
refresh_hw_device $device
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device $device
puts "AKYUZ_PROGRAM_SUCCESS"
close_hw_manager
exit
"""
        tcl_file = self.workspace_dir / "program_project.tcl"
        tcl_file.write_text(tcl_content, encoding="utf-8")
        return str(tcl_file)

    def read_reports(self) -> str:
        """Scan project directory for synthesis/implementation reports and return a summary."""
        sections = []
        for rpt_name in ["utilization_impl.rpt", "timing_impl.rpt", "utilization_synth.rpt", "timing_synth.rpt", "power.rpt"]:
            rpt_path = self.project_dir / rpt_name
            if not rpt_path.exists():
                continue
            try:
                content = rpt_path.read_text(encoding="utf-8", errors="ignore")
                # Extract key tables (first 80 lines or up to separator)
                lines = content.splitlines()
                relevant = []
                in_table = False
                for line in lines:
                    if "|" in line or "Slack" in line or "WNS" in line or "Total" in line:
                        in_table = True
                    if in_table:
                        relevant.append(line)
                    if len(relevant) >= 60:
                        break
                if not relevant:
                    relevant = lines[:40]
                sections.append(f"=== {rpt_name} ===\n" + "\n".join(relevant))
            except Exception:
                pass

        # Also scan runs directories
        runs_dir = self.project_dir / f"{self.project_name}.runs"
        if runs_dir.exists() and not sections:
            for run in ["impl_1", "synth_1"]:
                run_path = runs_dir / run
                if not run_path.exists():
                    continue
                for rpt in sorted(run_path.glob("*utilization*.rpt"))[:2]:
                    try:
                        lines = rpt.read_text(encoding="utf-8", errors="ignore").splitlines()[:60]
                        sections.append(f"=== {rpt.name} ({run}) ===\n" + "\n".join(lines))
                    except Exception:
                        pass

        if not sections:
            return "No reports found. Build must complete first."
        return "\n\n".join(sections)

    def execute_tcl(self, tcl_file: str) -> Dict[str, Any]:
        """Executes a TCL script using Vivado in batch mode."""
        if not os.path.exists(self.vivado_path):
            return {"success": False, "log": f"Vivado not found at {self.vivado_path}"}
        
        cmd = [self.vivado_path, "-mode", "batch", "-source", tcl_file]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, cwd=self.workspace_dir, timeout=1800)
            full_log = result.stdout + result.stderr
            
            # Simple success detection for Project Mode
            success = "AKYUZ_BUILD_SUCCESS" in full_log or result.returncode == 0
            
            # If it's a build, we might want to also parse for summary metrics (later)
            return {
                "success": success,
                "log": full_log,
                "project_path": str(self.project_dir)
            }
        except Exception as e:
            return {"success": False, "log": f"Error: {str(e)}"}

    # Vivado hata kodları → açıklama + öneri
    ERROR_HINTS: Dict[str, Dict[str, str]] = {
        "8-2571": {
            "desc": "Tanımsız modül",
            "fix":  "Kullanılan modülün .v dosyası derleme listesine eklenmemiş. prepare_vivado_build() çağrısındaki 'files' listesini kontrol edin.",
        },
        "8-6090": {
            "desc": "Tanımsız port",
            "fix":  "Bağlantı yapılan port adı modül tanımında yok. Port adını ve wire bağlantılarını kontrol edin.",
        },
        "8-285":  {
            "desc": "Tanımsız net/sinyal",
            "fix":  "Kullanılan bir wire veya reg tanımlanmamış. Sinyal bildirimini (wire/reg) kontrol edin.",
        },
        "8-87":   {
            "desc": "Çoklu kaynak (multiple drivers)",
            "fix":  "Bir net'e birden fazla always/assign bloğu değer atıyor. always bloklarını birleştirin veya reg kullanın.",
        },
        "8-3332": {
            "desc": "Gecikme (timing) kısıtı karşılanamadı",
            "fix":  "Kritik yol çok uzun. Pipeline ekleyin, saat frekansını düşürün veya create_clock kısıtını gevşetin.",
        },
        "8-4471": {
            "desc": "Latch çıkarımı",
            "fix":  "Kombinasyonel always bloğunda tüm koşullar ele alınmamış. if/case ifadelerine 'else/default' ekleyin.",
        },
        "8-5840": {
            "desc": "Saat sinyali kombinasyonel mantıktan geçiyor",
            "fix":  "Saat sinyali doğrudan flip-flop clock pinine bağlanmalı, combinational logic üzerinden geçmemeli.",
        },
        "12-1790": {
            "desc": "XDC pin kısıtı eşleşmedi",
            "fix":  "XDC dosyasındaki port adı tasarımda bulunamadı. Üst modül port adlarını ve XDC'deki get_ports isimlerini karşılaştırın.",
        },
        "12-584": {
            "desc": "Timing kısıtı çözülemedi",
            "fix":  "set_input_delay veya set_output_delay için referans saat bulunamadı. XDC'de create_clock tanımının doğru olduğunu kontrol edin.",
        },
    }

    def parse_vivado_log(self, log_text: str) -> Dict[str, Any]:
        summary: Dict[str, Any] = {
            "status": "Unknown", "errors": [], "warnings": [],
            "utilization": {}, "timing": "N/A",
            "synth_done": False, "impl_done": False,
            "error_hints": [],
        }
        if "AKYUZ_BUILD_SUCCESS" in log_text:
            summary["status"] = "Success"
            summary["synth_done"] = True
            summary["impl_done"] = True
        elif "AKYUZ_IMPL_DONE" in log_text:
            summary["status"] = "Synth+Impl OK / Bitstream failed"
            summary["synth_done"] = True
            summary["impl_done"] = True
        elif "AKYUZ_SYNTH_DONE" in log_text:
            summary["status"] = "Synth OK / Impl failed"
            summary["synth_done"] = True
        elif "ERROR:" in log_text:
            summary["status"] = "Failed"

        summary["errors"] = re.findall(r"ERROR:\s*(.*)", log_text)[:10]
        summary["warnings"] = re.findall(r"CRITICAL WARNING:\s*(.*)", log_text)[:5]

        # Hata kodu → öneri eşleştirmesi
        seen_codes: set = set()
        for code, hint in self.ERROR_HINTS.items():
            pattern = rf"\[(?:Synth|Impl|Place|Route|DRC|Timing|XDC)\s+{re.escape(code)}\]"
            if re.search(pattern, log_text) and code not in seen_codes:
                seen_codes.add(code)
                # Hangi satırda görüldüğünü al
                m = re.search(rf"ERROR:.*\[(?:Synth|Impl|Place|Route|DRC|Timing|XDC)\s+{re.escape(code)}\](.*)", log_text)
                context = m.group(1).strip()[:100] if m else ""
                summary["error_hints"].append({
                    "code": code,
                    "desc": hint["desc"],
                    "fix":  hint["fix"],
                    "context": context,
                })

        # Resource utilization
        lut = re.search(r"\|\s*Slice LUTs\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*([\d.]+)\s*\|", log_text)
        if lut:
            summary["utilization"]["LUTs"] = f"{lut.group(1)} ({lut.group(2)}%)"
        ff = re.search(r"\|\s*Slice Registers\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*([\d.]+)\s*\|", log_text)
        if ff:
            summary["utilization"]["FFs"] = f"{ff.group(1)} ({ff.group(2)}%)"
        bram = re.search(r"\|\s*Block RAM Tile\s*\|\s*([\d.]+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*([\d.]+)\s*\|", log_text)
        if bram:
            summary["utilization"]["BRAM"] = f"{bram.group(1)} ({bram.group(2)}%)"
        dsp = re.search(r"\|\s*DSPs\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*([\d.]+)\s*\|", log_text)
        if dsp:
            summary["utilization"]["DSPs"] = f"{dsp.group(1)} ({dsp.group(2)}%)"

        # Timing
        wns = re.search(r"Worst Negative Slack \(WNS\)\s*:\s*([\d.\-]+)\s*ns", log_text)
        if wns:
            summary["timing"] = f"WNS={wns.group(1)}ns"
        whs = re.search(r"Worst Hold Slack \(WHS\)\s*:\s*([\d.\-]+)\s*ns", log_text)
        if whs:
            summary["timing"] += f"  WHS={whs.group(1)}ns"

        return summary
