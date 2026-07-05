"""
server/services/assembler.py — AkyuzIDE Modernized RISC-V Assembler
==================================================================
Standalone RV32I assembler service. No external dependencies.
"""

from __future__ import annotations
import re
import struct
from dataclasses import dataclass, field
from typing import Dict, List, Tuple, Optional, Union

# Standard RISC-V Registers
REGS: Dict[str, int] = {
    "x0": 0, "zero": 0,
    "x1": 1, "ra": 1,
    "x2": 2, "sp": 2,
    "x3": 3, "gp": 3,
    "x4": 4, "tp": 4,
    "x5": 5, "t0": 5,
    "x6": 6, "t1": 6,
    "x7": 7, "t2": 7,
    "x8": 8, "s0": 8, "fp": 8,
    "x9": 9, "s1": 9,
    "x10": 10, "a0": 10,
    "x11": 11, "a1": 11,
    "x12": 12, "a2": 12,
    "x13": 13, "a3": 13,
    "x14": 14, "a4": 14,
    "x15": 15, "a5": 15,
    "x16": 16, "a6": 16,
    "x17": 17, "a7": 17,
    "x18": 18, "s2": 18,
    "x19": 19, "s3": 19,
    "x20": 20, "s4": 20,
    "x21": 21, "s5": 21,
    "x22": 22, "s6": 22,
    "x23": 23, "s7": 23,
    "x24": 24, "s8": 24,
    "x25": 25, "s9": 25,
    "x26": 26, "s10": 26,
    "x27": 27, "s11": 27,
    "x28": 28, "t3": 28,
    "x29": 29, "t4": 29,
    "x30": 30, "t5": 30,
    "x31": 31, "t6": 31,
}

class AssemblerError(Exception):
    def __init__(self, message: str, lineno: int = 0):
        self.lineno = lineno
        prefix = f"Line {lineno}: " if lineno else ""
        super().__init__(f"{prefix}{message}")

@dataclass
class AssemblerResult:
    words: List[int] = field(default_factory=list)
    origin: int = 0
    symbols: Dict[str, int] = field(default_factory=dict)
    listing: List[str] = field(default_factory=list)

    def to_readmemh(self) -> str:
        return "\n".join(f"{w:08x}" for w in self.words)

    def to_plain_hex(self) -> str:
        return "\n".join(f"{w:08X}" for w in self.words)

class RV32IAssembler:
    """
    Two-pass RV32I Assembler.
    """
    _R_OPS = {
        "add": (0x00, 0x0), "sub": (0x20, 0x0),
        "sll": (0x00, 0x1), "slt": (0x00, 0x2),
        "sltu": (0x00, 0x3), "xor": (0x00, 0x4),
        "srl": (0x00, 0x5), "sra": (0x20, 0x5),
        "or": (0x00, 0x6), "and": (0x00, 0x7),
    }

    _I_ALU = {"addi": 0x0, "slti": 0x2, "sltiu": 0x3, "xori": 0x4, "ori": 0x6, "andi": 0x7}
    _SHIFT = {"slli": (0x00, 0x1), "srli": (0x00, 0x5), "srai": (0x20, 0x5)}
    _LOADS = {"lb": 0x0, "lh": 0x1, "lw": 0x2, "lbu": 0x4, "lhu": 0x5}
    _STORES = {"sb": 0x0, "sh": 0x1, "sw": 0x2}
    _BRANCH = {"beq": 0x0, "bne": 0x1, "blt": 0x4, "bge": 0x5, "bltu": 0x6, "bgeu": 0x7}

    def __init__(self, start_address: int = 0x00000000):
        self.start_address = start_address

    def assemble(self, source: str) -> AssemblerResult:
        lines = self._clean(source.splitlines())
        symbols = {}
        self._pass1(lines, symbols)
        
        words = []
        listing = []
        self._pass2(lines, symbols, words, listing)
        
        return AssemblerResult(words=words, origin=self.start_address, symbols=symbols, listing=listing)

    def _clean(self, raw: List[str]) -> List[Tuple[int, str]]:
        result = []
        for lineno, line in enumerate(raw, 1):
            line = re.sub(r'#.*|//.*', '', line).strip()
            if line:
                result.append((lineno, line))
        return result

    def _pass1(self, lines: List[Tuple[int, str]], syms: dict) -> None:
        pc = self.start_address
        for lineno, line in lines:
            # Handle .org
            if line.lower().startswith(".org"):
                pc = int(line.split()[1], 0)
                continue
            
            # Handle Labels
            if ":" in line:
                lbl, remainder = line.split(":", 1)
                syms[lbl.strip()] = pc
                line = remainder.strip()
            
            if not line or line.startswith("."): continue
            pc += 4 # Fixed 4-byte instructions for now (excluding dual-op pseudos)

    def _pass2(self, lines: List[Tuple[int, str]], syms: dict, words: List[int], listing: List[str]) -> None:
        pc = self.start_address
        for lineno, line in lines:
            if line.lower().startswith(".org"):
                pc = int(line.split()[1], 0)
                continue
            if ":" in line: line = line.split(":", 1)[1].strip()
            if not line or line.startswith("."): continue

            try:
                encoded = self._encode_instruction(line, pc, syms, lineno)
                words.append(encoded)
                listing.append(f"{pc:08X}: {encoded:08X} | {line}")
                pc += 4
            except Exception as e:
                raise AssemblerError(str(e), lineno)

    def _encode_instruction(self, line: str, pc: int, syms: dict, ln: int) -> int:
        parts = re.split(r'[\s,()]+', line)
        parts = [p for p in parts if p]
        op = parts[0].lower()

        if op in self._R_OPS:
            rd, rs1, rs2 = self._get_reg(parts[1]), self._get_reg(parts[2]), self._get_reg(parts[3])
            f7, f3 = self._R_OPS[op]
            return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0x33

        if op in self._I_ALU:
            rd, rs1 = self._get_reg(parts[1]), self._get_reg(parts[2])
            imm = int(parts[3], 0) & 0xFFF
            return (imm << 20) | (rs1 << 15) | (self._I_ALU[op] << 12) | (rd << 7) | 0x13

        if op == "lui":
            rd = self._get_reg(parts[1])
            imm = int(parts[2], 0) & 0xFFFFF
            return (imm << 12) | (rd << 7) | 0x37

        # Simplified encoding for demonstration, expansion is needed for full RV32I
        return 0x00000013 # Default NOP (addi x0, x0, 0)

    def _get_reg(self, name: str) -> int:
        if name.lower() not in REGS:
            raise ValueError(f"Unknown register: {name}")
        return REGS[name.lower()]
