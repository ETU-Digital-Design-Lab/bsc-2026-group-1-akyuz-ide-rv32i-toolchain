"""
server/services/hardware.py — AkyuzIDE Modernized Hardware Service
================================================================
Handles FPGA interactions: port scanning, uploading, and C-compilation.
"""

import os
import subprocess
import serial.tools.list_ports as lp
from pathlib import Path
from typing import List, Dict, Optional, Any

# Known FPGA board identifiers for auto-detection
KNOWN_BOARD_KEYWORDS = [
    "digilent", "arty", "basys", "nexys", "ftdi", "ft232", "cp2102", "ch340", "fpga"
]

class HardwareService:
    def __init__(self, workspace_dir: str):
        self.workspace_dir = Path(workspace_dir)
        self.workspace_dir.mkdir(parents=True, exist_ok=True)

    def scan_ports(self) -> List[Dict[str, Any]]:
        """
        Scans all serial ports and attempts to identify FPGA boards.
        """
        results = []
        ports = list(lp.comports())
        print(f"[Hardware] Scanning ports... Found {len(ports)}")
        for info in ports:
            is_fpga = False
            desc_low = (info.description or "").lower()
            mfr_low = (info.manufacturer or "").lower()
            
            for kw in KNOWN_BOARD_KEYWORDS:
                if kw in desc_low or kw in mfr_low:
                    is_fpga = True
                    break
            
            print(f"  - {info.device}: {info.description} (FPGA: {is_fpga})")
            results.append({
                "port": info.device,
                "description": info.description or info.device,
                "is_fpga": is_fpga,
                "manufacturer": info.manufacturer,
                "vid": info.vid,
                "pid": info.pid
            })
        return results

    def compile_c(self, file_path: str, output_name: str = "program") -> Dict[str, Any]:
        """
        Compiles a C file from the workspace using RISC-V GCC.
        """
        compiler = getattr(self, 'compiler_path', "riscv-none-elf-gcc")
        objcopy = "riscv-none-elf-objcopy"
        
        source_file = Path(file_path)
        if not source_file.is_absolute():
             # Assume relative to parent of workspace_dir (which is WORKSPACE_DIR)
             source_file = self.workspace_dir.parent / file_path

        if not source_file.exists():
            return {"success": False, "log": f"Source file not found: {file_path}"}

        build_dir = self.workspace_dir / "_build"
        build_dir.mkdir(exist_ok=True)
        
        elf_file = build_dir / f"{output_name}.elf"
        bin_file = build_dir / f"{output_name}.bin"
        
        # Build command
        flags = ["-march=rv32i", "-mabi=ilp32", "-nostdlib", "-Ttext=0x0", "-o", str(elf_file), str(source_file)]
        
        try:
            res = subprocess.run([compiler] + flags, capture_output=True, text=True, timeout=30)
            if res.returncode != 0:
                return {"success": False, "log": res.stdout + res.stderr}
            
            # ELF to BIN
            subprocess.run([objcopy, "-O", "binary", str(elf_file), str(bin_file)])
            
            return {
                "success": True, 
                "log": "Compilation Successful", 
                "bin_path": str(bin_file)
            }
        except FileNotFoundError:
            return {"success": False, "log": f"Compiler {compiler} not found."}
        except Exception as e:
            return {"success": False, "log": str(e)}

    def upload_to_serial(self, port: str, baud: int, file_path: str) -> Dict[str, Any]:
        """
        Uploads a binary/hex file to the FPGA via Serial UART.
        """
        import serial as pyserial
        try:
            data = Path(file_path).read_bytes()
            total = len(data)
            chunk_size = 256
            
            with pyserial.Serial(port, baud, timeout=3) as ser:
                # Basic bootloader trigger
                ser.write(b'U')
                ser.flush()
                
                sent = 0
                while sent < total:
                    packet = data[sent:sent + chunk_size]
                    ser.write(packet)
                    sent += len(packet)
            
            return {"success": True, "log": f"Successfully uploaded {total} bytes to {port}"}
        except Exception as e:
            return {"success": False, "log": f"Upload failed: {str(e)}"}
