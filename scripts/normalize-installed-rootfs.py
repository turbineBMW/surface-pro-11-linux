#!/usr/bin/env python3

"""Normalize generated package metadata in an installed-root staging tree."""

from __future__ import annotations

import argparse
import os
import stat
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--source-date-epoch", type=int, required=True)
    parser.add_argument("--expected-packages", type=int, required=True)
    return parser.parse_args()


def normalize_install_date(path: Path, source_date_epoch: int) -> None:
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
        raise ValueError(f"unsafe pacman metadata file: {path}")

    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    markers = [index for index, line in enumerate(lines) if line == "%INSTALLDATE%\n"]
    if len(markers) != 1 or markers[0] + 1 >= len(lines):
        raise ValueError(f"unexpected INSTALLDATE structure: {path}")

    value_index = markers[0] + 1
    if not lines[value_index].removesuffix("\n").isdigit():
        raise ValueError(f"invalid INSTALLDATE value: {path}")
    lines[value_index] = f"{source_date_epoch}\n"

    temporary = path.with_name(f".{path.name}.sp11-normalize-{os.getpid()}")
    try:
        with temporary.open("x", encoding="utf-8", newline="") as output:
            output.writelines(lines)
        os.chmod(temporary, stat.S_IMODE(metadata.st_mode))
        os.chown(temporary, metadata.st_uid, metadata.st_gid)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def main() -> int:
    args = parse_args()
    root = args.root.resolve(strict=True)
    if not root.is_dir() or root.is_symlink():
        raise ValueError(f"unsafe root directory: {root}")
    if args.source_date_epoch <= 0 or args.expected_packages <= 0:
        raise ValueError("epoch and expected package count must be positive")

    package_database = root / "var/lib/pacman/local"
    descriptions = sorted(package_database.glob("*/desc"), key=os.fspath)
    if len(descriptions) != args.expected_packages:
        raise ValueError(
            "unexpected pacman description count: "
            f"{len(descriptions)} != {args.expected_packages}"
        )
    for description in descriptions:
        normalize_install_date(description, args.source_date_epoch)

    print(f"Normalized INSTALLDATE in {len(descriptions)} package records.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
