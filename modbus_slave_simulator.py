#!/usr/bin/env python3
"""
=============================================================
  MODBUS RTU SLAVE SIMULATOR - WTP 4 Leighton
  Simulasi sensor AE-101 (Chlorine) & AE-102 (pH)
  untuk Allen Bradley Micro850 PLC via Waveshare RS-485
=============================================================
  Tested with: pymodbus 3.12.1, pyserial 3.5, Python 3.11

Cara pakai:
  1. pip install pymodbus pyserial
  2. Hubungkan Waveshare USB-to-RS485 ke laptop
  3. Jalankan: python modbus_slave_simulator.py --port COM5
  4. Gunakan menu interaktif untuk ubah nilai sensor
"""

import argparse
import asyncio
import struct
import threading
import sys
import os
import time
import logging

from pymodbus.datastore import ModbusSequentialDataBlock, ModbusServerContext, ModbusDeviceContext
from pymodbus.server import ModbusSerialServer

# ===================== KONFIGURASI DEFAULT =====================
DEFAULT_PORT = "COM5" if os.name == "nt" else "/dev/ttyUSB0"
DEFAULT_BAUDRATE = 9600
DEFAULT_PARITY = "N"
DEFAULT_STOPBITS = 1
DEFAULT_BYTESIZE = 8
DEFAULT_CHLORINE = 0.15             # mg/L (normal range 0.1 - 0.3)
DEFAULT_PH = 7.2                    # pH (normal range 6.5 - 8.0)

# Register address yang di-poll PLC (dari kode ST: MB_TargetCfg.Addr := 1)
REG_START_ADDR = 1


def float32_to_registers(value, byte_order="big"):
    """
    Konversi float32 ke 2 buah 16-bit register.

    Allen Bradley Micro850 COP instruction menyalin buffer secara sequential.
    Byte order 'big' = Big-Endian (AB CD) - default untuk AB PLC.
    Jika data terbaca aneh, coba 'little' atau 'mixed'.
    """
    packed = struct.pack(">f", value)  # pack sebagai big-endian

    if byte_order == "big":       # AB CD (Big-Endian)
        reg_hi = (packed[0] << 8) | packed[1]
        reg_lo = (packed[2] << 8) | packed[3]
    elif byte_order == "little":  # DC BA (Little-Endian)
        reg_hi = (packed[3] << 8) | packed[2]
        reg_lo = (packed[1] << 8) | packed[0]
    elif byte_order == "mixed":   # CD AB (Word-Swapped)
        reg_hi = (packed[2] << 8) | packed[3]
        reg_lo = (packed[0] << 8) | packed[1]
    else:
        raise ValueError(f"Unknown byte_order: {byte_order}")

    return reg_hi, reg_lo


def registers_to_float32(reg_hi, reg_lo, byte_order="big"):
    """Decode 2 registers kembali ke float32 (untuk verifikasi)."""
    if byte_order == "big":
        packed = struct.pack(">HH", reg_hi, reg_lo)
    elif byte_order == "little":
        packed = struct.pack("<HH", reg_lo, reg_hi)
    elif byte_order == "mixed":
        packed = struct.pack(">HH", reg_lo, reg_hi)
    else:
        raise ValueError(f"Unknown byte_order: {byte_order}")
    return struct.unpack(">f", packed)[0]


def update_registers(context, slave_id, address, float_value, byte_order):
    """Update holding registers di datastore dengan nilai float baru."""
    reg_hi, reg_lo = float32_to_registers(float_value, byte_order)
    context[slave_id].setValues(3, address, [reg_hi, reg_lo])
    return reg_hi, reg_lo


