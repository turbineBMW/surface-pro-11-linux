#!/usr/bin/env python3

"""Unit tests for fail-closed SP11 executor boot-entry validation."""

from __future__ import annotations

import importlib.util
import subprocess
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).with_name("sp11-install-executor.py")
SPEC = importlib.util.spec_from_file_location("sp11_install_executor", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
EXECUTOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXECUTOR)

ESP = {
    "number": 4,
    "partuuid": "2909e69c-5684-4bc7-b772-ea841a830ec1",
}
VALID_OUTPUT = """\
BootCurrent: 0005
Timeout: 0 seconds
BootOrder: 0005,0001,0000,0004,0002
Boot0001* USB Storage\tFvVol(example)
Boot0004* Windows Boot Manager\tHD(1,GPT,e614bfd1-2a82-4a46-ab27-0b777b8971dc,0x800,0x96000)/\\EFI\\Microsoft\\Boot\\bootmgfw.efi
Boot0005* SP11 Linux\tHD(4,GPT,2909e69c-5684-4bc7-b772-ea841a830ec1,0x15679800,0x200000)/\\EFI\\BOOT\\BOOTAA64.EFI
"""


class UefiBootEntryTests(unittest.TestCase):
    def test_run_lets_input_create_stdin_pipe(self) -> None:
        with mock.patch.object(EXECUTOR.subprocess, "run") as run_mock:
            EXECUTOR.run(["example"], input_text="partition script\n")

        self.assertEqual(run_mock.call_args.kwargs["input"], "partition script\n")
        self.assertIsNone(run_mock.call_args.kwargs["stdin"])

    def test_run_closes_stdin_without_input(self) -> None:
        with mock.patch.object(EXECUTOR.subprocess, "run") as run_mock:
            EXECUTOR.run(["example"])

        self.assertIsNone(run_mock.call_args.kwargs["input"])
        self.assertIs(run_mock.call_args.kwargs["stdin"], subprocess.DEVNULL)

    def test_accepts_active_first_exact_esp_and_arm64_loader(self) -> None:
        state = EXECUTOR.parse_uefi_boot_state(VALID_OUTPUT)
        EXECUTOR.assert_linux_uefi_entry(state, "0005", ESP)

    def test_rejects_fallback_file_without_persistent_entry(self) -> None:
        state = EXECUTOR.parse_uefi_boot_state(
            VALID_OUTPUT.replace(
                "Boot0005* SP11 Linux\tHD(4,GPT,2909e69c-5684-4bc7-b772-ea841a830ec1,0x15679800,0x200000)/\\EFI\\BOOT\\BOOTAA64.EFI\n",
                "",
            )
        )
        with self.assertRaisesRegex(
            EXECUTOR.ExecutorRefusal, "persistent SP11 Linux UEFI entry"
        ):
            EXECUTOR.assert_linux_uefi_entry(state, "0005", ESP)

    def test_rejects_duplicate_sp11_entries(self) -> None:
        state = EXECUTOR.parse_uefi_boot_state(
            VALID_OUTPUT
            + VALID_OUTPUT.splitlines()[-1].replace("0005", "0006")
            + "\n"
        )
        with self.assertRaisesRegex(
            EXECUTOR.ExecutorRefusal, "persistent SP11 Linux UEFI entry"
        ):
            EXECUTOR.assert_linux_uefi_entry(state, "0005", ESP)

    def test_rejects_wrong_partition_or_loader(self) -> None:
        for changed in (
            VALID_OUTPUT.replace("HD(4,GPT", "HD(1,GPT"),
            VALID_OUTPUT.replace("BOOTAA64.EFI", "grubaa64.efi"),
            VALID_OUTPUT.replace("Boot0005*", "Boot0005"),
            VALID_OUTPUT.replace(
                "BootOrder: 0005,0001,0000,0004,0002",
                "BootOrder: 0001,0005,0000,0004,0002",
            ),
        ):
            with self.subTest(output=changed):
                state = EXECUTOR.parse_uefi_boot_state(changed)
                with self.assertRaises(EXECUTOR.ExecutorRefusal):
                    EXECUTOR.assert_linux_uefi_entry(state, "0005", ESP)

    def test_rejects_missing_boot_order(self) -> None:
        with self.assertRaisesRegex(
            EXECUTOR.ExecutorRefusal, "BootOrder is unavailable"
        ):
            EXECUTOR.parse_uefi_boot_state("Boot0005* SP11 Linux\tHD(...)\n")

    def provision_with_states(
        self, states: list[dict[str, object]]
    ) -> tuple[dict[str, object], list[list[str]]]:
        commands: list[list[str]] = []

        def fake_run(arguments: list[str], **_kwargs: object) -> object:
            commands.append(arguments)
            return object()

        with (
            mock.patch.object(
                EXECUTOR, "read_uefi_boot_state", side_effect=states
            ),
            mock.patch.object(EXECUTOR, "run", side_effect=fake_run),
        ):
            record = EXECUTOR.provision_linux_uefi_entry("/dev/nvme0n1", ESP)
        return record, commands

    def test_provisions_fresh_entry_and_preserves_order(self) -> None:
        before = {"order": ["0001", "0004"], "linux_entries": []}
        created = {
            "order": ["0006", "0001", "0004"],
            "linux_entries": [{"number": "0006"}],
        }
        final = EXECUTOR.parse_uefi_boot_state(
            VALID_OUTPUT.replace("0005", "0006")
            .replace("0006,0001,0000,0004,0002", "0006,0001,0004")
        )
        record, commands = self.provision_with_states([before, created, final])
        self.assertEqual(record["replaced_entry_numbers"], [])
        self.assertEqual(
            commands[-1],
            ["efibootmgr", "--bootorder", "0006,0001,0004"],
        )

    def test_replaces_one_stale_entry(self) -> None:
        before = EXECUTOR.parse_uefi_boot_state(VALID_OUTPUT)
        created = {
            "order": ["0006", "0001", "0000", "0004", "0002"],
            "linux_entries": [{"number": "0006"}],
        }
        final = EXECUTOR.parse_uefi_boot_state(
            VALID_OUTPUT.replace("0005", "0006").replace(
                "2909e69c-5684-4bc7-b772-ea841a830ec1",
                ESP["partuuid"],
            )
        )
        record, commands = self.provision_with_states([before, created, final])
        self.assertEqual(record["replaced_entry_numbers"], ["0005"])
        self.assertEqual(
            record["original_boot_order"],
            ["0001", "0000", "0004", "0002"],
        )
        self.assertEqual(record["observed_boot_order"], before["order"])
        self.assertEqual(
            commands[0],
            ["efibootmgr", "--bootnum", "0005", "--delete-bootnum"],
        )
        self.assertEqual(
            commands[-1],
            ["efibootmgr", "--bootorder", "0006,0001,0000,0004,0002"],
        )

    def test_replaces_duplicate_stale_entries(self) -> None:
        duplicate = VALID_OUTPUT.replace(
            "Boot0005* SP11 Linux",
            "Boot0003* SP11 Linux",
        ).replace(
            "BootOrder: 0005,0001,0000,0004,0002",
            "BootOrder: 0003,0001,0005,0000,0004,0002",
        ) + VALID_OUTPUT.splitlines()[-1] + "\n"
        before = EXECUTOR.parse_uefi_boot_state(duplicate)
        created = {
            "order": ["0006", "0001", "0000", "0004", "0002"],
            "linux_entries": [{"number": "0006"}],
        }
        final = EXECUTOR.parse_uefi_boot_state(
            VALID_OUTPUT.replace("0005", "0006")
        )
        record, commands = self.provision_with_states([before, created, final])
        self.assertEqual(record["replaced_entry_numbers"], ["0003", "0005"])
        self.assertEqual(
            commands[-1],
            ["efibootmgr", "--bootorder", "0006,0001,0000,0004,0002"],
        )

    def test_failed_replacement_removes_partial_entry_and_retains_windows(self) -> None:
        before = EXECUTOR.parse_uefi_boot_state(VALID_OUTPUT)
        partial = {
            "order": ["0006", "0001", "0000", "0004", "0002"],
            "linux_entries": [{"number": "0006"}],
        }
        cleanup_commands: list[list[str]] = []
        with (
            mock.patch.object(
                EXECUTOR,
                "read_uefi_boot_state",
                side_effect=[before, RuntimeError("create read failed"), partial],
            ),
            mock.patch.object(EXECUTOR, "run") as run_mock,
            mock.patch.object(
                EXECUTOR.subprocess,
                "run",
                side_effect=lambda args, **_kwargs: cleanup_commands.append(args),
            ),
        ):
            with self.assertRaisesRegex(RuntimeError, "create read failed"):
                EXECUTOR.provision_linux_uefi_entry("/dev/nvme0n1", ESP)
        self.assertIn(
            ["efibootmgr", "--bootnum", "0006", "--delete-bootnum"],
            cleanup_commands,
        )
        self.assertEqual(
            cleanup_commands[-1],
            ["efibootmgr", "--bootorder", "0001,0000,0004,0002"],
        )
        deleted_by_checked_commands = [
            call.args[0][2]
            for call in run_mock.call_args_list
            if "--delete-bootnum" in call.args[0]
        ]
        self.assertNotIn("0004", deleted_by_checked_commands)


if __name__ == "__main__":
    unittest.main(verbosity=2)
