#!/usr/bin/env python3

"""Create the deterministic installed-root file identity manifest."""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
from pathlib import Path
from typing import Iterator


def walk(root: Path) -> Iterator[tuple[str, Path]]:
    pending: list[tuple[str, Path]] = []
    for directory, names, filenames in os.walk(root, topdown=True, followlinks=False):
        names.sort(key=os.fsencode)
        filenames.sort(key=os.fsencode)
        directory_path = Path(directory)
        for name in names + filenames:
            path = directory_path / name
            relative = path.relative_to(root).as_posix()
            if any(character in relative for character in "\t\r\n"):
                raise ValueError(f"manifest-unsafe path: {relative!r}")
            pending.append((relative, path))
    pending.sort(key=lambda item: os.fsencode(item[0]))
    yield from pending


def file_hash(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def type_name(mode: int) -> str:
    if stat.S_ISREG(mode):
        return "regular file"
    if stat.S_ISDIR(mode):
        return "directory"
    if stat.S_ISLNK(mode):
        return "symbolic link"
    if stat.S_ISFIFO(mode):
        return "fifo"
    if stat.S_ISSOCK(mode):
        return "socket"
    if stat.S_ISBLK(mode):
        return "block special file"
    if stat.S_ISCHR(mode):
        return "character special file"
    return "unknown"


def portable_size(kind: str, metadata: os.stat_result) -> int:
    """Return only sizes that survive archive extraction across filesystems."""
    if kind in {"regular file", "symbolic link"}:
        return metadata.st_size
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve(strict=True)
    if not root.is_dir() or root.is_symlink():
        raise ValueError(f"unsafe root directory: {root}")
    if args.output.exists() or args.output.is_symlink():
        raise ValueError(f"output already exists: {args.output}")

    with args.output.open("x", encoding="utf-8", newline="\n") as output:
        output.write("path\ttype\tmode\tuid\tgid\tbytes\tidentity\n")
        for relative, path in walk(root):
            metadata = path.lstat()
            kind = type_name(metadata.st_mode)
            if kind == "regular file":
                identity = file_hash(path)
            elif kind == "symbolic link":
                identity = os.readlink(path)
                if any(character in identity for character in "\t\r\n"):
                    raise ValueError(f"manifest-unsafe symlink target: {relative!r}")
            else:
                identity = "-"
            output.write(
                f"{relative}\t{kind}\t"
                f"{stat.S_IMODE(metadata.st_mode):o}\t"
                f"{metadata.st_uid}\t{metadata.st_gid}\t"
                f"{portable_size(kind, metadata)}\t{identity}\n"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