def create_datastore(chlorine_val, ph_val, byte_order):
    """Buat Modbus datastore untuk slave ID 1 (chlorine) dan slave ID 2 (pH)."""
    slaves = {}

    # Slave ID 1 - AE-101 Chlorine Sensor
    cl_hi, cl_lo = float32_to_registers(chlorine_val, byte_order)
    hr_block_1 = ModbusSequentialDataBlock(0, [0] * 10)
    hr_block_1.setValues(REG_START_ADDR, [cl_hi, cl_lo])
    slaves[1] = ModbusDeviceContext(
        di=ModbusSequentialDataBlock(0, [0] * 10),
        co=ModbusSequentialDataBlock(0, [0] * 10),
        hr=hr_block_1,
        ir=ModbusSequentialDataBlock(0, [0] * 10),
    )

    # Slave ID 2 - AE-102 pH Sensor
    ph_hi, ph_lo = float32_to_registers(ph_val, byte_order)
    hr_block_2 = ModbusSequentialDataBlock(0, [0] * 10)
    hr_block_2.setValues(REG_START_ADDR, [ph_hi, ph_lo])
    slaves[2] = ModbusDeviceContext(
        di=ModbusSequentialDataBlock(0, [0] * 10),
        co=ModbusSequentialDataBlock(0, [0] * 10),
        hr=hr_block_2,
        ir=ModbusSequentialDataBlock(0, [0] * 10),
    )

    # pymodbus 3.12+: 'slaves' renamed to 'devices'
    try:
        return ModbusServerContext(devices=slaves, single=False)
    except TypeError:
        return ModbusServerContext(slaves=slaves, single=False)


