#!/usr/bin/env python3
# upload.py - Flashes firmware.bin to RV32_Prototip_3 over UART
import sys
import time
import os

try:
    import serial
except ImportError:
    print("Error: pyserial library is not installed. Please run: pip install pyserial")
    sys.exit(1)

if len(sys.argv) < 3:
    print(f"Usage: python {sys.argv[0]} <COM_PORT> <firmware.bin>")
    print(f"Example: python {sys.argv[0]} COM12 firmware.bin")
    sys.exit(1)

port = sys.argv[1]
filename = sys.argv[2]
baudrate = 115200

try:
    with open(filename, 'rb') as f:
        firmware = f.read()
except FileNotFoundError:
    print(f"Error: {filename} not found.")
    sys.exit(1)

length = len(firmware)
if length == 0:
    print("Error: Firmware is empty.")
    sys.exit(1)

print(f"Opening port {port} at {baudrate} baud...")
try:
    ser = serial.Serial(port, baudrate, timeout=1)
except Exception as e:
    print(f"Failed to open port: {e}")
    sys.exit(1)

print("Sending MAGIC sequence (BOOT) to halt CPU and enter Bootloader mode...")
# Magic Sequence: 0xDE 0xAD 0xBE 0xEF
magic = bytes([0xDE, 0xAD, 0xBE, 0xEF])
ser.write(magic)

# Give hw_bootloader a tiny moment to reset the CPU
time.sleep(0.01)

print(f"Sending Length header: {length} bytes...")
# 4 bytes little endian
len_bytes = length.to_bytes(4, byteorder='little')
ser.write(len_bytes)

print("Sending Firmware Payload...")
# Pad to 4-byte boundaries because hw_bootloader expects 32-bit words
pad_len = (4 - (length % 4)) % 4
padded_firmware = firmware + bytes([0]*pad_len)

# Write payload to serial
ser.write(padded_firmware)
ser.flush()

print("Upload complete! CPU should now be booting the new C firmware.")
ser.close()
