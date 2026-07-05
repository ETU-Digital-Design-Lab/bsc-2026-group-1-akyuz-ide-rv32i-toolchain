#!/usr/bin/env python3
import serial
import sys
import time

def send_firmware(port, filename):
    """Send firmware to RV32 bootloader via UART"""

    with open(filename, 'rb') as f:
        firmware = f.read()

    print(f"Opening {port}...")
    ser = serial.Serial(port, baudrate=115200, timeout=1)
    time.sleep(0.5)

    print(f"Sending firmware ({len(firmware)} bytes)...")

    # Magic sequence: 0xDE 0xAD 0xBE 0xEF
    magic = bytes([0xDE, 0xAD, 0xBE, 0xEF])
    ser.write(magic)
    print(f"Sent magic: {magic.hex()}")
    time.sleep(0.1)

    # Send length (little endian)
    length = len(firmware)
    length_bytes = length.to_bytes(4, byteorder='little')
    ser.write(length_bytes)
    print(f"Sent length: {length} bytes ({length_bytes.hex()})")
    time.sleep(0.1)

    # Send firmware in chunks
    chunk_size = 64
    for i in range(0, len(firmware), chunk_size):
        chunk = firmware[i:i+chunk_size]
        ser.write(chunk)
        print(f"Sent {i+len(chunk)}/{len(firmware)} bytes...")
        time.sleep(0.01)

    print("Done! CPU should boot now.")
    ser.close()

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python3 send_firmware.py <PORT> <FIRMWARE.BIN>")
        print("Example: python3 send_firmware.py COM3 firmware.bin")
        sys.exit(1)

    port = sys.argv[1]
    firmware_file = sys.argv[2]

    send_firmware(port, firmware_file)