def interactive_menu(context, byte_order, stop_event):
    """Menu interaktif untuk mengubah nilai sensor secara real-time."""
    print("\n" + "=" * 60)
    print("  MODBUS SLAVE SIMULATOR - Interactive Console")
    print("=" * 60)
    print(f"  Byte Order : {byte_order}")
    print(f"  Reg Address: {REG_START_ADDR}")
    print("-" * 60)
    print("  Commands:")
    print("    cl <value>   - Set Chlorine (mg/L)  [Slave 1]")
    print("    ph <value>   - Set pH value          [Slave 2]")
    print("    ramp <sensor> <start> <end> <step> <interval_sec>")
    print("                 - Ramp sensor value gradually")
    print("    status       - Tampilkan nilai register saat ini")
    print("    help         - Tampilkan menu ini")
    print("    quit         - Keluar dari simulator")
    print("=" * 60)

    while not stop_event.is_set():
        try:
            cmd = input("\n[modbus-sim] > ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print("\nShutting down...")
            stop_event.set()
            break

        if not cmd:
            continue

        parts = cmd.split()

        if parts[0] in ("quit", "exit", "q"):
            print("Shutting down simulator...")
            stop_event.set()
            break

        elif parts[0] in ("help", "h"):
            print("  cl <value>   - Set Chlorine mg/L  (contoh: cl 0.2)")
            print("  ph <value>   - Set pH              (contoh: ph 7.5)")
            print("  ramp <cl|ph> <start> <end> <step> <sec>")
            print("               - Ramp value          (contoh: ramp cl 0.1 0.5 0.01 1)")
            print("  status       - Tampilkan register saat ini")
            print("  quit         - Keluar")

        elif parts[0] == "cl":
            if len(parts) < 2:
                print("  Usage: cl <value>  (contoh: cl 0.2)")
                continue
            try:
                val = float(parts[1])
                rh, rl = update_registers(context, 1, REG_START_ADDR, val, byte_order)
                verify = registers_to_float32(rh, rl, byte_order)
                print(f"  [OK] Chlorine = {val:.4f} mg/L")
                print(f"        Registers: [{rh:#06x}, {rl:#06x}] -> verify: {verify:.4f}")
            except ValueError:
                print(f"  [ERROR] Invalid number: {parts[1]}")

        elif parts[0] == "ph":
            if len(parts) < 2:
                print("  Usage: ph <value>  (contoh: ph 7.5)")
                continue
            try:
                val = float(parts[1])
                rh, rl = update_registers(context, 2, REG_START_ADDR, val, byte_order)
                verify = registers_to_float32(rh, rl, byte_order)
                print(f"  [OK] pH = {val:.4f}")
                print(f"        Registers: [{rh:#06x}, {rl:#06x}] -> verify: {verify:.4f}")
            except ValueError:
                print(f"  [ERROR] Invalid number: {parts[1]}")

        elif parts[0] == "ramp":
            if len(parts) < 6:
                print("  Usage: ramp <cl|ph> <start> <end> <step> <interval_sec>")
                print("  Contoh: ramp cl 0.1 0.5 0.02 0.5")
                continue
            try:
                sensor = parts[1]
                start = float(parts[2])
                end = float(parts[3])
                step = float(parts[4])
                interval = float(parts[5])

                slave_id = 1 if sensor == "cl" else 2 if sensor == "ph" else None
                label = "Chlorine" if sensor == "cl" else "pH" if sensor == "ph" else None
                if slave_id is None:
                    print(f"  [ERROR] Unknown sensor: {sensor} (use 'cl' or 'ph')")
                    continue

                print(f"  [RAMP] {label}: {start} -> {end}, step={step}, interval={interval}s")
                print("  (Press Enter to stop ramp)")

                ramp_val = [start]
                direction = 1 if end > start else -1
                ramp_running = threading.Event()
                ramp_running.set()

                def ramp_thread():
                    while ramp_running.is_set() and not stop_event.is_set():
                        update_registers(context, slave_id, REG_START_ADDR, ramp_val[0], byte_order)
                        sys.stdout.write(f"\r  [RAMP] {label} = {ramp_val[0]:.4f}    ")
                        sys.stdout.flush()
                        ramp_val[0] += step * direction
                        if (direction > 0 and ramp_val[0] > end) or (direction < 0 and ramp_val[0] < end):
                            ramp_val[0] = start
                        time.sleep(interval)

                t = threading.Thread(target=ramp_thread, daemon=True)
                t.start()
                try:
                    input()
                except (EOFError, KeyboardInterrupt):
                    pass
                ramp_running.clear()
                t.join(timeout=2)
                print(f"\n  [RAMP] Stopped. {label} = {ramp_val[0]:.4f}")

            except (ValueError, IndexError) as e:
                print(f"  [ERROR] {e}")

        elif parts[0] in ("status", "s"):
            try:
                cl_regs = context[1].getValues(3, REG_START_ADDR, 2)
                cl_val = registers_to_float32(cl_regs[0], cl_regs[1], byte_order)
                print(f"  Slave 1 (Chlorine AE-101):")
                print(f"    Value    : {cl_val:.4f} mg/L")
                print(f"    Registers: [{cl_regs[0]:#06x}, {cl_regs[1]:#06x}]")
                print(f"    Notif L/H: 0.10 / 0.30")
            except Exception as e:
                print(f"  Slave 1: Error - {e}")

            try:
                ph_regs = context[2].getValues(3, REG_START_ADDR, 2)
                ph_val = registers_to_float32(ph_regs[0], ph_regs[1], byte_order)
                print(f"  Slave 2 (pH AE-102):")
                print(f"    Value    : {ph_val:.4f}")
                print(f"    Registers: [{ph_regs[0]:#06x}, {ph_regs[1]:#06x}]")
                print(f"    Alarm LL/L/H/HH: 6.00 / 6.50 / 8.00 / 8.50")
            except Exception as e:
                print(f"  Slave 2: Error - {e}")

        else:
            print(f"  [?] Unknown command: {parts[0]}. Type 'help' for commands.")


async def run_async_server(args):
    """Start Modbus RTU slave server (async)."""
    if args.debug:
        logging.basicConfig(level=logging.DEBUG)
        log = logging.getLogger()
        log.setLevel(logging.DEBUG)
    else:
        logging.basicConfig(level=logging.WARNING)

    print("=" * 60)
    print("  WTP 4 Leighton - Modbus RTU Slave Simulator")
    print("=" * 60)
    print(f"  Serial Port  : {args.port}")
    print(f"  Baud Rate    : {args.baudrate}")
    print(f"  Parity       : {args.parity}")
    print(f"  Stop Bits    : {args.stopbits}")
    print(f"  Byte Order   : {args.byte_order}")
    print(f"  Slave ID 1   : AE-101 Chlorine = {args.chlorine} mg/L")
    print(f"  Slave ID 2   : AE-102 pH       = {args.ph}")
    print(f"  Reg Address  : {REG_START_ADDR}")
    print("=" * 60)

    context = create_datastore(args.chlorine, args.ph, args.byte_order)

    stop_event = threading.Event()

    # Interactive menu di thread terpisah
    menu_thread = threading.Thread(
        target=interactive_menu,
        args=(context, args.byte_order, stop_event),
        daemon=True,
    )
    menu_thread.start()

    print(f"\n  [SERVER] Starting Modbus RTU Slave on {args.port}...")
    print(f"  [SERVER] Waiting for Master (PLC) requests...\n")

    server = ModbusSerialServer(
        context=context,
        framer="rtu",
        port=args.port,
        baudrate=args.baudrate,
        parity=args.parity,
        stopbits=args.stopbits,
        bytesize=DEFAULT_BYTESIZE,
        timeout=1,
    )

    try:
        await server.serve_forever()
    except Exception as e:
        print(f"\n[ERROR] Server failed: {e}")
        print("\nTroubleshooting:")
        print(f"  1. Pastikan port {args.port} ada dan tidak dipakai app lain")
        print("  2. Cek Device Manager -> Ports (COM & LPT) untuk nomor COM")
        print("  3. Cek driver Waveshare (CH340/CP2102) terinstall")
        print("  4. List ports: python -m serial.tools.list_ports")


def main():
    parser = argparse.ArgumentParser(
        description="Modbus RTU Slave Simulator - WTP 4 Leighton",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Contoh penggunaan:
  # Default (COM5 di Windows)
  python modbus_slave_simulator.py

  # Pilih port lain
  python modbus_slave_simulator.py --port COM6

  # Custom initial values
  python modbus_slave_simulator.py --port COM5 --chlorine 0.2 --ph 7.0

  # Jika data terbaca aneh di PLC, coba byte order lain
  python modbus_slave_simulator.py --byte-order mixed

  # Debug mode (lihat semua Modbus frames)
  python modbus_slave_simulator.py --debug
        """,
    )

    parser.add_argument("--port", "-p", default=DEFAULT_PORT,
                        help=f"Serial port (default: {DEFAULT_PORT})")
    parser.add_argument("--baudrate", "-b", type=int, default=DEFAULT_BAUDRATE,
                        help=f"Baud rate (default: {DEFAULT_BAUDRATE})")
    parser.add_argument("--parity", default=DEFAULT_PARITY, choices=["N", "E", "O"],
                        help=f"Parity (default: {DEFAULT_PARITY})")
    parser.add_argument("--stopbits", type=int, default=DEFAULT_STOPBITS, choices=[1, 2],
                        help=f"Stop bits (default: {DEFAULT_STOPBITS})")
    parser.add_argument("--chlorine", "-cl", type=float, default=DEFAULT_CHLORINE,
                        help=f"Initial chlorine mg/L (default: {DEFAULT_CHLORINE})")
    parser.add_argument("--ph", type=float, default=DEFAULT_PH,
                        help=f"Initial pH (default: {DEFAULT_PH})")
    parser.add_argument("--byte-order", default="big", choices=["big", "little", "mixed"],
                        help="Float byte order: big=ABCD, little=DCBA, mixed=CDAB (default: big)")
    parser.add_argument("--debug", "-d", action="store_true",
                        help="Enable debug logging (shows all Modbus frames)")

    args = parser.parse_args()

    try:
        asyncio.run(run_async_server(args))
    except KeyboardInterrupt:
        print("\n[SERVER] Stopped by user.")


if __name__ == "__main__":
    main()
