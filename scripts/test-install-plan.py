#!/usr/bin/env python3

"""Regression tests for the read-only SP11 fresh-install planner."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Any


SCRIPT = Path(__file__).with_name("sp11-install-plan.py")
MIB = 1024**2
GIB = 1024**3
SECTOR = 512

ESP_GUID = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
MSR_GUID = "e3c9e316-0b5c-4db8-817d-f92df00215ae"
BASIC_GUID = "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7"
RECOVERY_GUID = "de94bba4-06d1-4d40-a16a-bfd50179d6ac"
LINUX_GUID = "0fc63daf-8483-4772-8e79-3d69d8477de4"


def partition(
    number: int,
    start: int,
    size: int,
    parttype: str,
    fstype: str | None,
    label: str,
    mountpoints: list[str] | None = None,
    partlabel: str = "",
) -> dict[str, Any]:
    return {
        "name": f"nvme0n1p{number}",
        "path": f"/dev/nvme0n1p{number}",
        "type": "part",
        "size": size,
        "start": start // SECTOR,
        "log-sec": SECTOR,
        "phy-sec": 4096,
        "min-io": 4096,
        "opt-io": 65536,
        "alignment": 0,
        "ro": False,
        "rm": False,
        "hotplug": False,
        "tran": None,
        "model": None,
        "serial": None,
        "pttype": "gpt",
        "ptuuid": "11111111-2222-3333-4444-555555555555",
        "fstype": fstype,
        "fsver": None,
        "label": label,
        "uuid": f"FS-{number}",
        "parttype": parttype,
        "parttypename": None,
        "partuuid": f"00000000-0000-0000-0000-{number:012d}",
        "partlabel": partlabel,
        "partn": number,
        "pkname": "nvme0n1",
        "mountpoints": mountpoints or [],
    }


def factory_inventory(
    *,
    free_space: int = 200 * GIB,
    mounted: bool = False,
    transport: str = "nvme",
    removable: bool = False,
    hotplug: bool = False,
    include_linux: bool = False,
) -> dict[str, Any]:
    esp_start = MIB
    esp_size = 260 * MIB
    msr_start = esp_start + esp_size
    msr_size = 16 * MIB
    windows_start = msr_start + msr_size
    windows_size = 500 * GIB
    free_start = windows_start + windows_size
    recovery_start = free_start + free_space
    recovery_size = 2 * GIB
    disk_size = recovery_start + recovery_size + MIB
    children = [
        partition(1, esp_start, esp_size, ESP_GUID, "vfat", "SYSTEM"),
        partition(2, msr_start, msr_size, MSR_GUID, None, ""),
        partition(
            3,
            windows_start,
            windows_size,
            BASIC_GUID,
            "BitLocker",
            "Windows",
        ),
    ]
    if include_linux:
        children.append(
            partition(
                5,
                free_start,
                free_space,
                LINUX_GUID,
                "ext4",
                "sp11root",
                ["/"] if mounted else [],
            )
        )
    children.append(
        partition(
            4,
            recovery_start,
            recovery_size,
            RECOVERY_GUID,
            "ntfs",
            "Windows RE tools",
        )
    )
    return {
        "blockdevices": [
            {
                "name": "nvme0n1",
                "path": "/dev/nvme0n1",
                "type": "disk",
                "size": disk_size,
                "start": None,
                "log-sec": SECTOR,
                "phy-sec": 4096,
                "min-io": 4096,
                "opt-io": 65536,
                "alignment": 0,
                "ro": False,
                "rm": removable,
                "hotplug": hotplug,
                "tran": transport,
                "model": "Synthetic Surface NVMe",
                "serial": "TESTSERIAL123",
                "pttype": "gpt",
                "ptuuid": "11111111-2222-3333-4444-555555555555",
                "fstype": None,
                "fsver": None,
                "label": None,
                "uuid": None,
                "parttype": None,
                "parttypename": None,
                "partuuid": None,
                "partn": None,
                "pkname": None,
                "mountpoints": [],
                "children": children,
            }
        ]
    }


def terminal_reclaim_inventory(*, mounted: bool = False) -> dict[str, Any]:
    inventory = factory_inventory(include_linux=True, mounted=mounted)
    disk = inventory["blockdevices"][0]
    children = disk["children"]
    linux = next(item for item in children if item["parttype"] == LINUX_GUID)
    children.remove(next(item for item in children if item["parttype"] == RECOVERY_GUID))
    linux["name"] = "nvme0n1p4"
    linux["path"] = "/dev/nvme0n1p4"
    linux["partn"] = 4
    linux["partuuid"] = "00000000-0000-0000-0000-000000000004"
    linux["uuid"] = "FS-4"
    disk["size"] = linux["start"] * SECTOR + linux["size"] + MIB
    return inventory


def terminal_free_inventory() -> dict[str, Any]:
    inventory = factory_inventory()
    disk = inventory["blockdevices"][0]
    recovery = next(
        item for item in disk["children"] if item["parttype"] == RECOVERY_GUID
    )
    disk["children"].remove(recovery)
    disk["size"] = recovery["start"] * SECTOR + MIB
    return inventory


def terminal_sp11_pair_inventory(*, mounted: bool = False) -> dict[str, Any]:
    inventory = factory_inventory()
    disk = inventory["blockdevices"][0]
    recovery = next(
        item for item in disk["children"] if item["parttype"] == RECOVERY_GUID
    )
    disk["children"].remove(recovery)
    windows = next(
        item for item in disk["children"] if item["parttype"] == BASIC_GUID
    )
    esp_start = windows["start"] * SECTOR + windows["size"]
    esp = partition(
        4,
        esp_start,
        GIB,
        ESP_GUID,
        "vfat",
        "SP11EFI",
        partlabel="SP11 Linux EFI",
    )
    root = partition(
        5,
        esp_start + GIB,
        200 * GIB,
        LINUX_GUID,
        "ext4",
        "sp11root",
        ["/"] if mounted else [],
        partlabel="SP11 Linux Root",
    )
    disk["children"].extend((esp, root))
    disk["size"] = root["start"] * SECTOR + root["size"] + MIB
    return inventory


class PlannerTests(unittest.TestCase):
    def run_planner(
        self, inventory: dict[str, Any], mode: str
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = Path(temporary) / "lsblk.json"
            fixture.write_text(json.dumps(inventory), encoding="utf-8")
            return subprocess.run(
                [
                    str(SCRIPT),
                    "--inventory-json",
                    str(fixture),
                    "--mode",
                    mode,
                    "--disk",
                    "/dev/nvme0n1",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )

    def test_dual_boot_uses_only_windows_shrink_extent(self) -> None:
        result = self.run_planner(factory_inventory(), "dual-boot")
        self.assertEqual(result.returncode, 0, result.stderr)
        plan = json.loads(result.stdout)
        self.assertFalse(plan["execution_eligible"])
        self.assertEqual(plan["executor_status"], "held-disposable-loop-only")
        self.assertEqual(plan["confirmation"]["required_text"], "INSTALL TESTSERIAL123")
        self.assertEqual(
            [item["role"] for item in plan["proposed_partitions"]],
            ["linux-esp", "linux-root"],
        )
        self.assertEqual(plan["proposed_partitions"][0]["size_bytes"], GIB)
        self.assertEqual(len(plan["preserved_partitions"]), 4)
        preserved_types = {item["parttype"] for item in plan["preserved_partitions"]}
        self.assertEqual(
            preserved_types, {ESP_GUID, MSR_GUID, BASIC_GUID, RECOVERY_GUID}
        )

    def test_dual_boot_refuses_too_little_unallocated_space(self) -> None:
        result = self.run_planner(factory_inventory(free_space=32 * GIB), "dual-boot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires exactly one >=33 GiB", result.stderr)

    def test_dual_boot_reclaims_one_terminal_linux_partition(self) -> None:
        result = self.run_planner(terminal_reclaim_inventory(), "dual-boot")
        self.assertEqual(result.returncode, 0, result.stderr)
        plan = json.loads(result.stdout)
        self.assertEqual(
            [item["number"] for item in plan["proposed_partitions"]], [4, 5]
        )
        self.assertEqual(
            [item["number"] for item in plan["reclaimed_partitions"]], [4]
        )
        self.assertEqual(
            [item["number"] for item in plan["preserved_partitions"]], [1, 2, 3]
        )

    def test_dual_boot_reclaims_exact_terminal_sp11_esp_root_pair(self) -> None:
        result = self.run_planner(terminal_sp11_pair_inventory(), "dual-boot")
        self.assertEqual(result.returncode, 0, result.stderr)
        plan = json.loads(result.stdout)
        self.assertEqual(
            [item["number"] for item in plan["proposed_partitions"]], [4, 5]
        )
        self.assertEqual(
            [item["number"] for item in plan["reclaimed_partitions"]], [4, 5]
        )
        self.assertEqual(
            [item["number"] for item in plan["preserved_partitions"]], [1, 2, 3]
        )

    def test_dual_boot_refuses_ambiguous_second_esp(self) -> None:
        inventory = terminal_sp11_pair_inventory()
        esp = next(
            item
            for item in inventory["blockdevices"][0]["children"]
            if item["partn"] == 4
        )
        esp["partlabel"] = "Unrecognized EFI"
        result = self.run_planner(inventory, "dual-boot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("non-SP11 Windows EFI", result.stderr)

    def test_dual_boot_refuses_nonadjacent_sp11_pair(self) -> None:
        inventory = terminal_sp11_pair_inventory()
        disk = inventory["blockdevices"][0]
        root = next(
            item for item in disk["children"] if item["partn"] == 5
        )
        root["start"] += (2 * MIB) // SECTOR
        disk["size"] += 2 * MIB
        result = self.run_planner(inventory, "dual-boot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("found 0 usable extents", result.stderr)

    def test_dual_boot_refuses_mounted_reclaim_partition(self) -> None:
        result = self.run_planner(
            terminal_reclaim_inventory(mounted=True), "dual-boot"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("mounted filesystems", result.stderr)

    def test_dual_boot_refuses_multiple_linux_partitions(self) -> None:
        inventory = terminal_reclaim_inventory()
        disk = inventory["blockdevices"][0]
        linux = next(
            item for item in disk["children"] if item["parttype"] == LINUX_GUID
        )
        extra = partition(
            5,
            linux["start"] * SECTOR + linux["size"],
            GIB,
            LINUX_GUID,
            "ext4",
            "other-linux",
        )
        disk["children"].append(extra)
        disk["size"] = extra["start"] * SECTOR + extra["size"] + MIB
        result = self.run_planner(inventory, "dual-boot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("found 0 usable extents", result.stderr)

    def test_dual_boot_refuses_nonadjacent_linux_partition(self) -> None:
        inventory = terminal_reclaim_inventory()
        disk = inventory["blockdevices"][0]
        linux = next(
            item for item in disk["children"] if item["parttype"] == LINUX_GUID
        )
        linux["partn"] = 5
        linux["name"] = "nvme0n1p5"
        linux["path"] = "/dev/nvme0n1p5"
        result = self.run_planner(inventory, "dual-boot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("found 0 usable extents", result.stderr)

    def test_dual_boot_refuses_nonterminal_linux_partition(self) -> None:
        inventory = terminal_reclaim_inventory()
        inventory["blockdevices"][0]["size"] += 10 * GIB
        result = self.run_planner(inventory, "dual-boot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("found 0 usable extents", result.stderr)

    def test_dual_boot_uses_terminal_free_space_without_recovery(self) -> None:
        result = self.run_planner(terminal_free_inventory(), "dual-boot")
        self.assertEqual(result.returncode, 0, result.stderr)
        plan = json.loads(result.stdout)
        self.assertEqual(plan["reclaimed_partitions"], [])
        self.assertEqual(
            [item["number"] for item in plan["proposed_partitions"]], [4, 5]
        )

    def test_any_plan_refuses_mounted_target(self) -> None:
        result = self.run_planner(
            factory_inventory(include_linux=True, mounted=True), "wipe"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("mounted filesystems", result.stderr)

    def test_any_plan_refuses_usb(self) -> None:
        result = self.run_planner(factory_inventory(transport="usb"), "wipe")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("USB transport", result.stderr)

    def test_any_plan_refuses_removable_or_hotplug(self) -> None:
        for inventory in (
            factory_inventory(removable=True),
            factory_inventory(hotplug=True),
        ):
            with self.subTest(inventory=inventory):
                result = self.run_planner(inventory, "wipe")
                self.assertNotEqual(result.returncode, 0)

    def test_wipe_plan_has_exact_identity_confirmation(self) -> None:
        result = self.run_planner(factory_inventory(), "wipe")
        self.assertEqual(result.returncode, 0, result.stderr)
        plan = json.loads(result.stdout)
        self.assertEqual(plan["preserved_partitions"], [])
        self.assertEqual(plan["confirmation"]["required_text"], "ERASE TESTSERIAL123")
        self.assertEqual(
            [item["number"] for item in plan["proposed_partitions"]], [1, 2]
        )

    def test_plan_id_changes_when_observed_identity_changes(self) -> None:
        first = self.run_planner(factory_inventory(), "wipe")
        changed = factory_inventory()
        changed["blockdevices"][0]["serial"] = "DIFFERENT-SERIAL"
        second = self.run_planner(changed, "wipe")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertNotEqual(
            json.loads(first.stdout)["plan_id"],
            json.loads(second.stdout)["plan_id"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
