#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 turbinebmw
"""sp11-firmware: collect, validate, and install the Surface Pro 11 firmware
that cannot be redistributed with the project.

Five files from the Windows installation are needed for audio, microphones,
the ambient sensor stack, the CDSP, and GPU acceleration:

    qcom/x1e80100/microsoft/Denali/adsp_dtb.mbn      (Windows: adsp_dtbs.elf)
    qcom/x1e80100/microsoft/Denali/qcadsp8380.mbn
    qcom/x1e80100/microsoft/Denali/cdsp_dtb.mbn      (Windows: cdsp_dtbs.elf)
    qcom/x1e80100/microsoft/Denali/qccdsp8380.mbn
    qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn

Wi-Fi and Bluetooth firmware is redistributable and already in the image.

This tool never uploads anything. Only Python 3.9+ and standard Linux tools
are required, so the same file works from the live USB, an installed SP11
system, or any other Linux machine that can see the Windows disk.
"""

from __future__ import annotations

import argparse
import csv
import datetime as _dt
import hashlib
import io
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

MANIFEST_NAME = "SP11-FIRMWARE-MANIFEST.tsv"
REPORT_NAME = "SP11-FIRMWARE-REPORT.txt"
MARKER = Path("/etc/sp11-external-firmware")
MARKER_MANIFEST = Path("/etc/sp11-external-firmware-manifest.tsv")
FIRMWARE_ROOT = Path("/usr/lib/firmware")

# path -> (component, windows candidate names, purpose)
REQUIRED = {
    "qcom/x1e80100/microsoft/Denali/adsp_dtb.mbn": (
        "adsp", ("adsp_dtbs.elf", "adsp_dtb.mbn"), "Surface ADSP device tree"),
    "qcom/x1e80100/microsoft/Denali/qcadsp8380.mbn": (
        "adsp", ("qcadsp8380.mbn",), "Surface ADSP image (audio, sensors, battery)"),
    "qcom/x1e80100/microsoft/Denali/cdsp_dtb.mbn": (
        "cdsp", ("cdsp_dtbs.elf", "cdsp_dtb.mbn"), "Surface CDSP device tree"),
    "qcom/x1e80100/microsoft/Denali/qccdsp8380.mbn": (
        "cdsp", ("qccdsp8380.mbn",), "Surface CDSP image"),
    "qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn": (
        "gpu", ("qcdxkmsuc8380.mbn",), "Adreno GPU zap shader (GPU acceleration)"),
}

# Structural expectations: ELF machine, and the reserved-memory window every
# loadable segment must stay inside (from the SP11 device tree). Program
# header counts and entry points are NOT pinned: they legitimately change
# between Windows driver releases.
PROFILES = {
    "qcom/x1e80100/microsoft/Denali/adsp_dtb.mbn": (1, 0x8B800000, 0x8B880000),
    "qcom/x1e80100/microsoft/Denali/cdsp_dtb.mbn": (1, 0x8D900000, 0x8D980000),
    "qcom/x1e80100/microsoft/Denali/qcadsp8380.mbn": (164, 0x87E00000, 0x8B800000),
    "qcom/x1e80100/microsoft/Denali/qccdsp8380.mbn": (164, 0x8B900000, 0x8D900000),
    "qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn": (164, 0x1000, 0x200000),
}

# Hashes that were exercised on the maintainer's unit. Informational only:
# newer Windows driver packages are accepted and expected.
KNOWN_GOOD = {
    "544bd795cb06cf8dee8119ede2a667f01066b2f1b9e4348f1772d080e2026ff4": "adsp_dtb (Surface ADSP driver 8100.1.1.139)",
    "921870a839ee2aba647b04598d62ed96f3d2d5dfbb2499fc842f9a6ff0e0da13": "qcadsp8380 (Surface ADSP driver 8100.1.1.139)",
    "444f79a6eb0f5309e12a953be4fe15a76a633a7864ac5217d0cadd13427ed1fb": "cdsp_dtb (CDSP driver, mid 2025)",
    "b2ed1656c46b116f7a2adedce8e4502a2f8ed5e223b82e0ac6cc70e451d58ecc": "qccdsp8380 (CDSP driver, mid 2025)",
    "93941f040da14b8305d39579686d886706d22954a538b03da676c1aaa191797f": "cdsp_dtb (CDSP driver 30.0.0219.1000)",
    "4a67a03367f2eff2f8a0e867ca25d2bf2fcd5aee3e41e2c9f436c804e257c789": "qccdsp8380 (CDSP driver 30.0.0219.1000)",
    "c89711a60240f29cb5df13f7b904642b78b7d9d6e614473751f7bf4049fab137": "qcdxkmsuc8380 (Adreno driver 31.0.137.0)",
}

