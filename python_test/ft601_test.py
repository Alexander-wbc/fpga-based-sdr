import sys

import ftd3xx
from ftd3xx.defines import (
    FT_DEVICE_600,
    FT_DEVICE_601,
    FT_FLAGS_HISPEED,
    FT_FLAGS_OPENED,
    FT_FLAGS_SUPERSPEED,
    FT_OPEN_BY_INDEX,
)


def decode_bytes(value):
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return str(value)


def device_type_name(device_type):
    if device_type == FT_DEVICE_600:
        return "FT600"
    if device_type == FT_DEVICE_601:
        return "FT601"
    return f"unknown ({device_type})"


def flags_name(flags):
    names = []
    if flags & FT_FLAGS_OPENED:
        names.append("opened")
    if flags & FT_FLAGS_HISPEED:
        names.append("high-speed")
    if flags & FT_FLAGS_SUPERSPEED:
        names.append("super-speed")
    return ", ".join(names) if names else "none"


def print_device(index):
    info = ftd3xx.getDeviceInfoDetail(index)
    print(f"[{index}]")
    print(f"  type        : {device_type_name(info['Type'])}")
    print(f"  flags       : {flags_name(info['Flags'])}")
    print(f"  id          : 0x{info['ID']:08X}")
    print(f"  location id : 0x{info['LocId']:08X}")
    print(f"  serial      : {decode_bytes(info['SerialNumber'])}")
    print(f"  description : {decode_bytes(info['Description'])}")
    return info


def main():
    print("FT601 / FTD3XX connection test")
    print(f"Python: {sys.executable}")
    print(f"ftd3xx: {ftd3xx.__file__}")
    print()

    try:
        count = ftd3xx.createDeviceInfoList()
    except Exception as exc:
        print("FAILED: could not create device info list.")
        print(f"Reason: {exc}")
        print("Check that the FTDI D3XX driver is installed and matches your OS/Python bitness.")
        return 1

    print(f"Device count: {count}")
    if count == 0:
        print("No FT600/FT601 device was found.")
        print("Check USB cable, board power, Windows Device Manager, and D3XX driver installation.")
        return 2

    print()
    for index in range(count):
        print_device(index)

    print()
    print("Opening device 0...")
    dev = ftd3xx.create(0, FT_OPEN_BY_INDEX)
    if dev is None:
        print("FAILED: device 0 was listed, but could not be opened.")
        print("It may already be opened by another process, or the driver state may need a reconnect.")
        return 3

    try:
        info = dev.getDeviceInfo()
        print("OPEN OK")
        print(f"  type        : {device_type_name(info['Type'])}")
        print(f"  id          : 0x{info['ID']:08X}")
        print(f"  serial      : {decode_bytes(info['Serial'])}")
        print(f"  description : {decode_bytes(info['Description'])}")

        try:
            vid, pid = dev.getVIDPID()
            print(f"  vid/pid     : {vid:04X}:{pid:04X}")
        except Exception as exc:
            print(f"  vid/pid     : unavailable ({exc})")
    finally:
        dev.close()
        print("Device closed.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
