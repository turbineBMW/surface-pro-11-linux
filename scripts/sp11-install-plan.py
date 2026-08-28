#!/usr/bin/env python3

"""Read-only disk inventory and immutable-plan generator for the SP11 installer."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


SCHEMA = "sp11.install-plan.v1"
LOOP_EXECUTOR_STATUS = "held-disposable-loop-only"
USB_EXECUTOR_STATUS = "held-disposable-usb-qualification-only"
LIVE_EXECUTOR_STATUS = "held-live-internal-only"
MIB = 1024**2
GIB = 1024**3
ALIGNMENT = MIB
ESP_SIZE = GIB
MIN_ROOT_SIZE = 32 * GIB
GPT_EDGE_RESERVE = MIB

ESP_GUID = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
MS_RESERVED_GUID = "e3c9e316-0b5c-4db8-817d-f92df00215ae"
MS_BASIC_GUID = "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7"
WINDOWS_RECOVERY_GUID = "de94bba4-06d1-4d40-a16a-bfd50179d6ac"
LINUX_FILESYSTEM_GUID = "0fc63daf-8483-4772-8e79-3d69d8477de4"
LINUX_FILESYSTEMS = {"btrfs", "ext2", "ext3", "ext4", "f2fs", "xfs"}

LSBLK_FIELDS = (
    "NAME,PATH,TYPE,SIZE,START,LOG-SEC,PHY-SEC,MIN-IO,OPT-IO,ALIGNMENT,"
    "RO,RM,HOTPLUG,TRAN,MODEL,SERIAL,PTTYPE,PTUUID,FSTYPE,FSVER,LABEL,UUID,"
    "PARTTYPE,PARTTYPENAME,PARTUUID,PARTLABEL,PARTN,PKNAME,MOUNTPOINTS"
)


class PlannerError(RuntimeError):
    """A fail-closed planner refusal."""


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def align_up(value: int, alignment: int = ALIGNMENT) -> int:
    return ((value + alignment - 1) // alignment) * alignment


def align_down(value: int, alignment: int = ALIGNMENT) -> int:
    return (value // alignment) * alignment


def load_inventory(path: Path | None) -> tuple[dict[str, Any], str]:
    if path is not None:
        with path.open("r", encoding="utf-8") as source:
            inventory = json.load(source)
        source_name = "fixture"
    else:
        result = subprocess.run(
            ["lsblk", "--json", "--bytes", "-o", LSBLK_FIELDS],
            check=True,
            stdout=subprocess.PIPE,
            text=True,
        )
        inventory = json.loads(result.stdout)
        source_name = "live-lsblk"
    if not isinstance(inventory, dict) or not isinstance(
        inventory.get("blockdevices"), list
    ):
        raise PlannerError("lsblk inventory has no blockdevices array")
    return inventory, source_name


def as_int(value: Any, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise PlannerError(f"invalid numeric {field}: {value!r}")
    return value


def as_bool(value: Any, field: str) -> bool:
    if not isinstance(value, bool):
        raise PlannerError(f"invalid boolean {field}: {value!r}")
    return value


def clean_text(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def mounted_at(device: dict[str, Any]) -> list[str]:
    raw = device.get("mountpoints")
    if raw is None:
        return []
    if not isinstance(raw, list):
        raise PlannerError("invalid mountpoints inventory")
    return [item for item in raw if isinstance(item, str) and item]


def select_disk(inventory: dict[str, Any], requested: str) -> dict[str, Any]:
    requested_real = os.path.realpath(requested)
    matches = []
    for candidate in inventory["blockdevices"]:
        if not isinstance(candidate, dict) or candidate.get("type") != "disk":
            continue
        candidate_path = clean_text(candidate.get("path"))
        if candidate_path and os.path.realpath(candidate_path) == requested_real:
            matches.append(candidate)
    if len(matches) != 1:
        raise PlannerError(
            f"target must resolve to exactly one whole disk: {requested}"
        )
    return matches[0]


def partitions(disk: dict[str, Any]) -> list[dict[str, Any]]:
    children = disk.get("children") or []
    if not isinstance(children, list):
        raise PlannerError("invalid disk children inventory")
    result = []
    for child in children:
        if not isinstance(child, dict) or child.get("type") != "part":
            raise PlannerError("target has a non-partition child or malformed child")
        result.append(child)
    return result


def validate_physical_target(
    disk: dict[str, Any], *, disposable_usb_qualification: bool = False
) -> None:
    path = clean_text(disk.get("path"))
    if as_bool(disk.get("ro"), "disk ro"):
        raise PlannerError(f"target disk is read-only: {path}")
    transport = clean_text(disk.get("tran")).lower()
    if disposable_usb_qualification:
        if (
            not as_bool(disk.get("rm"), "disk rm")
            or not as_bool(disk.get("hotplug"), "disk hotplug")
            or transport != "usb"
        ):
            raise PlannerError(
                "disposable qualification target must be removable, hot-plug "
                "USB media"
            )
    else:
        if as_bool(disk.get("rm"), "disk rm"):
            raise PlannerError(f"target disk is removable: {path}")
        if as_bool(disk.get("hotplug"), "disk hotplug"):
            raise PlannerError(f"target disk is hot-plug capable: {path}")
        if transport == "usb":
            raise PlannerError(f"target disk uses USB transport: {path}")
    if not clean_text(disk.get("serial")):
        raise PlannerError("target disk has no stable serial")
    if as_int(disk.get("size"), "disk size") < ESP_SIZE + MIN_ROOT_SIZE:
        raise PlannerError("target disk is smaller than the minimum installation")
    mounted = mounted_at(disk)
    for part in partitions(disk):
        mounted.extend(mounted_at(part))
    if mounted:
        raise PlannerError(
            "target disk has mounted filesystems: " + ", ".join(sorted(mounted))
        )


def partition_geometry(disk: dict[str, Any], part: dict[str, Any]) -> tuple[int, int]:
    sector_size = as_int(disk.get("log-sec"), "disk logical sector")
    start_sector = as_int(part.get("start"), "partition start")
    size = as_int(part.get("size"), "partition size")
    start = start_sector * sector_size
    end = start + size
    disk_size = as_int(disk.get("size"), "disk size")
    if start < GPT_EDGE_RESERVE or end <= start or end > disk_size:
        raise PlannerError(
            f"partition geometry is outside the disk: {part.get('path')}"
        )
    return start, end


def partition_record(disk: dict[str, Any], part: dict[str, Any]) -> dict[str, Any]:
    start, end = partition_geometry(disk, part)
    return {
        "path": clean_text(part.get("path")),
        "number": as_int(part.get("partn"), "partition number"),
        "start_bytes": start,
        "size_bytes": end - start,
        "parttype": clean_text(part.get("parttype")).lower(),
        "partuuid": clean_text(part.get("partuuid")).lower(),
        "fstype": clean_text(part.get("fstype")),
        "filesystem_uuid": clean_text(part.get("uuid")),
        "label": clean_text(part.get("label")),
        "partition_name": clean_text(part.get("partlabel")),
    }


def disk_record(disk: dict[str, Any]) -> dict[str, Any]:
    return {
        "path": clean_text(disk.get("path")),
        "model": clean_text(disk.get("model")),
        "serial": clean_text(disk.get("serial")),
        "size_bytes": as_int(disk.get("size"), "disk size"),
        "transport": clean_text(disk.get("tran")),
        "logical_sector_bytes": as_int(disk.get("log-sec"), "disk logical sector"),
        "partition_table": clean_text(disk.get("pttype")).lower(),
        "partition_table_uuid": clean_text(disk.get("ptuuid")).lower(),
    }


def unused_partition_numbers(records: list[dict[str, Any]], count: int) -> list[int]:
    used = {record["number"] for record in records}
    available = [number for number in range(1, 129) if number not in used]
    if len(available) < count:
        raise PlannerError("GPT has no room for the required partition numbers")
    return available[:count]


def dual_boot_layout(
    disk: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    if clean_text(disk.get("pttype")).lower() != "gpt":
        raise PlannerError("dual boot requires an existing GPT")
    records = sorted(
        (partition_record(disk, part) for part in partitions(disk)),
        key=lambda item: item["start_bytes"],
    )
    linux_esps = [
        record
        for record in records
        if record["parttype"] == ESP_GUID
        and record["fstype"].lower() == "vfat"
        and record["label"] == "SP11EFI"
        and record["partition_name"] == "SP11 Linux EFI"
    ]
    if len(linux_esps) > 1:
        raise PlannerError(
            "expected at most one exact SP11 Linux EFI partition; found "
            f"{len(linux_esps)}"
        )
    windows_esps = [
        record
        for record in records
        if record["parttype"] == ESP_GUID and record not in linux_esps
    ]
    if len(windows_esps) != 1:
        raise PlannerError(
            "expected exactly one non-SP11 Windows EFI System Partition; "
            f"found {len(windows_esps)}"
        )
    types = [record["parttype"] for record in records]
    for required_type, description in (
        (MS_RESERVED_GUID, "Microsoft Reserved Partition"),
        (MS_BASIC_GUID, "Microsoft basic-data partition"),
    ):
        if types.count(required_type) != 1:
            raise PlannerError(
                f"expected exactly one {description}; found "
                f"{types.count(required_type)}"
            )
    linux_records = [
        record
        for record in records
        if record["parttype"] == LINUX_FILESYSTEM_GUID
        or record["fstype"].lower() in LINUX_FILESYSTEMS
    ]
    windows = next(
        record for record in records if record["parttype"] == MS_BASIC_GUID
    )
    recovery_records = [
        record for record in records if record["parttype"] == WINDOWS_RECOVERY_GUID
    ]

    candidate_extents: list[tuple[int, int]] = []
    for previous, following in zip(records, records[1:]):
        if (
            previous["parttype"] != MS_BASIC_GUID
            or following["parttype"] != WINDOWS_RECOVERY_GUID
        ):
            continue
        previous_end = previous["start_bytes"] + previous["size_bytes"]
        start = align_up(previous_end)
        end = align_down(following["start_bytes"])
        if end - start >= ESP_SIZE + MIN_ROOT_SIZE:
            candidate_extents.append((start, end))
    if (
        len(candidate_extents) == 0
        and len(linux_records) == 0
        and len(recovery_records) == 0
        and records[-1] == windows
    ):
        start = align_up(windows["start_bytes"] + windows["size_bytes"])
        end = align_down(as_int(disk.get("size"), "disk size") - GPT_EDGE_RESERVE)
        if end - start >= ESP_SIZE + MIN_ROOT_SIZE:
            candidate_extents.append((start, end))
    reclaimed: list[dict[str, Any]] = []
    if (
        len(candidate_extents) == 0
        and len(linux_esps) == 1
        and len(linux_records) == 1
    ):
        linux_esp = linux_esps[0]
        linux_root = linux_records[0]
        esp_end = linux_esp["start_bytes"] + linux_esp["size_bytes"]
        root_end = linux_root["start_bytes"] + linux_root["size_bytes"]
        disk_end = align_down(
            as_int(disk.get("size"), "disk size") - GPT_EDGE_RESERVE
        )
        if (
            linux_esp["number"] == windows["number"] + 1
            and linux_root["number"] == linux_esp["number"] + 1
            and linux_esp["start_bytes"] >= align_up(
                windows["start_bytes"] + windows["size_bytes"]
            )
            and linux_esp["size_bytes"] == ESP_SIZE
            and linux_root["start_bytes"] == align_up(esp_end)
            and disk_end - root_end <= ALIGNMENT
            and linux_root["size_bytes"] >= MIN_ROOT_SIZE
        ):
            candidate_extents.append(
                (linux_esp["start_bytes"], align_down(root_end))
            )
            reclaimed = [linux_esp, linux_root]
    if len(candidate_extents) == 0 and len(linux_records) == 1:
        candidate = linux_records[0]
        candidate_end = candidate["start_bytes"] + candidate["size_bytes"]
        disk_end = align_down(
            as_int(disk.get("size"), "disk size") - GPT_EDGE_RESERVE
        )
        if (
            candidate["number"] == windows["number"] + 1
            and candidate["start_bytes"] >= align_up(
                windows["start_bytes"] + windows["size_bytes"]
            )
            and disk_end - candidate_end <= ALIGNMENT
            and candidate["size_bytes"] >= ESP_SIZE + MIN_ROOT_SIZE
        ):
            candidate_extents.append(
                (candidate["start_bytes"], align_down(candidate_end))
            )
            reclaimed = [candidate]
    if len(candidate_extents) != 1:
        raise PlannerError(
            "dual boot requires exactly one >=33 GiB unallocated extent "
            "immediately after Windows basic data, either before Windows "
            "Recovery or at the end of a disk without Recovery; "
            "or one supported unmounted terminal Linux replacement layout; "
            f"found {len(candidate_extents)} usable extents"
        )

    extent_start, extent_end = candidate_extents[0]
    esp_start = extent_start
    esp_end = esp_start + ESP_SIZE
    root_start = align_up(esp_end)
    root_end = extent_end
    if root_end - root_start < MIN_ROOT_SIZE:
        raise PlannerError("aligned Linux root would be smaller than 32 GiB")
    if reclaimed:
        esp_number = reclaimed[0]["number"]
        root_number = (
            reclaimed[1]["number"]
            if len(reclaimed) == 2
            else unused_partition_numbers(records, 1)[0]
        )
    else:
        esp_number, root_number = unused_partition_numbers(records, 2)
    proposed = [
        {
            "role": "linux-esp",
            "number": esp_number,
            "start_bytes": esp_start,
            "size_bytes": esp_end - esp_start,
            "parttype": ESP_GUID,
            "partition_name": "SP11 Linux EFI",
            "filesystem": "vfat",
            "filesystem_label": "SP11EFI",
        },
        {
            "role": "linux-root",
            "number": root_number,
            "start_bytes": root_start,
            "size_bytes": root_end - root_start,
            "parttype": LINUX_FILESYSTEM_GUID,
            "partition_name": "SP11 Linux Root",
            "filesystem": "ext4",
            "filesystem_label": "sp11root",
        },
    ]
    preserved = [record for record in records if record not in reclaimed]
    return preserved, proposed, reclaimed


def wipe_layout(disk: dict[str, Any]) -> list[dict[str, Any]]:
    disk_size = as_int(disk.get("size"), "disk size")
    esp_start = GPT_EDGE_RESERVE
    esp_end = esp_start + ESP_SIZE
    root_start = align_up(esp_end)
    root_end = align_down(disk_size - GPT_EDGE_RESERVE)
    if root_end - root_start < MIN_ROOT_SIZE:
        raise PlannerError("aligned Linux root would be smaller than 32 GiB")
    return [
        {
            "role": "linux-esp",
            "number": 1,
            "start_bytes": esp_start,
            "size_bytes": esp_end - esp_start,
            "parttype": ESP_GUID,
            "partition_name": "SP11 Linux EFI",
            "filesystem": "vfat",
            "filesystem_label": "SP11EFI",
        },
        {
            "role": "linux-root",
            "number": 2,
            "start_bytes": root_start,
            "size_bytes": root_end - root_start,
            "parttype": LINUX_FILESYSTEM_GUID,
            "partition_name": "SP11 Linux Root",
            "filesystem": "ext4",
            "filesystem_label": "sp11root",
        },
    ]


def build_plan(
    inventory: dict[str, Any],
    inventory_source: str,
    mode: str,
    requested_disk: str,
    *,
    disposable_usb_qualification: bool = False,
) -> dict[str, Any]:
    disk = select_disk(inventory, requested_disk)
    validate_physical_target(
        disk,
        disposable_usb_qualification=disposable_usb_qualification,
    )
    identity = disk_record(disk)
    observed_fingerprint = digest(inventory)
    if mode == "dual-boot":
        preserved, proposed, reclaimed = dual_boot_layout(disk)
        confirmation = f"INSTALL {identity['serial']}"
        warnings = [
            "Windows partitions and the Windows ESP are preserved byte-for-byte.",
            (
                "Only the explicitly identified existing Linux partition may "
                "be reclaimed."
                if reclaimed
                else "Only pre-existing unallocated space may be used."
            ),
            "The Windows ESP must be mounted read-only and its loader verified "
            "before execution.",
        ]
        if reclaimed:
            warnings.insert(
                0,
                "The existing SP11 Linux partition(s) "
                f"{', '.join(item['path'] for item in reclaimed)} will be "
                "erased and replaced by a dedicated Linux EFI partition and "
                "a fresh Linux root; Windows partitions are not reclaimed.",
            )
    elif mode == "wipe":
        preserved = []
        proposed = wipe_layout(disk)
        confirmation = f"ERASE {identity['serial']}"
        warnings = [
            "Every partition and all data on the selected disk will be destroyed.",
            "Windows and Surface recovery partitions will not be retained.",
            "Official Surface recovery media is required to restore Windows.",
        ]
    else:
        raise PlannerError(f"unsupported planning mode: {mode}")
    if disposable_usb_qualification:
        warnings.insert(
            0,
            "HELD LAB QUALIFICATION: this plan may target only separately "
            "enrolled disposable USB media and is never a release install plan.",
        )

    plan: dict[str, Any] = {
        "schema": SCHEMA,
        "mode": mode,
        "inventory_source": inventory_source,
        "execution_eligible": inventory_source == "live-lsblk",
        "observed_inventory_sha256": observed_fingerprint,
        "disk": identity,
        "preserved_partitions": preserved,
        "reclaimed_partitions": reclaimed if mode == "dual-boot" else [],
        "proposed_partitions": proposed,
        "required_prechecks": [
            "exact Surface Pro 11 DMI and microsoft,denali compatibility",
            "held live-image identity and exact installer artifact hashes",
            "target disk inventory reacquired with identical SHA-256",
            "target disk and every child partition still unmounted",
            "stable disk path, serial, size, and partition-table identity",
            "AC power connected and battery charge at or above 50 percent",
        ],
        "confirmation": {
            "required_text": confirmation,
            "second_confirmation_required": True,
        },
        "warnings": warnings,
        "executor_status": (
            USB_EXECUTOR_STATUS
            if disposable_usb_qualification
            else (
                LIVE_EXECUTOR_STATUS
                if inventory_source == "live-lsblk"
                else LOOP_EXECUTOR_STATUS
            )
        ),
    }
    plan["plan_id"] = digest(plan)
    return plan


def inventory_report(inventory: dict[str, Any], source: str) -> dict[str, Any]:
    disks = []
    for candidate in inventory["blockdevices"]:
        if not isinstance(candidate, dict) or candidate.get("type") != "disk":
            continue
        summary: dict[str, Any] = {
            "path": clean_text(candidate.get("path")),
            "model": clean_text(candidate.get("model")),
            "serial": clean_text(candidate.get("serial")),
            "size_bytes": candidate.get("size"),
            "transport": clean_text(candidate.get("tran")),
            "removable": candidate.get("rm"),
            "hotplug": candidate.get("hotplug"),
            "read_only": candidate.get("ro"),
            "partition_table": clean_text(candidate.get("pttype")),
            "mountpoints": mounted_at(candidate),
            "partitions": [],
        }
        for part in candidate.get("children") or []:
            summary["mountpoints"].extend(mounted_at(part))
            summary["partitions"].append(
                {
                    "path": clean_text(part.get("path")),
                    "size_bytes": part.get("size"),
                    "parttype": clean_text(part.get("parttype")),
                    "fstype": clean_text(part.get("fstype")),
                    "label": clean_text(part.get("label")),
                    "mountpoints": mounted_at(part),
                }
            )
        summary["mountpoints"] = sorted(set(summary["mountpoints"]))
        disks.append(summary)
    return {
        "schema": "sp11.disk-inventory.v1",
        "inventory_source": source,
        "observed_inventory_sha256": digest(inventory),
        "disks": disks,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Read-only SP11 fresh-install disk inventory and immutable-plan "
            "generator. This program has no partitioning or formatting code."
        )
    )
    parser.add_argument(
        "--mode", choices=("inventory", "dual-boot", "wipe"), default="inventory"
    )
    parser.add_argument("--disk", help="exact whole-disk path for a plan")
    parser.add_argument(
        "--inventory-json",
        type=Path,
        help=(
            "offline/test lsblk JSON; plans generated from fixtures are marked "
            "execution_eligible=false"
        ),
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="new output file; default is standard output",
    )
    parser.add_argument(
        "--held-disposable-usb-qualification",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.mode != "inventory" and not args.disk:
        raise PlannerError("--disk is required for dual-boot or wipe mode")
    if args.mode == "inventory" and args.disk:
        raise PlannerError("--disk is not valid in inventory mode")
    if args.held_disposable_usb_qualification and (
        args.mode == "inventory" or args.inventory_json is None
    ):
        raise PlannerError(
            "held disposable USB qualification requires a fixture plan mode"
        )
    if args.output and args.output.exists():
        raise PlannerError(f"output file already exists: {args.output}")

    inventory, source = load_inventory(args.inventory_json)
    if args.mode == "inventory":
        result = inventory_report(inventory, source)
    else:
        result = build_plan(
            inventory,
            source,
            args.mode,
            args.disk,
            disposable_usb_qualification=(
                args.held_disposable_usb_qualification
            ),
        )
    rendered = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
    else:
        sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        PlannerError,
        OSError,
        subprocess.CalledProcessError,
        json.JSONDecodeError,
    ) as error:
        print(f"REFUSED: {error}", file=sys.stderr)
        raise SystemExit(1) from None