QRD_REPO = "WOA-Project/Qualcomm-Reference-Drivers"
QRD_DEVICE = "Surface/8380_DEN"


class Failure(RuntimeError):
    pass


def log(message: str = "") -> None:
    print(message, flush=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(command, text=True, capture_output=True, check=False, **kwargs)


def is_root() -> bool:
    return os.geteuid() == 0


# --------------------------------------------------------------------------
# Structural validation
# --------------------------------------------------------------------------

def elf_check(path: Path, relative: str) -> list[str]:
    """Return a list of problems (empty when the file looks usable)."""
    problems: list[str] = []
    data = path.read_bytes()
    if len(data) < 52 or data[:7] != b"\x7fELF\x01\x01\x01":
        return [f"{relative}: not a 32-bit little-endian ELF image"]
    machine, _entry, phoff = struct.unpack_from("<H4xII", data, 18)
    phentsize, phnum = struct.unpack_from("<HH", data, 42)
    if phentsize != 32 or phoff + phentsize * phnum > len(data):
        return [f"{relative}: invalid ELF program-header table"]
    expected_machine, base, limit = PROFILES[relative]
    if machine != expected_machine:
        problems.append(f"{relative}: ELF machine {machine}, expected {expected_machine}")
    loads = 0
    for index in range(phnum):
        p_type, _off, _va, physical, _fsz, memsz = struct.unpack_from(
            "<IIIIII", data, phoff + index * phentsize)
        if p_type != 1:
            continue
        loads += 1
        if physical < base or physical + memsz > limit:
            problems.append(
                f"{relative}: load segment {physical:#x}+{memsz:#x} is outside the "
                f"reserved window {base:#x}-{limit:#x}")
    if loads == 0:
        problems.append(f"{relative}: no loadable segment")
    return problems


def read_manifest(pack: Path) -> list[dict[str, str]]:
    manifest = pack / MANIFEST_NAME
    if manifest.is_symlink() or not manifest.is_file():
        raise Failure(f"{MANIFEST_NAME} is missing in {pack}")
    with manifest.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    if not rows or not {"path", "bytes", "sha256"} <= set(rows[0]):
        raise Failure("firmware manifest has an unexpected header")
    return rows


def validate_pack(pack: Path, quiet: bool = False) -> list[dict[str, str]]:
    """Validate a pack directory (usr/lib/firmware/... + manifest)."""
    rows = read_manifest(pack)
    paths = {row["path"] for row in rows}
    if paths != set(REQUIRED):
        missing = sorted(set(REQUIRED) - paths)
        extra = sorted(paths - set(REQUIRED))
        raise Failure(f"manifest must list exactly the five SP11 files "
                      f"(missing: {missing}, unexpected: {extra})")
    problems: list[str] = []
    packages: dict[str, set[str]] = {}
    for row in rows:
        relative = row["path"]
        if relative.startswith("/") or ".." in Path(relative).parts:
            raise Failure(f"unsafe path in manifest: {relative}")
        target = pack / "usr/lib/firmware" / relative
        if target.is_symlink() or not target.is_file():
            problems.append(f"{relative}: file missing from the pack")
            continue
        if not row["bytes"].isdigit() or target.stat().st_size != int(row["bytes"]):
            problems.append(f"{relative}: size differs from the manifest")
            continue
        if not re.fullmatch(r"[0-9a-f]{64}", row["sha256"]) or sha256(target) != row["sha256"]:
            problems.append(f"{relative}: SHA-256 differs from the manifest")
            continue
        problems.extend(elf_check(target, relative))
        component = REQUIRED[relative][0]
        package = row.get("source_package") or ""
        if package:
            packages.setdefault(component, set()).add(package)
    for component in ("adsp", "cdsp"):
        if len(packages.get(component, set())) > 1:
            problems.append(
                f"{component}: image and device tree come from different driver "
                f"packages ({', '.join(sorted(packages[component]))})")
    if problems:
        raise Failure("firmware pack rejected:\n  " + "\n  ".join(problems))
    if not quiet:
        log(f"Firmware pack OK: 5 files in {pack}")
    return rows


# --------------------------------------------------------------------------
# Candidate discovery
# --------------------------------------------------------------------------

class Candidate:
    def __init__(self, path: Path, package: str, package_rank: tuple, note: str):
        self.path = path
        self.package = package
        self.package_rank = package_rank
        self.note = note
        self.size = path.stat().st_size
        self.sha256 = sha256(path)

    @property
    def known(self) -> str:
        return KNOWN_GOOD.get(self.sha256, "")


def ci_child(directory: Path, name: str) -> Path | None:
    """Case-insensitive child lookup (NTFS mounted on Linux keeps stored case)."""
    direct = directory / name
    if direct.exists():
        return direct
    lowered = name.lower()
    try:
        for entry in directory.iterdir():
            if entry.name.lower() == lowered:
                return entry
    except OSError:
        return None
    return None


def parse_driver_version(package_dir: Path) -> tuple:
    """Rank key for a DriverStore package from its INF DriverVer line."""
    best: tuple = (0, 0, 0, ())
    for inf in package_dir.glob("*.inf"):
        try:
            raw = inf.read_bytes()
        except OSError:
            continue
        if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
            text = raw.decode("utf-16", errors="ignore")
        else:
            text = raw.decode("utf-8", errors="ignore")
        match = re.search(r"DriverVer\s*=\s*(\d{1,2})/(\d{1,2})/(\d{4})\s*,\s*([\d.]+)",
                          text, re.IGNORECASE)
        if not match:
            continue
        month, day, year, version = match.groups()
        version_tuple = tuple(int(part) for part in version.split(".") if part.isdigit())
        key = (int(year), int(month), int(day), version_tuple)
        best = max(best, key)
    return best


def version_text(rank: tuple) -> str:
    if not rank or rank[0] == 0:
        return "unknown version"
    year, month, day, version = rank
    return f"{year:04d}-{month:02d}-{day:02d} v{'.'.join(map(str, version))}"


def windows_root(directory: Path) -> Path | None:
    """Return the directory that contains Windows/System32, if any."""
    for candidate in (directory, directory / "Windows"):
        if candidate.name.lower() == "windows":
            system32 = ci_child(candidate, "System32")
            if system32 and system32.is_dir():
                return candidate.parent
        windows = ci_child(candidate, "Windows")
        if windows and windows.is_dir() and ci_child(windows, "System32"):
            return candidate
    return None


def find_in_windows(root: Path) -> dict[str, list[Candidate]]:
    windows = ci_child(root, "Windows")
    system32 = ci_child(windows, "System32") if windows else None
    store = ci_child(system32, "DriverStore") if system32 else None
    repository = ci_child(store, "FileRepository") if store else None
    if repository is None or not repository.is_dir():
        raise Failure(f"no Windows DriverStore below {root}")
    wanted = {name.lower(): relative for relative, (_c, names, _p) in REQUIRED.items()
              for name in names}
    found: dict[str, list[Candidate]] = {relative: [] for relative in REQUIRED}
    for package_dir in sorted(repository.iterdir()):
        if not package_dir.is_dir():
            continue
        hits = []
        try:
            for entry in package_dir.iterdir():
                if entry.is_file() and entry.name.lower() in wanted:
                    hits.append(entry)
        except OSError:
            continue
        if not hits:
            continue
        rank = parse_driver_version(package_dir)
        for entry in hits:
            relative = wanted[entry.name.lower()]
            found[relative].append(Candidate(
                entry, package_dir.name, rank,
                f"DriverStore {package_dir.name} ({version_text(rank)})"))
    deployed = ci_child(system32, "qcdxkmsuc8380.mbn") if system32 else None
    if deployed and deployed.is_file():
        found["qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn"].append(Candidate(
            deployed, "System32", (9999, 12, 31, ()), "Windows/System32 (currently deployed copy)"))
    return found


def find_in_linux_tree(root: Path) -> dict[str, list[Candidate]]:
    found: dict[str, list[Candidate]] = {relative: [] for relative in REQUIRED}
    for relative in REQUIRED:
        for base in (root / "usr/lib/firmware", root / "lib/firmware", root):
            target = base / relative
            if target.is_file() and not target.is_symlink():
                found[relative].append(Candidate(target, f"linux:{base}", (1, 1, 1, ()),
                                                 f"Linux firmware tree {base}"))
                break
    return found


def find_loose(root: Path) -> dict[str, list[Candidate]]:
    """Recursive search by file name; the containing directory is the package."""
    wanted = {name.lower(): relative for relative, (_c, names, _p) in REQUIRED.items()
              for name in names}
    found: dict[str, list[Candidate]] = {relative: [] for relative in REQUIRED}
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            if name.lower() in wanted:
                path = Path(dirpath) / name
                if path.is_symlink():
                    continue
                relative = wanted[name.lower()]
                found[relative].append(Candidate(
                    path, dirpath, (1, 1, 1, ()), f"directory {dirpath}"))
    return found


def select(found: dict[str, list[Candidate]], prefer_known: bool) -> dict[str, Candidate]:
    """Pick one candidate per required path, keeping DSP image+DTB coherent."""
    chosen: dict[str, Candidate] = {}
    by_component: dict[str, list[str]] = {}
    for relative, (component, _n, _p) in REQUIRED.items():
        by_component.setdefault(component, []).append(relative)
    for component, relatives in by_component.items():
        packages: dict[str, dict[str, Candidate]] = {}
        for relative in relatives:
            for candidate in found[relative]:
                packages.setdefault(candidate.package, {})
                current = packages[candidate.package].get(relative)
                if current is None or candidate.package_rank > current.package_rank:
                    packages[candidate.package][relative] = candidate
        complete = {name: members for name, members in packages.items()
                    if set(members) == set(relatives)}
        if not complete:
            missing = [relative for relative in relatives if not found[relative]]
            raise Failure(
                f"no driver package provides every {component.upper()} file "
                f"(missing: {missing or 'files present but split across packages'})")

        def key(item):
            name, members = item
            known = all(member.known for member in members.values())
            rank = max(member.package_rank for member in members.values())
            return ((known, rank) if prefer_known else (rank, known))
        _name, members = max(complete.items(), key=key)
        chosen.update(members)
    return chosen


# --------------------------------------------------------------------------
# Pack creation
# --------------------------------------------------------------------------

def write_pack(chosen: dict[str, Candidate], output: Path, source_text: str) -> None:
    firmware = output / "usr/lib/firmware"
    for relative, candidate in chosen.items():
        target = firmware / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(candidate.path, target)
        target.chmod(0o644)
    header = ["manifest_version", "path", "bytes", "sha256", "component",
              "source_package", "selection", "candidate_names", "purpose"]
    lines = ["\t".join(header)]
    report = [
        "Surface Pro 11 firmware pack",
        f"Created: {_dt.datetime.now(_dt.timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}",
        f"Source: {source_text}",
        "",
        "These files belong to Microsoft/Qualcomm and were copied from your own",
        "Windows installation. Do not upload or redistribute this directory.",
        "",
    ]
    for relative in REQUIRED:
        candidate = chosen[relative]
        component, names, purpose = REQUIRED[relative]
        selection = "known-good" if candidate.known else "newest-driver"
        lines.append("\t".join([
            "2", relative, str(candidate.size), candidate.sha256, component,
            candidate.package, selection, ",".join(names), purpose]))
        report.append(f"{relative}")
        report.append(f"    from: {candidate.path}")
        report.append(f"    {candidate.note}")
        report.append(f"    {candidate.size} bytes, sha256 {candidate.sha256}")
        report.append("    " + (f"known-good: {candidate.known}" if candidate.known
                                else "not seen on the maintainer's unit yet (that is normal "
                                     "after Windows Update); structurally validated"))
    (output / MANIFEST_NAME).write_text("\n".join(lines) + "\n", encoding="utf-8")
    (output / "README.txt").write_text(
        "SP11 external firmware pack\n\nThese files were copied from the device owner's "
        "Windows installation.\nDo not upload, publish, or redistribute this directory.\n",
        encoding="utf-8")
    (output / REPORT_NAME).write_text("\n".join(report) + "\n", encoding="utf-8")


def print_selection(chosen: dict[str, Candidate]) -> None:
    log("Selected firmware:")
    for relative in REQUIRED:
        candidate = chosen[relative]
        flag = "known-good" if candidate.known else "new (validated)"
        log(f"  {relative}")
        log(f"      {candidate.note} [{flag}]")


# --------------------------------------------------------------------------
# Windows partition handling
# --------------------------------------------------------------------------

def lsblk() -> list[dict]:
    result = run(["lsblk", "-J", "-o", "PATH,FSTYPE,LABEL,SIZE,MOUNTPOINTS,TYPE,PKNAME,RM,TRAN"])
    if result.returncode != 0:
        raise Failure("lsblk failed: " + result.stderr.strip())
    devices: list[dict] = []

    def walk(nodes):
        for node in nodes:
            devices.append(node)
            walk(node.get("children", []))
    walk(json.loads(result.stdout).get("blockdevices", []))
    return devices


def windows_partitions() -> list[dict]:
    parts = []
    for device in lsblk():
        fstype = (device.get("fstype") or "").lower()
        if device.get("type") == "part" and fstype in ("ntfs", "bitlocker"):
            parts.append(device)
    return parts


class MountedWindows:
    """Context manager: mount an NTFS partition read-only if needed."""

    def __init__(self, device: str):
        self.device = device
        self.mountpoint: Path | None = None
        self.mounted_here = False

    def __enter__(self) -> Path:
        for entry in lsblk():
            if entry.get("path") == self.device:
                existing = [m for m in (entry.get("mountpoints") or []) if m]
                if existing:
                    self.mountpoint = Path(existing[0])
                    return self.mountpoint
                if (entry.get("fstype") or "").lower() == "bitlocker":
                    raise Failure(
                        f"{self.device} is BitLocker-encrypted. Either run RUN-IN-WINDOWS.cmd "
                        "from Windows (recommended), or disable BitLocker in Windows and retry.")
        if not is_root():
            raise Failure(f"mounting {self.device} needs root: rerun with sudo")
        self.mountpoint = Path(tempfile.mkdtemp(prefix="sp11-windows."))
        attempts = (
            ["mount", "-t", "ntfs3", "-o", "ro,noatime", self.device, str(self.mountpoint)],
            ["mount", "-t", "ntfs", "-o", "ro", self.device, str(self.mountpoint)],
            ["ntfs-3g", "-o", "ro", self.device, str(self.mountpoint)],
        )
        errors = []
        for command in attempts:
            if shutil.which(command[0]) is None:
                continue
            result = run(command)
            if result.returncode == 0:
                self.mounted_here = True
                return self.mountpoint
            errors.append(result.stderr.strip())
        self.mountpoint.rmdir()
        raise Failure(
            f"could not mount {self.device} read-only. If Windows was not shut down cleanly "
            "(Fast Startup/hibernation), boot Windows and shut it down fully, or run "
            "RUN-IN-WINDOWS.cmd instead. Details: " + " | ".join(e for e in errors if e))

    def __exit__(self, *_exc) -> None:
        if self.mounted_here and self.mountpoint:
            run(["umount", str(self.mountpoint)])
            try:
                self.mountpoint.rmdir()
            except OSError:
                pass


# --------------------------------------------------------------------------
# SP11FW (live USB companion partition)
# --------------------------------------------------------------------------

def sp11fw_device() -> str | None:
    link = Path("/dev/disk/by-label/SP11FW")
    if link.exists():
        return os.path.realpath(link)
    for device in lsblk():
        if device.get("label") == "SP11FW" and device.get("type") == "part":
            return device["path"]
    return None


class MountedSP11FW:
    def __init__(self):
        self.mountpoint: Path | None = None
        self.mounted_here = False

    def __enter__(self) -> Path:
        device = sp11fw_device()
        if device is None:
            raise Failure("no partition labelled SP11FW is attached (plug in the live USB)")
        for entry in lsblk():
            if entry.get("path") == device:
                existing = [m for m in (entry.get("mountpoints") or []) if m]
                if existing:
                    self.mountpoint = Path(existing[0])
                    if not os.access(self.mountpoint, os.W_OK):
                        raise Failure(f"{self.mountpoint} is not writable; rerun with sudo")
                    return self.mountpoint
        if not is_root():
            raise Failure("mounting SP11FW needs root: rerun with sudo")
        self.mountpoint = Path(tempfile.mkdtemp(prefix="sp11fw."))
        result = run(["mount", "-o", "rw", device, str(self.mountpoint)])
        if result.returncode != 0:
            self.mountpoint.rmdir()
            raise Failure("mount SP11FW failed: " + result.stderr.strip())
        self.mounted_here = True
        return self.mountpoint

    def __exit__(self, *_exc) -> None:
        if self.mountpoint:
            run(["sync", "-f", str(self.mountpoint)])
        if self.mounted_here and self.mountpoint:
            run(["umount", str(self.mountpoint)])
            try:
                self.mountpoint.rmdir()
            except OSError:
                pass


def copy_pack(pack: Path, destination: Path) -> None:
    for relative in REQUIRED:
        source = pack / "usr/lib/firmware" / relative
        target = destination / "usr/lib/firmware" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        try:
            target.chmod(0o644)
        except OSError:
            pass  # FAT
    for name in (MANIFEST_NAME, "README.txt", REPORT_NAME):
        if (pack / name).is_file():
            shutil.copyfile(pack / name, destination / name)


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------

def collect_from_source(args) -> tuple[dict[str, Candidate], str]:
    """Return (chosen, description) according to --from-* options."""
    if args.from_dir:
        root = Path(args.from_dir).resolve()
        if not root.is_dir():
            raise Failure(f"not a directory: {root}")
        win = windows_root(root)
        if win is not None:
            found = find_in_windows(win)
            source = f"Windows tree at {win}"
        else:
            found = find_in_linux_tree(root)
            if not all(found.values()):
                found = find_loose(root)
            source = f"directory {root}"
        return select(found, args.prefer_known), source
    if args.from_running:
        found = find_in_linux_tree(Path("/"))
        return select(found, args.prefer_known), "running system /usr/lib/firmware"
    if args.download:
        return download_qrd(args), f"{QRD_REPO} ({QRD_DEVICE})"
    device = args.from_windows
    if device in (None, "auto"):
        parts = windows_partitions()
        if not parts:
            raise Failure("no NTFS/BitLocker partition found. Use --from-dir, --download, "
                          "or run RUN-IN-WINDOWS.cmd from Windows.")
        internal = [p for p in parts if not p.get("rm")]
        parts = internal or parts
        parts.sort(key=lambda p: p.get("size") or "", reverse=True)
        device = parts[0]["path"]
        if len(parts) > 1:
            log(f"Several Windows-style partitions found; using {device} "
                f"({parts[0].get('size')}). Pass --from-windows DEVICE to choose another.")
    with MountedWindows(device) as mountpoint:
        win = windows_root(mountpoint)
        if win is None:
            raise Failure(f"{device} does not contain a Windows installation")
        found = find_in_windows(win)
        chosen = select(found, args.prefer_known)
        # Copy now, while the partition is mounted.
        staging = Path(tempfile.mkdtemp(prefix="sp11-firmware-stage."))
        write_pack(chosen, staging, f"Windows partition {device}")
        chosen = {relative: Candidate(staging / "usr/lib/firmware" / relative,
                                      candidate.package, candidate.package_rank, candidate.note)
                  for relative, candidate in chosen.items()}
        return chosen, f"Windows partition {device}"


def download_qrd(args) -> dict[str, Candidate]:
    if shutil.which("cabextract") is None:
        raise Failure("cabextract is required for --download (pacman -S cabextract)")
    api = f"https://api.github.com/repos/{QRD_REPO}/contents/{QRD_DEVICE}"
    with urllib.request.urlopen(api, timeout=60) as response:
        entries = json.load(response)
    versions = [e["name"] for e in entries if e.get("type") == "dir"]
    if not versions:
        raise Failure("no driver versions listed in the QRD repository")

    def version_key(name):
        return tuple(int(p) if p.isdigit() else 0 for p in name.split("."))
    version = args.download if args.download not in ("latest", True) else max(versions, key=version_key)
    if version not in versions:
        raise Failure(f"version {version} not available; choose from {', '.join(versions)}")
    log(f"Downloading driver package listing {version} ...")
    with urllib.request.urlopen(f"{api}/{version}", timeout=60) as response:
        files = [e for e in json.load(response) if e.get("type") == "file"]
    wanted_names = {name.lower() for _c, names, _p in REQUIRED.values() for name in names}
    work = Path(tempfile.mkdtemp(prefix="sp11-qrd."))
    cabs = [e for e in files if e["name"].lower().endswith(".cab") and
            re.search(r"adsp|cdsp|qcdx|dsp", e["name"], re.IGNORECASE)]
    for entry in cabs:
        target = work / entry["name"]
        log(f"  {entry['name']} ({entry.get('size', 0) // 1024} KiB)")
        urllib.request.urlretrieve(entry["download_url"], target)
        listing = run(["cabextract", "-l", str(target)]).stdout
        if not any(name in listing.lower() for name in wanted_names):
            target.unlink()
            continue
        extract_dir = work / target.stem
        extract_dir.mkdir()
        run(["cabextract", "-q", "-d", str(extract_dir), str(target)])
    found = find_loose(work)
    return select(found, args.prefer_known)


def cmd_collect(args) -> int:
    chosen, source = collect_from_source(args)
    print_selection(chosen)
    if args.to_usb:
        with MountedSP11FW() as sp11fw:
            staging = Path(tempfile.mkdtemp(prefix="sp11-firmware-pack."))
            write_pack(chosen, staging, source)
            validate_pack(staging, quiet=True)
            copy_pack(staging, sp11fw)
            shutil.rmtree(staging, ignore_errors=True)
            log(f"\nFirmware pack written to the live USB partition SP11FW ({sp11fw}).")
            log("It is picked up automatically the next time the live USB boots.")
        return 0
    output = Path(args.output or "./SP11-FIRMWARE").resolve()
    if output.exists():
        if args.force:
            shutil.rmtree(output)
        else:
            raise Failure(f"{output} already exists (use --force to replace it)")
    output.mkdir(parents=True)
    write_pack(chosen, output, source)
    validate_pack(output, quiet=True)
    log(f"\nFirmware pack written to {output}")
    log("Copy its contents to the SP11FW partition of the live USB, or run "
        "'sudo sp11-firmware install --pack <dir>' on an installed SP11 system.")
    return 0


def cmd_validate(args) -> int:
    validate_pack(Path(args.pack).resolve())
    return 0


def restart_dsps() -> None:
    for entry in sorted(Path("/sys/class/remoteproc").glob("remoteproc*")):
        try:
            name = (entry / "name").read_text().strip()
            state = (entry / "state").read_text().strip()
        except OSError:
            continue
        if name not in ("adsp", "cdsp"):
            continue
        log(f"Restarting {name} (was {state}) ...")
        try:
            if state == "running":
                (entry / "state").write_text("stop")
                time.sleep(1)
            (entry / "state").write_text("start")
            time.sleep(2)
            log(f"  {name}: {(entry / 'state').read_text().strip()}")
        except OSError as error:
            log(f"  {name}: {error}")


def install_pack(pack: Path, root: Path, restart: bool, source: str) -> None:
    rows = validate_pack(pack, quiet=True)
    firmware = root / "usr/lib/firmware"
    for row in rows:
        target = firmware / row["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        backup = target.with_suffix(target.suffix + ".previous")
        if target.is_file() and sha256(target) != row["sha256"]:
            shutil.copyfile(target, backup)
        shutil.copyfile(pack / "usr/lib/firmware" / row["path"], target)
        target.chmod(0o644)
    etc = root / "etc"
    etc.mkdir(exist_ok=True)
    (etc / MARKER.name).write_text(
        f"SP11 owner firmware installed by sp11-firmware from {source}\n" +
        "".join(f"{row['path']}\t{row['sha256']}\n" for row in rows), encoding="utf-8")
    shutil.copyfile(pack / MANIFEST_NAME, etc / MARKER_MANIFEST.name)
    log(f"Installed 5 firmware files into {firmware}")
    if restart and root == Path("/"):
        restart_dsps()
        log("Audio/DSPs restarted. GPU acceleration takes effect at the next login "
            "(log out/in) or reboot.")


def cmd_install(args) -> int:
    if not is_root():
        raise Failure("install needs root: rerun with sudo")
    root = Path(args.root).resolve()
    if args.pack:
        pack = Path(args.pack).resolve()
        source = f"pack {pack}"
    else:
        chosen, source = collect_from_source(args)
        print_selection(chosen)
        pack = Path(tempfile.mkdtemp(prefix="sp11-firmware-pack."))
        write_pack(chosen, pack, source)
    install_pack(pack, root, restart=not args.no_restart, source=source)
    if root != Path("/"):
        log(f"Files placed under {root}; no services were restarted.")
    return 0


def cmd_import_live(args) -> int:
    """Boot-time fallback used by sp11-firmware-import.service on the live image."""
    if MARKER.is_file():
        log("Owner firmware already active (marker present); nothing to do.")
        return 0
    if not is_root():
        raise Failure("import-live needs root")
    deadline = time.monotonic() + args.wait
    device = None
    while time.monotonic() < deadline:
        device = sp11fw_device()
        if device:
            break
        time.sleep(1)
    if device is None:
        log("No SP11FW partition found; continuing without owner firmware.")
        return 0
    mountpoint = Path(tempfile.mkdtemp(prefix="sp11fw-import."))
    result = run(["mount", "-o", "ro", device, str(mountpoint)])
    if result.returncode != 0:
        log("Could not mount SP11FW: " + result.stderr.strip())
        return 0
    try:
        try:
            install_pack(mountpoint, Path("/"), restart=True, source=f"SP11FW ({device})")
        except Failure as error:
            log(str(error))
            log("Run RUN-IN-WINDOWS.cmd or 'sudo sp11-firmware collect --to-usb' to fix the pack.")
            return 0
    finally:
        run(["umount", str(mountpoint)])
        mountpoint.rmdir()
    return 0


def cmd_status(_args) -> int:
    log("Owner firmware files:")
    complete = True
    for relative in REQUIRED:
        target = FIRMWARE_ROOT / relative
        if target.is_file():
            digest = sha256(target)
            note = KNOWN_GOOD.get(digest, "not seen on the maintainer's unit (fine if it works)")
            log(f"  present  {relative}\n           {digest[:16]}…  {note}")
        else:
            complete = False
            log(f"  MISSING  {relative}")
    log(f"Marker {MARKER}: {'present' if MARKER.is_file() else 'absent'}")
    status = Path("/etc/sp11-external-firmware-status")
    if status.is_file():
        log("Boot import trail:")
        for line in status.read_text(errors="replace").splitlines():
            log(f"  {line}")
    remoteprocs = sorted(Path("/sys/class/remoteproc").glob("remoteproc*"))
    if remoteprocs:
        log("DSP state:")
        for entry in remoteprocs:
            try:
                log(f"  {(entry / 'name').read_text().strip():6s} {(entry / 'state').read_text().strip()}")
            except OSError:
                pass
    cards = Path("/proc/asound/cards")
    if cards.is_file():
        text = cards.read_text().strip()
        log("Sound cards: " + (text.splitlines()[0].strip() if text and "no soundcards" not in text
                               else "none (ADSP firmware missing or not started)"))
    log("Windows partitions visible: " +
        (", ".join(f"{p['path']} ({p['fstype']})" for p in windows_partitions()) or "none"))
    if not complete:
        log("\nTo fix: run RUN-IN-WINDOWS.cmd from Windows, or "
            "'sudo sp11-firmware install --from-windows' from Linux.")
    return 0 if complete else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="sp11-firmware",
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    def add_sources(p):
        group = p.add_mutually_exclusive_group()
        group.add_argument("--from-windows", metavar="DEVICE", nargs="?", const="auto",
                           help="read the Windows partition (default: auto-detect the largest NTFS partition)")
        group.add_argument("--from-dir", metavar="DIR",
                           help="a mounted Windows tree, a Linux firmware tree, or a directory of loose files")
        group.add_argument("--from-running", action="store_true",
                           help="reuse the files already installed on this Linux system")
        group.add_argument("--download", metavar="VERSION", nargs="?", const="latest",
                           help=f"fetch Qualcomm reference driver cabs from github.com/{QRD_REPO} (needs cabextract)")
        p.add_argument("--prefer-known", action="store_true",
                       help="prefer hashes seen on the maintainer's unit over the newest driver package")

    collect = sub.add_parser("collect", help="build a firmware pack (default source: Windows partition)")
    add_sources(collect)
    collect.add_argument("--output", "-o", metavar="DIR", help="pack directory (default ./SP11-FIRMWARE)")
    collect.add_argument("--to-usb", action="store_true", help="write straight onto the live USB's SP11FW partition")
    collect.add_argument("--force", action="store_true", help="replace an existing output directory")
    collect.set_defaults(func=cmd_collect)

    install = sub.add_parser("install", help="install firmware into a Linux system (root)")
    add_sources(install)
    install.add_argument("--pack", metavar="DIR", help="install from an existing pack instead of a source")
    install.add_argument("--root", default="/", help="target root (default /; e.g. a mounted install)")
    install.add_argument("--no-restart", action="store_true", help="do not restart the DSPs afterwards")
    install.set_defaults(func=cmd_install)

    validate = sub.add_parser("validate", help="check a pack directory")
    validate.add_argument("pack")
    validate.set_defaults(func=cmd_validate)

    status = sub.add_parser("status", help="show what is installed and working")
    status.set_defaults(func=cmd_status)

    live = sub.add_parser("import-live", help="boot-time import from SP11FW (used by the live image)")
    live.add_argument("--wait", type=int, default=20, help="seconds to wait for SP11FW")
    live.set_defaults(func=cmd_import_live)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    # `collect` / `install` default to the Windows partition when no source is given.
    if args.command in ("collect", "install") and not (
            args.from_windows or args.from_dir or args.from_running or args.download
            or getattr(args, "pack", None)):
        args.from_windows = "auto"
    try:
        return args.func(args)
    except Failure as error:
        print(f"sp11-firmware: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
