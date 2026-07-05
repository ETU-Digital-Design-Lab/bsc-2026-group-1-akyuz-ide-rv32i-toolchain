#!/usr/bin/env python3
"""
gen_uart_dump.py — Generate uart_regdump.hex
Produces a RV32I program that:
  1. Loads x1..x11 with known test values
  2. Sends each as 8 ASCII hex digits + CR LF via UART (115200 8N1)
  3. Halts in an infinite loop

Memory map used:
  UART TX   = 0x00020000  (write byte → transmit)
  UART STAT = 0x00020004  (read: bit0 = tx_ready)

Register allocation:
  x1..x11  = test values
  x16      = UART base (0x00020000)
  x17      = value being printed
  x18      = nibble shift (28..0, step -4)
  x19      = nibble (0..15)
  x20      = ASCII char to send
  x21      = return address for print_hex32
  x15      = return address for uart_byte
  x22      = scratch

Layout:
  0x000 – 0x02F  setup  (12 instructions)
  0x030 – 0x07F  dump loop (11 regs × 2 instrs = 22 instructions)
  0x080          halt (jal x0,0)
  0x084 – 0x0BF  print_hex32 (15 instructions)
  0x0C0 – 0x0D0  uart_byte   (5 instructions)
"""

instrs = []   # list of (pc, encoding, comment)
pc = 0

def add(enc, comment=""):
    global pc
    instrs.append((pc, enc, comment))
    pc += 4

# ── Encoders ─────────────────────────────────────────────────────────────────

def addi(rd, rs1, imm):
    imm &= 0xFFF
    return (imm << 20) | (rs1 << 15) | (0b000 << 12) | (rd << 7) | 0b0010011

def lui(rd, imm20):
    """imm20 = bits[31:12] of result (i.e. the upper 20 bits)."""
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | 0b0110111

def jal(rd, offset):
    """offset in bytes, must be even."""
    assert offset & 1 == 0
    o = offset & 0x1FFFFF  # sign-extend handled by masking
    # JAL imm encoding: inst[31]=imm[20], [30:21]=imm[10:1], [20]=imm[11], [19:12]=imm[19:12]
    imm20 = (o >> 20) & 1
    imm10_1 = (o >> 1) & 0x3FF
    imm11 = (o >> 11) & 1
    imm19_12 = (o >> 12) & 0xFF
    return (imm20 << 31) | (imm10_1 << 21) | (imm11 << 20) | (imm19_12 << 12) | (rd << 7) | 0b1101111

def jalr(rd, rs1, imm):
    imm &= 0xFFF
    return (imm << 20) | (rs1 << 15) | (rd << 7) | 0b1100111

def srl(rd, rs1, rs2):
    return (0b0000000 << 25) | (rs2 << 20) | (rs1 << 15) | (0b101 << 12) | (rd << 7) | 0b0110011

def andi(rd, rs1, imm):
    imm &= 0xFFF
    return (imm << 20) | (rs1 << 15) | (0b111 << 12) | (rd << 7) | 0b0010011

