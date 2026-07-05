"""
server/services/simulation.py — AkyuzIDE Modernized Simulation Service
====================================================================
Interface for running Icarus Verilog simulations.
"""

import os
import subprocess
import tempfile
from dataclasses import dataclass
from typing import List, Dict, Optional

@dataclass
class SimulationResult:
    success: bool
    log: str
    vcd_path: Optional[str] = None
    exit_code: int = 0

class SimulationService:
    def __init__(self, iverilog_path: str = "iverilog", vvp_path: str = "vvp"):
        self.iverilog_path = iverilog_path
        self.vvp_path = vvp_path

    def run_simulation(self, files: List[str], top_module: str = "tb_top") -> SimulationResult:
        """
        Runs iverilog compilation followed by vvp execution.
        """
        with tempfile.TemporaryDirectory() as tmp_dir:
            out_exe = os.path.join(tmp_dir, "sim.out")
            
            # Step 1: Compilation
            compile_cmd = [self.iverilog_path, "-g2012", "-o", out_exe] + files
            try:
                comp_proc = subprocess.run(
                    compile_cmd,
                    capture_output=True,
                    text=True,
                    timeout=30
                )
                
                log = comp_proc.stdout + comp_proc.stderr
                if comp_proc.returncode != 0:
                    return SimulationResult(False, f"Compilation Failed:\n{log}", exit_code=comp_proc.returncode)

                # Step 2: Execution
                run_cmd = [self.vvp_path, out_exe]
                run_proc = subprocess.run(
                    run_cmd,
                    capture_output=True,
                    text=True,
                    timeout=60,
                    cwd=tmp_dir # Run in tmp dir where VCDs might be generated
                )
                
                run_log = run_proc.stdout + run_proc.stderr
                total_log = log + "\n" + run_log
                
                # Check for VCD (simplified check)
                vcd_path = None
                dump_file = os.path.join(tmp_dir, "dump.vcd")
                if os.path.exists(dump_file):
                    # In a real scenario, we might want to copy this out or serve it
                    vcd_path = dump_file 

                return SimulationResult(
                    success=(run_proc.returncode == 0),
                    log=total_log,
                    vcd_path=vcd_path,
                    exit_code=run_proc.returncode
                )

            except subprocess.TimeoutExpired:
                return SimulationResult(False, "Simulation timed out.")
            except FileNotFoundError:
                return SimulationResult(False, f"Simulation tools not found. Ensure {self.iverilog_path} is installed.")
            except Exception as e:
                return SimulationResult(False, f"Internal Error: {str(e)}")
