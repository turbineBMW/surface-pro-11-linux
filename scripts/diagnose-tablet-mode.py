#!/usr/bin/env python3
"""Read SP11 lid, tablet-mode, and controller posture without changing them."""

import argparse
import datetime
import fcntl
import glob
import pathlib
import time


EV_SW = 0x05
SW_NAMES = {0: "LID", 1: "TABLET_MODE", 14: "MACHINE_COVER"}


def _ioc(direction, ioctl_type, number, size):
    return direction << 30 | size << 16 | ioctl_type << 8 | number


def _read_switches():
    results = []
    errors = []
    for device in sorted(glob.glob("/dev/input/event*")):
        try:
            stream = open(device, "rb", buffering=0)
        except OSError as error:
            errors.append(f"{device}: {error}")
            continue

        try:
            name_buffer = bytearray(256)
            fcntl.ioctl(stream, _ioc(2, 0x45, 0x06, 256), name_buffer)
            name = name_buffer.split(b"\0")[0].decode(errors="replace")

            capability_buffer = bytearray(8)
            fcntl.ioctl(
                stream,
                _ioc(2, 0x45, 0x20 + EV_SW, len(capability_buffer)),
                capability_buffer,
            )
            capabilities = int.from_bytes(capability_buffer, "little")
            if not capabilities:
                continue

            state_buffer = bytearray(8)
            fcntl.ioctl(
                stream,
                _ioc(2, 0x45, 0x1B, len(state_buffer)),
                state_buffer,
            )
            state = int.from_bytes(state_buffer, "little")
            switches = []
            for bit in range(64):
                if capabilities & (1 << bit):
                    switch_name = SW_NAMES.get(bit, f"SW_{bit:#x}")
                    switches.append(f"{switch_name}={int(bool(state & (1 << bit)))}")
            results.append(f"{device}: {name}: {' '.join(switches)}")
        except OSError as error:
            errors.append(f"{device}: {error}")
        finally:
            stream.close()

    return results, errors


def _read_controller_states():
    driver = pathlib.Path(
        "/sys/bus/surface_aggregator/drivers/"
        "surface_aggregator_tablet_mode_switch"
    )
    states = []
    for state_path in sorted(driver.glob("*/state")):
        try:
            states.append(f"{state_path.parent.name}: {state_path.read_text().strip()}")
        except OSError as error:
            states.append(f"{state_path.parent.name}: unreadable ({error})")
    return states


def _snapshot():
    timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    print(f"timestamp={timestamp}")

    controller_states = _read_controller_states()
    if controller_states:
        for state in controller_states:
            print(f"controller={state}")
    else:
        print("controller=not found")

    switches, errors = _read_switches()
    if switches:
        for switch in switches:
            print(f"switch={switch}")
    else:
        print("switch=none readable")
        if errors:
            print("hint=run as root or grant read access to the evdev devices")


def main():
    parser = argparse.ArgumentParser(
        description="read posture state without injecting input or rebinding a driver"
    )
    parser.add_argument("--samples", type=int, default=1)
    parser.add_argument("--interval", type=float, default=1.0)
    args = parser.parse_args()

    if args.samples < 1:
        parser.error("--samples must be at least 1")
    if args.interval < 0:
        parser.error("--interval cannot be negative")

    for sample in range(args.samples):
        if sample:
            print()
        print(f"sample={sample + 1}/{args.samples}")
        _snapshot()
        if sample + 1 < args.samples:
            time.sleep(args.interval)

    print(
        "note=lid-open plus tablet-mode can be legitimate when the keyboard is "
        "detached or folded back"
    )


if __name__ == "__main__":
    main()