def blt(rs1, rs2, offset):
    """Branch if rs1 < rs2 (signed)."""
    o = offset & 0x1FFF
    imm12   = (o >> 12) & 1
    imm10_5 = (o >> 5) & 0x3F
    imm4_1  = (o >> 1) & 0xF
    imm11   = (o >> 11) & 1
    return (imm12 << 31) | (imm10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (0b100 << 12) | (imm4_1 << 8) | (imm11 << 7) | 0b1100011

def bge(rs1, rs2, offset):
    """Branch if rs1 >= rs2 (signed)."""
    o = offset & 0x1FFF
    imm12   = (o >> 12) & 1
    imm10_5 = (o >> 5) & 0x3F
    imm4_1  = (o >> 1) & 0xF
    imm11   = (o >> 11) & 1
    return (imm12 << 31) | (imm10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (0b101 << 12) | (imm4_1 << 8) | (imm11 << 7) | 0b1100011

def beq(rs1, rs2, offset):
    o = offset & 0x1FFF
    imm12   = (o >> 12) & 1
    imm10_5 = (o >> 5) & 0x3F
    imm4_1  = (o >> 1) & 0xF
    imm11   = (o >> 11) & 1
    return (imm12 << 31) | (imm10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (0b000 << 12) | (imm4_1 << 8) | (imm11 << 7) | 0b1100011

def lw(rd, rs1, imm):
    imm &= 0xFFF
    return (imm << 20) | (rs1 << 15) | (0b010 << 12) | (rd << 7) | 0b0000011

def sw(rs2, rs1, imm):
    imm &= 0xFFF
    imm11_5 = (imm >> 5) & 0x7F
    imm4_0  = imm & 0x1F
    return (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (0b010 << 12) | (imm4_0 << 7) | 0b0100011

def mv(rd, rs):
    return addi(rd, rs, 0)

# ── Register names ────────────────────────────────────────────────────────────
x0=0; x1=1; x2=2; x3=3; x4=4; x5=5; x6=6; x7=7
x8=8; x9=9; x10=10; x11=11; x12=12; x15=15; x16=16; x17=17
x18=18; x19=19; x20=20; x21=21; x22=22

# ── Known addresses ──────────────────────────────────────────────────────────
HALT_PC       = 0x080
PRINT_HEX_PC  = 0x084
UART_BYTE_PC  = 0x0C0

# ── Setup: load test values ──────────────────────────────────────────────────
assert pc == 0x000
add(addi(x1,  x0, 1),   "x1  = 1")
add(addi(x2,  x0, 2),   "x2  = 2")
add(addi(x3,  x0, 3),   "x3  = 3")
add(addi(x4,  x0, 4),   "x4  = 4")
add(addi(x5,  x0, 5),   "x5  = 5")
add(addi(x6,  x0, 6),   "x6  = 6")
add(addi(x7,  x0, 7),   "x7  = 7")
add(addi(x8,  x0, 8),   "x8  = 8")
add(addi(x9,  x0, 9),   "x9  = 9")
add(addi(x10, x0, 10),  "x10 = 10 (0xA)")
# x11 = 0xABCDE000  (lui + no addi since lower 12 = 0)
add(lui(x11, 0xABCDE),  "x11 = 0xABCDE000")
# x16 = UART base 0x00020000
add(lui(x16, 0x20),     "x16 = UART base 0x00020000")
assert pc == 0x030, f"pc={hex(pc)}"

# ── Dump section: mv x17,xN then jal print_hex32 ────────────────────────────
for reg, name in [(x1,"x1"),(x2,"x2"),(x3,"x3"),(x4,"x4"),(x5,"x5"),
                  (x6,"x6"),(x7,"x7"),(x8,"x8"),(x9,"x9"),(x10,"x10")]:
    add(mv(x17, reg),                          f"mv x17, {name}")
    add(jal(x21, PRINT_HEX_PC - pc),           f"call print_hex32")
assert pc == 0x080, f"pc={hex(pc)}"

# ── Halt ─────────────────────────────────────────────────────────────────────
add(jal(x0, 0),  "halt: jal x0,0")
assert pc == 0x084, f"pc={hex(pc)}"

# ── print_hex32 subroutine ───────────────────────────────────────────────────
# Sends x17 as 8 hex ASCII digits (MSB first), then \r\n
# Returns to x21; clobbers x18,x19,x20,x22; calls uart_byte (returns to x15)
assert pc == PRINT_HEX_PC
add(addi(x18, x0, 28),             "x18 = shift = 28")
ph32_loop_pc = pc
add(srl(x19, x17, x18),            "x19 = x17 >> shift")
add(andi(x19, x19, 0xF),           "x19 = nibble (0..15)")
add(addi(x20, x19, 48),            "x20 = '0' + nibble")
add(addi(x22, x19, -10),           "x22 = nibble - 10")
# if nibble < 10: skip next; blt x22, x0, +4
skip_pc = pc
add(blt(x22, x0, +8),              "if nibble<10: skip addi below")
add(addi(x20, x19, 55),            "x20 = 'A'-10 + nibble (A=65,10+55=65)")
# fall-through or jump here
jal_uart_pc = pc
add(jal(x15, UART_BYTE_PC - pc),   "call uart_byte")
add(addi(x18, x18, -4),            "shift -= 4")
# bge x18, x0, ph32_loop
add(bge(x18, x0, ph32_loop_pc - pc), "if shift>=0 loop")
add(addi(x20, x0, 13),             "x20 = '\\r'")
add(jal(x15, UART_BYTE_PC - pc),   "call uart_byte")
add(addi(x20, x0, 10),             "x20 = '\\n'")
add(jal(x15, UART_BYTE_PC - pc),   "call uart_byte")
add(jalr(x0, x21, 0),              "return")
assert pc == UART_BYTE_PC, f"print_hex32 overran: pc={hex(pc)}, expected {hex(UART_BYTE_PC)}"

# ── uart_byte subroutine ──────────────────────────────────────────────────────
# Sends byte in x20; polls UART status; returns to x15; clobbers x22
assert pc == UART_BYTE_PC
poll_pc = pc
add(lw(x22, x16, 4),               "x22 = UART status")
add(andi(x22, x22, 1),             "x22 = tx_ready bit")
add(beq(x22, x0, poll_pc - pc),    "if !ready: poll")
add(sw(x20, x16, 0),               "UART TX = x20")
add(jalr(x0, x15, 0),              "return")

# ── Emit hex ─────────────────────────────────────────────────────────────────
out_path = "uart_regdump.hex"
lines = []
for addr, enc, comment in instrs:
    lines.append(f"// PC=0x{addr:03X}  {comment}")
    lines.append(f"{enc:08X}")

with open(out_path, "w") as f:
    f.write("\n".join(lines) + "\n")

print(f"Written {len(instrs)} instructions to {out_path}")
print("\nLayout:")
print(f"  0x000 – 0x02F  setup (test values + UART base)")
print(f"  0x030 – 0x07F  dump x1..x11")
print(f"  0x080          halt")
print(f"  0x084 – 0x0BF  print_hex32")
print(f"  0x0C0 – 0x0D3  uart_byte")
print(f"\nExpected UART output (8 hex chars + CRLF per register):")
for i in range(1, 11):
    print(f"  x{i:2d} = {i:08X}")
