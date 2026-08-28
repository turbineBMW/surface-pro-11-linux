#!/usr/bin/env python3

"""Regression tests for portable installed-root manifest identities."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("manifest-installed-rootfs.py")
SPEC = importlib.util.spec_from_file_location("manifest_installed_rootfs", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MANIFEST = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MANIFEST)


class ManifestTests(unittest.TestCase):
    def test_directory_allocation_size_is_not_an_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            directory = root / "directory"
            directory.mkdir()
            for index in range(128):
                (directory / f"entry-{index:03d}").write_bytes(b"x")

            metadata = directory.lstat()
            self.assertGreater(metadata.st_size, 0)
            self.assertEqual(MANIFEST.portable_size("directory", metadata), 0)

    def test_file_and_symlink_sizes_remain_exact(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            regular = root / "regular"
            regular.write_bytes(b"content")
            link = root / "link"
            link.symlink_to("regular")

            self.assertEqual(
                MANIFEST.portable_size("regular file", regular.lstat()),
                len(b"content"),
            )
            self.assertEqual(
                MANIFEST.portable_size("symbolic link", link.lstat()),
                len("regular"),
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
