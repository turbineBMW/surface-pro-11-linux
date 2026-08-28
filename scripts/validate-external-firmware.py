#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Validate an owner-supplied SP11 firmware pack without executing it.

Small and dependency-free because it also runs inside the live initramfs.
It checks that the manifest describes exactly the five expected files, that
the files match the manifest (size + SHA-256), that each file is a 32-bit ELF
for the right processor whose loadable segments stay inside the memory window
the SP11 device tree reserves for it, and that a DSP image and its device
tree come from the same Windows driver package.

Program-header counts, entry points, and specific hashes are deliberately not
pinned: they change between Windows driver releases and the hardware
authenticates the images anyway.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import pathlib
import re
import struct
import sys

# path -> (ELF machine, reserved window start, reserved window end, component)
PROFILES = {
    "qcom/x1e80100/microsoft/Denali/adsp_dtb.mbn": (1, 0x8B800000, 0x8B880000, "adsp"),
    "qcom/x1e80100/microsoft/Denali/cdsp_dtb.mbn": (1, 0x8D900000, 0x8D980000, "cdsp"),
    "qcom/x1e80100/microsoft/Denali/qcadsp8380.mbn": (164, 0x87E00000, 0x8B800000, "adsp"),
    "qcom/x1e80100/microsoft/Denali/qccdsp8380.mbn": (164, 0x8B900000, 0x8D900000, "cdsp"),
    "qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn": (164, 0x1000, 0x200000, "gpu"),
}


class InvalidPack(RuntimeError):
    pass


def digest(path: pathlib.Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def check_elf(path: pathlib.Path, relative: str) -> None:
    data = path.read_bytes()
    if len(data) < 52 or data[:7] != b"\x7fELF\x01\x01\x01":
        raise InvalidPack(f"not a 32-bit little-endian ELF image: {relative}")
    machine, _entry, phoff = struct.unpack_from("<H4xII", data, 18)
    phentsize, phnum = struct.unpack_from("<HH", data, 42)
    if phentsize != 32 or phoff + phentsize * phnum > len(data):
        raise InvalidPack(f"invalid ELF program-header table: {relative}")
    expected_machine, base, limit, _component = PROFILES[relative]
    if machine != expected_machine:
        raise InvalidPack(f"wrong processor type ({machine}) for {relative}")
    loads = 0
    for index in range(phnum):
        p_type, _off, _va, physical, _fsz, memsz = struct.unpack_from(
            "<IIIIII", data, phoff + index * phentsize)
        if p_type != 1:
            continue
        loads += 1
        if physical < base or physical + memsz > limit:
            raise InvalidPack(
                f"{relative}: segment {physical:#x}+{memsz:#x} outside the reserved "
                f"window {base:#x}-{limit:#x}")
    if loads == 0:
        raise InvalidPack(f"ELF image has no loadable segment: {relative}")


def validate(pack: pathlib.Path) -> list[dict[str, str]]:
    manifest = pack / "SP11-FIRMWARE-MANIFEST.tsv"
    if manifest.is_symlink() or not manifest.is_file():
        raise InvalidPack("firmware manifest is missing or unsafe")
    with manifest.open(encoding="utf-8-sig", newline="") as source:
        records = list(csv.DictReader(source, delimiter="\t"))
    if not records or not {"path", "bytes", "sha256"} <= set(records[0]):
        raise InvalidPack("firmware manifest header is not recognised")
    if {row.get("path", "") for row in records} != set(PROFILES) or len(records) != 5:
        raise InvalidPack("manifest must contain exactly the five SP11 firmware paths")
    packages: dict[str, set[str]] = {}
    for row in records:
        relative = row["path"]
        if relative.startswith("/") or ".." in pathlib.PurePosixPath(relative).parts:
            raise InvalidPack(f"unsafe firmware path: {relative}")
        firmware = pack / "usr/lib/firmware" / relative
        if firmware.is_symlink() or not firmware.is_file():
            raise InvalidPack(f"firmware is missing or unsafe: {relative}")
        if not row.get("bytes", "").isdigit() or firmware.stat().st_size != int(row["bytes"]):
            raise InvalidPack(f"firmware size mismatch: {relative}")
        if not re.fullmatch(r"[0-9a-f]{64}", row.get("sha256", "")) or digest(firmware) != row["sha256"]:
            raise InvalidPack(f"firmware hash mismatch: {relative}")
        check_elf(firmware, relative)
        package = row.get("source_package") or ""
        if package:
            packages.setdefault(PROFILES[relative][3], set()).add(package)
    for component in ("adsp", "cdsp"):
        if len(packages.get(component, set())) > 1:
            raise InvalidPack(f"{component} image and device tree come from different driver packages")
    return records


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("pack", type=pathlib.Path)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    try:
        records = validate(args.pack.resolve(strict=True))
    except (InvalidPack, OSError, KeyError, UnicodeError, csv.Error) as error:
        print(f"SP11 firmware pack rejected: {error}", file=sys.stderr)
        return 1
    if not args.quiet:
        print(f"SP11 firmware pack accepted: {len(records)} structurally compatible files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
