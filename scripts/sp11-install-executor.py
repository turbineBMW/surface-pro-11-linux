#!/usr/bin/env python3

"""Fail-closed held executor for qualified tests and the SP11 live image."""

from __future__ import annotations

import argparse
import csv
import fcntl
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, NoReturn


SCHEMA = "sp11.install-plan.v1"
JOURNAL_SCHEMA = "sp11.install-transaction.v1"
LOOP_EXECUTOR_STATUS = "held-disposable-loop-only"
USB_EXECUTOR_STATUS = "held-disposable-usb-qualification-only"
LIVE_EXECUTOR_STATUS = "held-live-internal-only"
TEST_SERIAL = "SP11-DISPOSABLE-LOOP-TEST"
TEST_MARKER = "SP11 DISPOSABLE INSTALL EXECUTOR LOOP TEST\n"
SECOND_CONFIRMATION = "I UNDERSTAND THIS IS A DISPOSABLE LOOP TEST"
USB_MARKER_SCHEMA = "sp11.disposable-usb-qualification.v1"
USB_SECOND_CONFIRMATION = "I UNDERSTAND THIS ERASES A DISPOSABLE USB TEST DEVICE"
LIVE_DUAL_SECOND_CONFIRMATION = (
    "I UNDERSTAND THIS MODIFIES THE INTERNAL DISK AND REQUIRES A BACKUP"
)
LIVE_WIPE_SECOND_CONFIRMATION = (
    "I UNDERSTAND THIS ERASES WINDOWS RECOVERY AND ALL DATA"
)
RELEASE = "7.1.3-sp11-suspend-review20"
EXPECTED_ARCHIVE_SHA = (
    "fa04efafd4e48a261765f7b008cdb5c961c954a92f41d1a8be278259147674b8"
)
EXPECTED_ROOT_MANIFEST_SHA = (
    "dfad2bdf4abfade3f9cf726fe4c3f1284732ed321eb4667d8a2cb9b3df280d7c"
)
EXPECTED_IMAGE_SHA = (
    "918ed2560654355555535290fd0d9657e1afc7022b3e46cc8396155d3575f256"
)
EXPECTED_DTB_SHA = (
    "5e9009f5bd96a760a33086d1a8842e3228e3d28c413f96d70aca4914f7e397ed"
)

ESP_GUID = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
LINUX_GUID = "0fc63daf-8483-4772-8e79-3d69d8477de4"
LSBLK_FIELDS = (
    "NAME,PATH,TYPE,SIZE,START,LOG-SEC,RO,RM,HOTPLUG,TRAN,MODEL,SERIAL,"
    "PTTYPE,PTUUID,FSTYPE,FSVER,LABEL,UUID,PARTTYPE,PARTUUID,PARTLABEL,"
    "PARTN,PKNAME,MOUNTPOINTS"
)


class ExecutorRefusal(RuntimeError):
    """A fail-closed executor refusal."""


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def file_digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def refuse(message: str) -> NoReturn:
    raise ExecutorRefusal(message)


def run(
    arguments: list[str],
    *,
    stdout: int | None = subprocess.PIPE,
    text: bool = True,
    input_text: str | None = None,
) -> subprocess.CompletedProcess[Any]:
    try:
        return subprocess.run(
            arguments,
            check=True,
            # subprocess.run() creates stdin=PIPE itself when input= is used.
            # Passing both stdin=PIPE and input= raises ValueError before the
            # command can execute.
            stdin=None if input_text is not None else subprocess.DEVNULL,
            stdout=stdout,
            stderr=subprocess.PIPE,
            text=text,
            input=input_text,
        )
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() if isinstance(error.stderr, str) else ""
        command = Path(arguments[0]).name
        refuse(
            f"{command} failed with status {error.returncode}"
            + (f": {detail}" if detail else "")
        )


def read_kernel_bytes(path: Path) -> bytes:
    """Read a procfs/sysfs value without buffered-I/O EAGAIN leakage."""
    for attempt in range(5):
        try:
            descriptor = os.open(path, os.O_RDONLY | os.O_CLOEXEC)
            try:
                blocks = []
                while True:
                    block = os.read(descriptor, 64 * 1024)
                    if not block:
                        return b"".join(blocks)
                    blocks.append(block)
            finally:
                os.close(descriptor)
        except BlockingIOError:
            if attempt == 4:
                refuse(f"kernel state remained temporarily unreadable: {path}")
            time.sleep(0.05)
    refuse(f"kernel state is unreadable: {path}")


def read_kernel_text(path: Path) -> str:
    try:
        return read_kernel_bytes(path).decode("utf-8")
    except UnicodeDecodeError:
        refuse(f"kernel state is not valid UTF-8: {path}")


def read_json(path: Path) -> Any:
    if path.is_symlink() or not path.is_file():
        refuse(f"missing or unsafe JSON file: {path}")
    with path.open("r", encoding="utf-8") as source:
        value = json.load(source)
    return value


def write_json(path: Path, value: Any) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as output:
        json.dump(value, output, indent=2, sort_keys=True)
        output.write("\n")
        output.flush()
        os.fsync(output.fileno())


def replace_state(path: Path, state: str) -> None:
    temporary = path.with_name(f".{path.name}.{os.getpid()}")
    with temporary.open("x", encoding="utf-8", newline="\n") as output:
        output.write(f"{state}\n")
        output.flush()
        os.fsync(output.fileno())
    os.replace(temporary, path)


def append_event(journal: Path, event: str, **details: Any) -> None:
    record = {
        "event": event,
        "time_utc": datetime.now(UTC).isoformat(),
        **details,
    }
    with (journal / "events.jsonl").open(
        "a", encoding="utf-8", newline="\n"
    ) as output:
        output.write(json.dumps(record, sort_keys=True) + "\n")
        output.flush()
        os.fsync(output.fileno())


def parse_uefi_boot_state(output: str) -> dict[str, Any]:
    order_match = re.search(r"^BootOrder:\s*([0-9A-Fa-f,]+)\s*$", output, re.M)
    if order_match is None:
        refuse("UEFI BootOrder is unavailable or malformed")
    order = [item.upper() for item in order_match.group(1).split(",")]
    if not order or any(not re.fullmatch(r"[0-9A-F]{4}", item) for item in order):
        refuse("UEFI BootOrder is empty or malformed")
    entries = []
    for line in output.splitlines():
        match = re.match(
            r"^Boot([0-9A-Fa-f]{4})(\*)?\s+SP11 Linux\t(.*)$", line
        )
        if match:
            entries.append(
                {
                    "number": match.group(1).upper(),
                    "active": match.group(2) == "*",
                    "device_path": match.group(3),
                }
            )
    return {"order": order, "linux_entries": entries, "raw": output}


def read_uefi_boot_state() -> dict[str, Any]:
    return parse_uefi_boot_state(run(["efibootmgr", "-v"]).stdout)


def assert_linux_uefi_entry(
    state: dict[str, Any], entry_number: str, esp: dict[str, Any]
) -> None:
    entries = [
        entry
        for entry in state["linux_entries"]
        if entry["number"] == entry_number
    ]
    expected_hd = f"HD({esp['number']},GPT,{esp['partuuid']},".lower()
    expected_loader = r"\EFI\BOOT\BOOTAA64.EFI".lower()
    if (
        len(state["linux_entries"]) != 1
        or len(entries) != 1
        or not entries[0]["active"]
        or expected_hd not in entries[0]["device_path"].lower()
        or expected_loader not in entries[0]["device_path"].lower()
        or state["order"][0] != entry_number
    ):
        refuse("persistent SP11 Linux UEFI entry is missing or incorrect")


def provision_linux_uefi_entry(
    device: str, esp: dict[str, Any]
) -> dict[str, Any]:
    before = read_uefi_boot_state()
    stale_numbers = [
        entry["number"] for entry in before["linux_entries"]
    ]
    retained_order = [
        item for item in before["order"] if item not in stale_numbers
    ]
    created_number = ""
    try:
        for entry_number in stale_numbers:
            run(
                [
                    "efibootmgr",
                    "--bootnum",
                    entry_number,
                    "--delete-bootnum",
                ],
                stdout=None,
            )
        run(
            [
                "efibootmgr",
                "--create",
                "--disk",
                device,
                "--part",
                str(esp["number"]),
                "--label",
                "SP11 Linux",
                "--loader",
                r"\EFI\BOOT\BOOTAA64.EFI",
            ],
            stdout=None,
        )
        created = read_uefi_boot_state()
        new_entries = created["linux_entries"]
        if len(new_entries) != 1:
            refuse("UEFI firmware did not create one SP11 Linux entry")
        created_number = new_entries[0]["number"]
        final_order = [created_number, *[
            item for item in retained_order if item != created_number
        ]]
        run(
            ["efibootmgr", "--bootorder", ",".join(final_order)],
            stdout=None,
        )
        final = read_uefi_boot_state()
        assert_linux_uefi_entry(final, created_number, esp)
        return {
            "schema": "sp11.uefi-boot-entry.v1",
            "entry_number": created_number,
            "label": "SP11 Linux",
            "loader": r"\EFI\BOOT\BOOTAA64.EFI",
            "esp_number": esp["number"],
            "esp_partuuid": esp["partuuid"],
            "original_boot_order": retained_order,
            "observed_boot_order": before["order"],
            "replaced_entry_numbers": stale_numbers,
            "final_boot_order": final["order"],
        }
    except BaseException:
        cleanup_numbers = set(stale_numbers)
        try:
            cleanup_numbers.update(
                entry["number"]
                for entry in read_uefi_boot_state()["linux_entries"]
            )
        except BaseException:
            pass
        if created_number:
            cleanup_numbers.add(created_number)
        for entry_number in sorted(cleanup_numbers):
            subprocess.run(
                [
                    "efibootmgr",
                    "--bootnum",
                    entry_number,
                    "--delete-bootnum",
                ],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        if retained_order:
            subprocess.run(
                ["efibootmgr", "--bootorder", ",".join(retained_order)],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        raise


def rollback_linux_uefi_entry(record: dict[str, Any]) -> None:
    subprocess.run(
        [
            "efibootmgr",
            "--bootnum",
            str(record["entry_number"]),
            "--delete-bootnum",
        ],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    original = record.get("original_boot_order")
    if isinstance(original, list) and original:
        subprocess.run(
            ["efibootmgr", "--bootorder", ",".join(map(str, original))],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def load_plan(path: Path) -> dict[str, Any]:
    plan = read_json(path)
    if not isinstance(plan, dict):
        refuse("install plan is not a JSON object")
    if plan.get("schema") != SCHEMA:
        refuse("unsupported install-plan schema")
    plan_without_id = dict(plan)
    plan_id = plan_without_id.pop("plan_id", None)
    if not isinstance(plan_id, str) or plan_id != digest(plan_without_id):
        refuse("install-plan ID does not match its canonical content")
    status = plan.get("executor_status")
    if status not in {
        LOOP_EXECUTOR_STATUS,
        USB_EXECUTOR_STATUS,
        LIVE_EXECUTOR_STATUS,
    }:
        refuse("install plan is not marked for an approved held executor")
    if status == LIVE_EXECUTOR_STATUS:
        if (
            plan.get("inventory_source") != "live-lsblk"
            or plan.get("execution_eligible") is not True
        ):
            refuse("live executor requires an eligible live inventory plan")
    elif (
        plan.get("inventory_source") != "fixture"
        or plan.get("execution_eligible") is not False
    ):
        refuse("disposable executor accepts only non-executable fixture plans")
    disk = plan.get("disk")
    if not isinstance(disk, dict) or not isinstance(disk.get("serial"), str):
        refuse("held executor plan has no target serial")
    if status == LOOP_EXECUTOR_STATUS and disk.get("serial") != TEST_SERIAL:
        refuse("held loop executor requires the fixed test serial")
    if plan.get("mode") not in {"dual-boot", "wipe"}:
        refuse("unsupported install mode")
    return plan


def replan(
    plan: dict[str, Any], fixture: Path | None, planner: Path
) -> dict[str, Any]:
    arguments = [
        os.fspath(planner),
        "--mode",
        str(plan["mode"]),
        "--disk",
        str(plan["disk"]["path"]),
    ]
    if plan["executor_status"] == LIVE_EXECUTOR_STATUS:
        if fixture is not None:
            refuse("live executor does not accept a fixture inventory")
    else:
        if fixture is None:
            refuse("disposable executor requires its fixture inventory")
        arguments[1:1] = ["--inventory-json", os.fspath(fixture)]
        if plan["executor_status"] == USB_EXECUTOR_STATUS:
            arguments.append("--held-disposable-usb-qualification")
    result = run(arguments)
    regenerated = json.loads(result.stdout)
    if canonical_bytes(regenerated) != canonical_bytes(plan):
        refuse("plan no longer matches a fresh plan from the supplied inventory")
    return regenerated


def live_inventory(device: str) -> dict[str, Any]:
    result = run(
        ["lsblk", "--json", "--bytes", "-o", LSBLK_FIELDS, device]
    )
    inventory = json.loads(result.stdout)
    devices = inventory.get("blockdevices")
    if not isinstance(devices, list) or len(devices) != 1:
        refuse("live target inventory is ambiguous")
    disk = devices[0]
    if not isinstance(disk, dict):
        refuse("live target inventory is malformed")
    return disk


def complete_live_inventory() -> dict[str, Any]:
    result = run(["lsblk", "--json", "--bytes", "-o", LSBLK_FIELDS])
    inventory = json.loads(result.stdout)
    if not isinstance(inventory, dict) or not isinstance(
        inventory.get("blockdevices"), list
    ):
        refuse("complete live target inventory is malformed")
    return inventory


def clean_text(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def as_int(value: Any, description: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        refuse(f"invalid live {description}")
    return value


def mountpoints(value: Any) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list):
        refuse("invalid live mountpoint data")
    return [item for item in value if isinstance(item, str) and item]


def assert_unmounted(disk: dict[str, Any]) -> None:
    found = mountpoints(disk.get("mountpoints"))
    children = disk.get("children") or []
    if not isinstance(children, list):
        refuse("invalid live partition inventory")
    for child in children:
        if not isinstance(child, dict):
            refuse("malformed live partition")
        found.extend(mountpoints(child.get("mountpoints")))
    if found:
        refuse("disposable target or child is mounted: " + ", ".join(found))


def partition_record(
    disk: dict[str, Any], partition: dict[str, Any]
) -> dict[str, Any]:
    sector = as_int(disk.get("log-sec"), "logical sector size")
    start = as_int(partition.get("start"), "partition start") * sector
    return {
        "path": clean_text(partition.get("path")),
        "number": as_int(partition.get("partn"), "partition number"),
        "start_bytes": start,
        "size_bytes": as_int(partition.get("size"), "partition size"),
        "parttype": clean_text(partition.get("parttype")).lower(),
        "partuuid": clean_text(partition.get("partuuid")).lower(),
        "fstype": clean_text(partition.get("fstype")),
        "filesystem_uuid": clean_text(partition.get("uuid")),
        "label": clean_text(partition.get("label")),
        "partition_name": clean_text(partition.get("partlabel")),
    }


def live_partition_records(disk: dict[str, Any]) -> list[dict[str, Any]]:
    children = disk.get("children") or []
    if not isinstance(children, list):
        refuse("invalid live partition inventory")
    records = []
    for child in children:
        if not isinstance(child, dict) or child.get("type") != "part":
            refuse("live target contains a malformed or non-partition child")
        records.append(partition_record(disk, child))
    return sorted(records, key=lambda item: item["number"])


def preserved_projection(record: dict[str, Any]) -> dict[str, Any]:
    return {
        key: record[key]
        for key in (
            "path",
            "number",
            "start_bytes",
            "size_bytes",
            "parttype",
            "partuuid",
            "fstype",
            "filesystem_uuid",
            "label",
            "partition_name",
        )
    }


def assert_live_matches_plan_before(
    plan: dict[str, Any], disk: dict[str, Any], target_kind: str
) -> None:
    identity = plan["disk"]
    expected_type = "loop" if target_kind == "loop" else "disk"
    if disk.get("type") != expected_type:
        refuse(f"held executor target is not a live {expected_type} device")
    identity_fields = [
        ("path", clean_text(disk.get("path"))),
        ("size_bytes", as_int(disk.get("size"), "disk size")),
        (
            "logical_sector_bytes",
            as_int(disk.get("log-sec"), "logical sector size"),
        ),
        ("partition_table", clean_text(disk.get("pttype")).lower()),
        ("partition_table_uuid", clean_text(disk.get("ptuuid")).lower()),
    ]
    if target_kind in {"physical-usb", "live-internal"}:
        identity_fields.extend(
            (
                ("model", clean_text(disk.get("model"))),
                ("serial", clean_text(disk.get("serial"))),
                ("transport", clean_text(disk.get("tran"))),
            )
        )
    for field, live_value in identity_fields:
        if identity.get(field) != live_value:
            refuse(f"live disk identity changed: {field}")
    if disk.get("ro") is not False:
        refuse("live target is read-only")
    if target_kind == "loop":
        if disk.get("rm") is not False or disk.get("hotplug") is not False:
            refuse("live loop target is removable or hot-plug")
    elif target_kind == "physical-usb":
        if (
            disk.get("rm") is not True
            or disk.get("hotplug") is not True
            or clean_text(disk.get("tran")).lower() != "usb"
        ):
            refuse("live physical target is not removable hot-plug USB media")
    elif (
        disk.get("rm") is not False
        or disk.get("hotplug") is not False
        or clean_text(disk.get("tran")).lower() == "usb"
    ):
        refuse("live installation target is not fixed internal media")
    assert_unmounted(disk)
    if plan["mode"] == "dual-boot":
        expected = plan.get("preserved_partitions")
        reclaimed = plan.get("reclaimed_partitions", [])
        if not isinstance(reclaimed, list) or len(reclaimed) > 2:
            refuse("reclaimed partition contract is malformed")
        reclaimed_numbers = {
            item.get("number") for item in reclaimed if isinstance(item, dict)
        }
        records = live_partition_records(disk)
        actual = [
            preserved_projection(record)
            for record in records
            if record["number"] not in reclaimed_numbers
        ]
        if canonical_bytes(actual) != canonical_bytes(expected):
            refuse("live preserved partition identities changed")
        actual_reclaimed = [
            preserved_projection(record)
            for record in records
            if record["number"] in reclaimed_numbers
        ]
        if canonical_bytes(actual_reclaimed) != canonical_bytes(reclaimed):
            refuse("live reclaim partition identity changed")


def loop_backing_path(device: str) -> Path:
    name = Path(device).name
    backing_sysfs = Path("/sys/class/block") / name / "loop/backing_file"
    backing_text = backing_sysfs.read_text(encoding="utf-8").strip()
    backing = Path(backing_text)
    if not backing.is_absolute():
        backing = Path("/") / backing
    return backing.resolve(strict=True)


def validate_loop_marker(device: str, marker_argument: Path) -> Path:
    if marker_argument.is_symlink():
        refuse("disposable marker must not be a symlink")
    marker = marker_argument.resolve(strict=True)
    metadata = marker.lstat()
    if marker.is_symlink() or not stat.S_ISREG(metadata.st_mode):
        refuse("disposable marker is unsafe")
    if marker.read_text(encoding="utf-8") != TEST_MARKER:
        refuse("disposable marker content mismatch")
    parent = marker.parent
    if parent.parent != Path("/tmp") or not parent.name.startswith(
        "sp11-install-executor-loopback."
    ):
        refuse("disposable marker is outside the private loop-test namespace")

    device_path = Path(device)
    device_metadata = device_path.stat()
    if not stat.S_ISBLK(device_metadata.st_mode):
        refuse("target is not a block device")
    name = device_path.name
    if not name.startswith("loop") or not name[4:].isdigit():
        refuse("target is not an exact /dev/loopN device")
    backing = loop_backing_path(device)
    if backing.parent != parent or not backing.is_file() or backing.is_symlink():
        refuse("loop backing file does not share the disposable marker directory")
    return parent


def containing_disk(source: str) -> str:
    result = run(["lsblk", "-s", "-nro", "PATH,TYPE", source]).stdout
    disks = [
        line.split()[0]
        for line in result.splitlines()
        if len(line.split()) == 2 and line.split()[1] == "disk"
    ]
    if len(disks) != 1:
        refuse(f"could not resolve one containing disk for: {source}")
    return os.path.realpath(disks[0])


def validate_usb_marker(
    plan: dict[str, Any], device: str, marker_argument: Path
) -> Path:
    if marker_argument.is_symlink():
        refuse("disposable USB marker must not be a symlink")
    marker = marker_argument.resolve(strict=True)
    metadata = marker.lstat()
    if marker.is_symlink() or not stat.S_ISREG(metadata.st_mode):
        refuse("disposable USB marker is unsafe")
    parent = marker.parent
    if parent.parent != Path("/tmp") or not parent.name.startswith(
        "sp11-install-executor-physical."
    ):
        refuse("disposable USB marker is outside the private test namespace")
    record = read_json(marker)
    disk_identity = plan["disk"]
    if (
        record.get("schema") != USB_MARKER_SCHEMA
        or record.get("serial") != disk_identity["serial"]
        or record.get("size_bytes") != disk_identity["size_bytes"]
        or record.get("device") != device
    ):
        refuse("disposable USB marker identity mismatch")
    by_id_text = record.get("by_id")
    if (
        not isinstance(by_id_text, str)
        or not by_id_text.startswith("/dev/disk/by-id/usb-")
        or disk_identity["serial"] not in by_id_text
    ):
        refuse("disposable USB marker lacks an exact stable USB identity")
    by_id = Path(by_id_text)
    if by_id.parent != Path("/dev/disk/by-id") or os.path.realpath(by_id) != device:
        refuse("stable USB identity no longer resolves to the target")
    device_path = Path(device)
    if not stat.S_ISBLK(device_path.stat().st_mode):
        refuse("disposable USB target is not a block device")
    live = live_inventory(device)
    if (
        disk_identity["serial"] == "0308100000000053"
        or any(
        clean_text(child.get("label")) == "SP11FW"
        for child in live.get("children") or []
        if isinstance(child, dict)
        )
        or clean_text(live.get("label")) == "SP11BETA"
    ):
        refuse("disposable USB target collides with SP11 live media")
    root_source = run(["findmnt", "-rn", "-T", "/", "-o", "SOURCE"]).stdout.strip()
    if containing_disk(root_source) == os.path.realpath(device):
        refuse("disposable USB target is the running root disk")
    return parent


def read_release_identity(release_file: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in release_file.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or not re.fullmatch(r"[A-Z0-9_]+", key):
            refuse("live release identity is malformed")
        values[key] = value
    return values


def secure_boot_enabled() -> bool:
    variables = list(
        Path("/sys/firmware/efi/efivars").glob(
            "SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
        )
    )
    if len(variables) != 1:
        refuse("Secure Boot firmware state is unavailable")
    value = read_kernel_bytes(variables[0])
    if len(value) < 5 or value[4] not in {0, 1}:
        refuse("Secure Boot firmware state is malformed")
    return value[4] == 1


def assert_install_power() -> None:
    ac_online = False
    battery_capacity: int | None = None
    for supply in Path("/sys/class/power_supply").glob("*"):
        type_file = supply / "type"
        if not type_file.is_file():
            continue
        supply_type = read_kernel_text(type_file).strip()
        online_file = supply / "online"
        capacity_file = supply / "capacity"
        if supply_type in {"Mains", "USB", "USB_C", "USB_PD"} and (
            online_file.is_file()
            and read_kernel_text(online_file).strip() == "1"
        ):
            ac_online = True
        if supply_type == "Battery" and capacity_file.is_file():
            text = read_kernel_text(capacity_file).strip()
            if text.isdigit():
                capacity = int(text)
                battery_capacity = (
                    capacity
                    if battery_capacity is None
                    else max(battery_capacity, capacity)
                )
    if not ac_online:
        refuse("AC or USB-PD power must be connected")
    if battery_capacity is None or battery_capacity < 50:
        refuse("battery charge must be readable and at least 50 percent")


def validate_live_environment(
    plan: dict[str, Any], device: str, proof_argument: Path
) -> Path:
    if proof_argument != Path("/etc/sp11-live-release"):
        refuse("live executor requires the fixed live release identity")
    if proof_argument.is_symlink():
        refuse("live release identity must not be a symlink")
    proof = proof_argument.resolve(strict=True)
    metadata = proof.stat()
    if (
        proof != Path("/etc/sp11-live-release")
        or not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != 0
        or metadata.st_mode & 0o022
    ):
        refuse("live release identity is unsafe")
    identity = read_release_identity(proof)
    if (
        identity.get("SP11_HELD_LIVE") != "1"
        or identity.get("SP11_FRESH_INSTALLER") != "1"
        or identity.get("SP11_INSTALLED_ROOTFS_SHA256")
        != EXPECTED_ARCHIVE_SHA
    ):
        refuse("this held live image does not authorize fresh installation")
    product = read_kernel_text(
        Path("/sys/devices/virtual/dmi/id/product_name")
    ).strip()
    compatible = read_kernel_bytes(
        Path("/sys/firmware/devicetree/base/compatible")
    )
    if product != "Microsoft Surface Pro, 11th Edition" or (
        b"microsoft,denali\0" not in compatible
    ):
        refuse("hardware is not the qualified Surface Pro 11 Denali target")
    root_filesystem = run(
        ["findmnt", "-rn", "-T", "/", "-o", "FSTYPE"]
    ).stdout.strip()
    lower_mount = run(
        [
            "findmnt",
            "-rn",
            "/run/sp11-live/lower",
            "-o",
            "TARGET,FSTYPE,OPTIONS",
        ]
    ).stdout.strip().split()
    command_line = read_kernel_text(Path("/proc/cmdline")).split()
    if (
        root_filesystem != "overlay"
        or len(lower_mount) != 3
        or lower_mount[0] != "/run/sp11-live/lower"
        or lower_mount[1] != "squashfs"
        or "ro" not in lower_mount[2].split(",")
        or not Path("/run/sp11-live-session").is_file()
        or not any(item.startswith("sp11live=") for item in command_line)
    ):
        refuse("executor is not running from the qualified RAM-backed live root")
    if secure_boot_enabled():
        refuse(
            "Secure Boot is enabled; this unsigned held image requires it disabled"
        )
    assert_install_power()
    if not re.fullmatch(r"/dev/nvme[0-9]+n[0-9]+", device):
        refuse("live executor accepts only an exact internal NVMe namespace")
    if not stat.S_ISBLK(Path(device).stat().st_mode):
        refuse("live internal target is not a block device")
    live = live_inventory(device)
    if (
        clean_text(live.get("serial")) != plan["disk"]["serial"]
        or live.get("rm") is not False
        or live.get("hotplug") is not False
        or clean_text(live.get("tran")).lower() == "usb"
    ):
        refuse("live internal target identity or transport is unsafe")
    parent = Path("/run/sp11-installer")
    if parent.exists():
        parent_metadata = parent.stat()
        if (
            parent.is_symlink()
            or not parent.is_dir()
            or parent_metadata.st_uid != 0
            or stat.S_IMODE(parent_metadata.st_mode) != 0o700
        ):
            refuse("live transaction directory is unsafe")
    else:
        parent.mkdir(mode=0o700)
    return parent


def validate_target_marker(
    plan: dict[str, Any], device: str, marker: Path
) -> tuple[Path, str]:
    if plan["executor_status"] == LOOP_EXECUTOR_STATUS:
        return validate_loop_marker(device, marker), "loop"
    if plan["executor_status"] == USB_EXECUTOR_STATUS:
        return validate_usb_marker(plan, device, marker), "physical-usb"
    return validate_live_environment(plan, device, marker), "live-internal"


def validate_confirmation(plan: dict[str, Any], typed: str, second: str) -> None:
    confirmation = plan.get("confirmation")
    if not isinstance(confirmation, dict):
        refuse("plan confirmation record is malformed")
    if typed != confirmation.get("required_text"):
        refuse("typed disk confirmation does not exactly match the plan")
    if confirmation.get("second_confirmation_required") is not True:
        refuse("plan does not require a second confirmation")
    if plan["executor_status"] == LOOP_EXECUTOR_STATUS:
        expected_second = SECOND_CONFIRMATION
    elif plan["executor_status"] == USB_EXECUTOR_STATUS:
        expected_second = USB_SECOND_CONFIRMATION
    elif plan["mode"] == "dual-boot":
        expected_second = LIVE_DUAL_SECOND_CONFIRMATION
    else:
        expected_second = LIVE_WIPE_SECOND_CONFIRMATION
    if second != expected_second:
        refuse("second disposable confirmation does not exactly match")


def validate_proposed(plan: dict[str, Any]) -> list[dict[str, Any]]:
    proposed = plan.get("proposed_partitions")
    if not isinstance(proposed, list) or len(proposed) != 2:
        refuse("plan must contain exactly two proposed partitions")
    expected_roles = (
        ("linux-esp", ESP_GUID, "vfat", "SP11EFI"),
        ("linux-root", LINUX_GUID, "ext4", "sp11root"),
    )
    numbers: set[int] = set()
    previous_end = 0
    for item, expected in zip(proposed, expected_roles):
        if not isinstance(item, dict):
            refuse("proposed partition is malformed")
        role, parttype, filesystem, label = expected
        if (
            item.get("role") != role
            or item.get("parttype") != parttype
            or item.get("filesystem") != filesystem
            or item.get("filesystem_label") != label
        ):
            refuse(f"unexpected proposed partition contract: {role}")
        number = item.get("number")
        start = item.get("start_bytes")
        size = item.get("size_bytes")
        if (
            isinstance(number, bool)
            or not isinstance(number, int)
            or number < 1
            or number > 128
            or number in numbers
            or isinstance(start, bool)
            or not isinstance(start, int)
            or isinstance(size, bool)
            or not isinstance(size, int)
            or start % (1024**2)
            or size % (1024**2)
            or start < previous_end
        ):
            refuse("unsafe proposed partition geometry")
        numbers.add(number)
        previous_end = start + size
    return proposed


def partition_path(device: str, number: int) -> str:
    separator = "p" if device[-1:].isdigit() else ""
    return f"{device}{separator}{number}"


def journal_context(
    journal_argument: Path,
    marker: Path,
    *,
    allowed_states: set[str],
) -> tuple[Path, dict[str, Any], str, list[dict[str, Any]], Path, str]:
    if journal_argument.is_symlink():
        refuse("transaction journal must not be a symlink")
    journal = journal_argument.resolve(strict=True)
    if not journal.is_dir():
        refuse("unsafe transaction journal")
    plan = load_plan(journal / "plan.json")
    device = str(plan["disk"]["path"])
    parent, target_kind = validate_target_marker(plan, device, marker)
    if journal.parent != parent:
        refuse("journal is outside its authorized transaction directory")
    state = (journal / "STATE").read_text(encoding="utf-8").strip()
    if state not in allowed_states:
        refuse(f"transaction state is not allowed here: {state}")
    created = read_json(journal / "created-partitions.json")
    if not isinstance(created, list):
        refuse("created partition journal is malformed")
    live = live_inventory(device)
    assert_unmounted(live)
    records = live_partition_records(live)
    assert_created_unchanged(created, records)
    validate_preserved_after(plan, records)
    return journal, plan, device, created, parent, target_kind


def settle(device: str) -> None:
    run(["partprobe", device], stdout=None)
    run(["udevadm", "settle"], stdout=None)


def create_partitions(
    plan: dict[str, Any], device: str, proposed: list[dict[str, Any]]
) -> None:
    sector_size = int(plan["disk"]["logical_sector_bytes"])
    reclaimed = plan.get("reclaimed_partitions", [])
    if reclaimed:
        if plan["mode"] != "dual-boot" or len(reclaimed) not in {1, 2}:
            refuse("unsafe reclaim partition contract")
        reclaim_numbers = [item.get("number") for item in reclaimed]
        proposed_numbers = [item.get("number") for item in proposed]
        if reclaim_numbers != proposed_numbers[: len(reclaim_numbers)]:
            refuse("reclaimed partitions do not match the proposed Linux slots")
        run(
            [
                "sfdisk",
                "--lock=yes",
                "--delete",
                device,
                *map(str, reclaim_numbers),
            ],
            stdout=None,
        )
        settle(device)
    lines = []
    for item in proposed:
        number = int(item["number"])
        start = int(item["start_bytes"]) // sector_size
        sectors = int(item["size_bytes"]) // sector_size
        lines.append(
            f"{partition_path(device, number)} : "
            f"start={start}, size={sectors}, "
            f"type={item['parttype']}, "
            f'name="{item["partition_name"]}"'
        )
    script = "\n".join(lines) + "\n"
    arguments = ["sfdisk", "--lock=yes"]
    if plan["mode"] == "dual-boot":
        arguments.extend(("--append", "--wipe=never"))
    else:
        arguments.append("--wipe=always")
        script = "label: gpt\nunit: sectors\n\n" + script
    arguments.append(device)
    run(arguments, stdout=None, input_text=script)
    run(["sfdisk", "--verify", device], stdout=None)
    settle(device)


def assert_partition_geometry(
    proposed: list[dict[str, Any]], records: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    by_number = {record["number"]: record for record in records}
    created = []
    for item in proposed:
        record = by_number.get(item["number"])
        if record is None:
            refuse(f"created partition is missing: {item['number']}")
        for field in ("start_bytes", "size_bytes", "parttype", "partition_name"):
            expected_field = (
                "partition_name" if field == "partition_name" else field
            )
            if record[field] != item[expected_field]:
                refuse(
                    f"created partition {item['number']} geometry mismatch: {field}"
                )
        created.append(record)
    return created


def format_partitions(device: str, proposed: list[dict[str, Any]]) -> None:
    esp, root = proposed
    run(
        [
            "mkfs.fat",
            "-F",
            "32",
            "-n",
            str(esp["filesystem_label"]),
            partition_path(device, int(esp["number"])),
        ],
        stdout=None,
    )
    run(
        [
            "mkfs.ext4",
            "-F",
            "-L",
            str(root["filesystem_label"]),
            partition_path(device, int(root["number"])),
        ],
        stdout=None,
    )
    run(["udevadm", "settle"], stdout=None)


def validate_formatted(
    proposed: list[dict[str, Any]], records: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    created = assert_partition_geometry(proposed, records)
    for item, record in zip(proposed, created):
        if (
            record["fstype"] != item["filesystem"]
            or record["label"] != item["filesystem_label"]
            or not record["filesystem_uuid"]
            or not record["partuuid"]
        ):
            refuse(f"created partition is not correctly formatted: {item['role']}")
    return created


def validate_preserved_after(
    plan: dict[str, Any], records: list[dict[str, Any]]
) -> None:
    if plan["mode"] != "dual-boot":
        return
    created_numbers = {
        item["number"] for item in plan["proposed_partitions"]
    }
    actual = [
        preserved_projection(record)
        for record in records
        if record["number"] not in created_numbers
    ]
    if canonical_bytes(actual) != canonical_bytes(plan["preserved_partitions"]):
        refuse("a preserved partition identity changed during execution")


def initialize_journal(
    journal: Path,
    plan: dict[str, Any],
    fixture: dict[str, Any],
    live_before: dict[str, Any],
    device: str,
) -> None:
    journal.mkdir(mode=0o700)
    write_json(journal / "plan.json", plan)
    write_json(journal / "fixture-inventory.json", fixture)
    write_json(journal / "live-before.json", live_before)
    write_json(
        journal / "transaction.json",
        {
            "schema": JOURNAL_SCHEMA,
            "mode": plan["mode"],
            "plan_id": plan["plan_id"],
            "device": device,
            "initial_status": "PREPARED",
        },
    )
    replace_state(journal / "STATE", "PREPARED")
    dump = run(["sfdisk", "--dump", device]).stdout
    (journal / "sfdisk-before.txt").write_text(dump, encoding="utf-8")
    append_event(journal, "prepared", plan_id=plan["plan_id"], device=device)


def ensure_journal_target(parent: Path, argument: Path) -> Path:
    if argument.is_absolute():
        candidate = argument
    else:
        candidate = parent / argument
    candidate_parent = candidate.parent.resolve(strict=True)
    if candidate_parent != parent or candidate.name in {"", ".", ".."}:
        refuse("journal must be a new direct child of the disposable directory")
    if candidate.exists() or candidate.is_symlink():
        refuse("journal output already exists")
    return candidate


def apply(args: argparse.Namespace, planner: Path) -> None:
    plan = load_plan(args.plan)
    fixture = (
        read_json(args.inventory_json)
        if args.inventory_json is not None
        else complete_live_inventory()
    )
    if not isinstance(fixture, dict):
        refuse("source inventory is not a JSON object")
    replan(plan, args.inventory_json, planner)
    validate_confirmation(plan, args.confirm, args.second_confirm)
    proposed = validate_proposed(plan)
    device = str(plan["disk"]["path"])
    parent, target_kind = validate_target_marker(
        plan, device, args.test_marker
    )
    journal = ensure_journal_target(parent, args.journal)
    live_before = live_inventory(device)
    assert_live_matches_plan_before(plan, live_before, target_kind)

    initialize_journal(journal, plan, fixture, live_before, device)
    try:
        append_event(journal, "partitioning-started")
        replace_state(journal / "STATE", "PARTITIONING")
        create_partitions(plan, device, proposed)
        after_partitioning = live_inventory(device)
        assert_unmounted(after_partitioning)
        records = live_partition_records(after_partitioning)
        assert_partition_geometry(proposed, records)
        validate_preserved_after(plan, records)
        write_json(journal / "live-after-partitioning.json", after_partitioning)

        append_event(journal, "formatting-started")
        replace_state(journal / "STATE", "FORMATTING")
        format_partitions(device, proposed)
        live_after = live_inventory(device)
        assert_unmounted(live_after)
        records = live_partition_records(live_after)
        created = validate_formatted(proposed, records)
        validate_preserved_after(plan, records)
        write_json(journal / "live-after.json", live_after)
        write_json(journal / "created-partitions.json", created)
        replace_state(journal / "STATE", "PARTITIONED")
        append_event(journal, "partitioned", created=created)
    except BaseException as error:
        replace_state(journal / "STATE", "FAILED")
        append_event(journal, "failed", error=repr(error))
        raise

    print(f"Held {target_kind} partition executor passed.")
    print(f"Plan ID: {plan['plan_id']}")
    print(f"Journal: {journal}")


def assert_created_unchanged(
    expected: list[dict[str, Any]], actual: list[dict[str, Any]]
) -> None:
    by_number = {record["number"]: record for record in actual}
    for saved in expected:
        current = by_number.get(saved["number"])
        if current is None or canonical_bytes(current) != canonical_bytes(saved):
            refuse(f"created partition changed before removal: {saved['number']}")


def created_by_role(
    plan: dict[str, Any], created: list[dict[str, Any]]
) -> dict[str, dict[str, Any]]:
    by_number = {item["number"]: item for item in created}
    result = {}
    for proposed in plan["proposed_partitions"]:
        record = by_number.get(proposed["number"])
        if record is None:
            refuse(f"journal is missing created role: {proposed['role']}")
        result[proposed["role"]] = record
    if set(result) != {"linux-esp", "linux-root"}:
        refuse("journal does not contain the required installation roles")
    return result


def validate_artifact(artifact_argument: Path, script_dir: Path) -> Path:
    artifact = artifact_argument.resolve(strict=True)
    if artifact.is_symlink() or not artifact.is_dir():
        refuse("installed-root artifact directory is unsafe")
    archive = artifact / "sp11-installed-rootfs.tar.zst"
    manifest = artifact / "ROOTFS-FILES.tsv"
    if (
        not archive.is_file()
        or archive.is_symlink()
        or file_digest(archive) != EXPECTED_ARCHIVE_SHA
        or not manifest.is_file()
        or manifest.is_symlink()
        or file_digest(manifest) != EXPECTED_ROOT_MANIFEST_SHA
    ):
        refuse("installed-root artifact identity mismatch")
    image = artifact / f"boot/Image-{RELEASE}"
    dtb = artifact / "boot/x1e80100-microsoft-denali-oled.dtb"
    if (
        not image.is_file()
        or image.is_symlink()
        or file_digest(image) != EXPECTED_IMAGE_SHA
        or not dtb.is_file()
        or dtb.is_symlink()
        or file_digest(dtb) != EXPECTED_DTB_SHA
    ):
        refuse("installed-root boot payload identity mismatch")
    if (artifact / "rootfs").is_dir():
        run(
            [
                os.fspath(script_dir / "audit-installed-rootfs.sh"),
                os.fspath(artifact),
            ],
            stdout=None,
        )
    else:
        run(["zstd", "-q", "-t", os.fspath(archive)], stdout=None)
        listing = run(
            ["tar", "--zstd", "-tf", os.fspath(archive)]
        ).stdout.splitlines()
        if len(listing) < 100000 or any(
            entry.startswith("/") or ".." in Path(entry).parts
            for entry in listing
        ):
            refuse("installed-root archive member list is unsafe")
    return artifact


OWNER_FIRMWARE_PATHS = {
    "qcom/x1e80100/microsoft/Denali/adsp_dtb.mbn": "Surface ADSP device tree",
    "qcom/x1e80100/microsoft/Denali/qcadsp8380.mbn": "Surface ADSP image",
    "qcom/x1e80100/microsoft/Denali/cdsp_dtb.mbn": "Surface CDSP device tree",
    "qcom/x1e80100/microsoft/Denali/qccdsp8380.mbn": "Surface CDSP image",
    "qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn": "Adreno GPU zap shader",
}

# Files the live image carries that the installed system should keep so the
# owner can (re)collect firmware later without the USB stick.
INSTALLED_TOOLS = (
    "usr/local/bin/sp11-firmware",
    "usr/local/libexec/sp11-validate-external-firmware",
)


def load_external_firmware(
    manifest: Path | None, source_root: Path
) -> list[dict[str, Any]]:
    if source_root.is_symlink() or not source_root.is_dir():
        refuse("owner firmware source root is unsafe")
    records = []
    if manifest is None:
        # No manifest: describe the five files that are actually present.
        for relative, purpose in OWNER_FIRMWARE_PATHS.items():
            source_file = source_root / relative
            if source_file.is_symlink() or not source_file.is_file():
                refuse(f"owner firmware is missing: {relative}")
            records.append(
                {
                    "path": relative,
                    "bytes": source_file.stat().st_size,
                    "sha256": file_digest(source_file),
                    "purpose": purpose,
                    "source": source_file,
                }
            )
        return records
    with manifest.open("r", encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source, delimiter="\t")
        if not reader.fieldnames or not {"path", "bytes", "sha256"} <= set(reader.fieldnames):
            refuse("owner firmware manifest header mismatch")
        for row in reader:
            relative = row.get("path", "")
            expected_bytes = row.get("bytes", "")
            expected_sha = row.get("sha256", "")
            purpose = row.get("purpose", "owner-supplied SP11 firmware")
            if (
                relative.startswith("/")
                or ".." in Path(relative).parts
                or not expected_bytes.isdigit()
                or not re.fullmatch(r"[0-9a-f]{64}", expected_sha)
            ):
                refuse("unsafe owner firmware manifest record")
            source_file = source_root / relative
            if (
                source_file.is_symlink()
                or not source_file.is_file()
                or source_file.stat().st_size != int(expected_bytes)
                or file_digest(source_file) != expected_sha
            ):
                refuse(f"owner firmware identity mismatch: {relative}")
            records.append(
                {
                    "path": relative,
                    "bytes": int(expected_bytes),
                    "sha256": expected_sha,
                    "purpose": purpose,
                    "source": source_file,
                }
            )
    if len(records) != 5:
        refuse(f"expected five owner firmware files, found {len(records)}")
    return records


def validate_account(username: str, hash_file: Path) -> str:
    if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,30}", username):
        refuse("username does not satisfy the installer account policy")
    if username in {"root", "gdm", "nobody", "alpm"}:
        refuse("username collides with a reserved system account")
    if hash_file.is_symlink() or not hash_file.is_file():
        refuse("password hash file is unsafe")
    password_hash = hash_file.read_text(encoding="utf-8").rstrip("\n")
    if (
        "\n" in password_hash
        or ":" in password_hash
        or not password_hash.startswith(("$6$", "$y$"))
        or len(password_hash) > 512
    ):
        refuse("password hash must contain one SHA-512 or yescrypt hash")
    return password_hash


def filesystem_uuid(device: str) -> str:
    value = run(["blkid", "-s", "UUID", "-o", "value", device]).stdout.strip()
    if not re.fullmatch(r"[0-9A-Fa-f-]{4,64}", value):
        refuse(f"filesystem UUID is unsafe or missing: {device}")
    return value


def write_text(path: Path, content: str, mode: int = 0o644) -> None:
    if path.exists() or path.is_symlink():
        path.unlink()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8", newline="\n") as output:
        output.write(content)
    path.chmod(mode)


def isolate_mount_namespace() -> None:
    os.unshare(os.CLONE_NEWNS)
    run(["mount", "--make-rprivate", "/"], stdout=None)


def mount_targets_below(root: Path) -> list[Path]:
    root_text = os.fspath(root)
    targets: list[Path] = []
    escapes = {"\\040": " ", "\\011": "\t", "\\012": "\n", "\\134": "\\"}
    for line in Path("/proc/self/mountinfo").read_text(encoding="utf-8").splitlines():
        fields = line.split(" - ", maxsplit=1)[0].split()
        if len(fields) < 5:
            refuse("malformed mountinfo while cleaning installation mounts")
        mount_point = fields[4]
        for escaped, decoded in escapes.items():
            mount_point = mount_point.replace(escaped, decoded)
        if mount_point == root_text or mount_point.startswith(f"{root_text}/"):
            targets.append(Path(mount_point))
    return sorted(targets, key=lambda path: len(path.parts), reverse=True)


def unmount_below(root: Path) -> None:
    for target in mount_targets_below(root):
        subprocess.run(
            ["umount", os.fspath(target)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    remaining = mount_targets_below(root)
    for target in remaining:
        subprocess.run(
            ["umount", "--lazy", os.fspath(target)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    remaining = mount_targets_below(root)
    if remaining:
        refuse(
            "installation mount cleanup failed below "
            f"{root}: {', '.join(map(os.fspath, remaining))}"
        )


def mount_installation(
    root_device: str, esp_device: str, mount_root: Path, *, read_only: bool
) -> None:
    mount_root.mkdir(mode=0o700)
    root_options = ["-o", "ro,noload"] if read_only else []
    run(["mount", *root_options, root_device, os.fspath(mount_root)], stdout=None)
    (mount_root / "efi").mkdir(exist_ok=True)
    esp_options = ["-o", "ro"] if read_only else []
    run(
        [
            "mount",
            *esp_options,
            esp_device,
            os.fspath(mount_root / "efi"),
        ],
        stdout=None,
    )
def unmount_installation(mount_root: Path) -> None:
    if mount_root.exists():
        unmount_below(mount_root)
        if any(mount_root.iterdir()):
            refuse(f"installation mount directory is not empty: {mount_root}")
        mount_root.rmdir()


def mount_runtime(root: Path) -> None:
    specifications = (
        ("dev", "devtmpfs", "devtmpfs", "mode=0755,nosuid"),
        ("proc", "proc", "proc", "nosuid,nodev,noexec"),
        ("sys", "sysfs", "sysfs", "nosuid,nodev,noexec,ro"),
        ("run", "tmpfs", "tmpfs", "mode=0755,nosuid,nodev"),
    )
    mounted: list[Path] = []
    try:
        for relative, source, filesystem, options in specifications:
            target = root / relative
            target.mkdir(exist_ok=True)
            run(
                [
                    "mount",
                    "-t",
                    filesystem,
                    "-o",
                    options,
                    source,
                    os.fspath(target),
                ],
                stdout=None,
            )
            run(["mount", "--make-private", os.fspath(target)], stdout=None)
            mounted.append(target)
    except BaseException:
        for target in reversed(mounted):
            subprocess.run(
                ["umount", os.fspath(target)],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        raise


def unmount_runtime(root: Path) -> None:
    for relative in ("run", "sys", "proc", "dev"):
        unmount_below(root / relative)


def windows_boot_record(
    plan: dict[str, Any], parent: Path
) -> dict[str, Any] | None:
    if plan["mode"] != "dual-boot":
        return None
    candidates = [
        item
        for item in plan["preserved_partitions"]
        if item["parttype"] == ESP_GUID
    ]
    if len(candidates) != 1:
        refuse("dual-boot plan has no unique preserved Windows ESP")
    windows_esp = candidates[0]
    if windows_esp["fstype"] != "vfat" or not windows_esp["filesystem_uuid"]:
        refuse("preserved Windows ESP lacks a vfat filesystem identity")
    mount_root = parent / "windows-esp-read-only"
    if mount_root.exists():
        if mount_root.is_symlink() or not mount_root.is_dir() or any(
            mount_root.iterdir()
        ):
            refuse("Windows ESP verification mount directory is unsafe")
    else:
        mount_root.mkdir(mode=0o700)
    try:
        run(
            ["mount", "-o", "ro", windows_esp["path"], os.fspath(mount_root)],
            stdout=None,
        )
        loader = mount_root / "EFI/Microsoft/Boot/bootmgfw.efi"
        if loader.is_symlink() or not loader.is_file():
            refuse("Windows Boot Manager is missing from the preserved ESP")
        return {
            "partition": windows_esp,
            "loader_sha256": file_digest(loader),
            "loader_bytes": loader.stat().st_size,
        }
    finally:
        subprocess.run(
            ["umount", os.fspath(mount_root)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        mount_root.rmdir()


def configure_target(
    root: Path,
    artifact: Path,
    firmware: list[dict[str, Any]],
    username: str,
    password_hash: str,
    timezone: str,
    root_uuid: str,
    esp_uuid: str,
    windows: dict[str, Any] | None,
) -> None:
    write_text(
        root / "etc/fstab",
        (
            f"UUID={root_uuid}\t/\text4\tdefaults\t0 1\n"
            f"UUID={esp_uuid}\t/efi\tvfat\tumask=0077\t0 2\n"
        ),
    )
    write_text(root / "etc/hostname", "sp11\n")
    zone = root / "usr/share/zoneinfo" / timezone
    if (
        timezone.startswith("/")
        or ".." in Path(timezone).parts
        or zone.is_symlink()
        or not zone.is_file()
    ):
        refuse("timezone is not present in the installed root")
    localtime = root / "etc/localtime"
    localtime.unlink(missing_ok=True)
    localtime.symlink_to(f"/usr/share/zoneinfo/{timezone}")

    run(["systemd-machine-id-setup", f"--root={root}"], stdout=None)
    machine_id = (root / "etc/machine-id").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"[0-9a-f]{32}", machine_id):
        refuse("target machine ID generation failed")
    pacman_gnupg = root / "etc/pacman.d/gnupg"
    if pacman_gnupg.exists() and any(pacman_gnupg.iterdir()):
        refuse("installed-root artifact contains a preseeded pacman keyring")
    run(
        ["chroot", os.fspath(root), "/usr/bin/pacman-key", "--init"],
        stdout=None,
    )
    run(
        [
            "chroot",
            os.fspath(root),
            "/usr/bin/pacman-key",
            "--populate",
            "archlinuxarm",
        ],
        stdout=None,
    )
    run(
        [
            "chroot",
            os.fspath(root),
            "/usr/bin/gpgconf",
            "--homedir",
            "/etc/pacman.d/gnupg",
            "--kill",
            "all",
        ],
        stdout=None,
    )
    write_text(root / "etc/nvme/hostid", f"{root_uuid.lower()}\n")
    write_text(
        root / "etc/nvme/hostnqn",
        f"nqn.2014-08.org.nvmexpress:uuid:{root_uuid.lower()}\n",
    )

    for record in firmware:
        destination = root / "usr/lib/firmware" / record["path"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(record["source"], destination)
        destination.chmod(0o644)

    run(
        [
            "chroot",
            os.fspath(root),
            "/usr/sbin/useradd",
            "--create-home",
            "--groups",
            "wheel,audio,video,input,storage",
            "--shell",
            "/bin/bash",
            username,
        ],
        stdout=None,
    )
    run(
        ["chroot", os.fspath(root), "/usr/sbin/chpasswd", "--encrypted"],
        stdout=None,
        input_text=f"{username}:{password_hash}\n",
    )
    write_text(
        root / "etc/sudoers.d/10-sp11-wheel",
        "%wheel ALL=(ALL:ALL) ALL\n",
        0o440,
    )

    boot_dir = root / "boot/sp11"
    boot_dir.mkdir(parents=True)
    image = artifact / f"boot/Image-{RELEASE}"
    dtb = artifact / "boot/x1e80100-microsoft-denali-oled.dtb"
    if file_digest(image) != EXPECTED_IMAGE_SHA or file_digest(dtb) != EXPECTED_DTB_SHA:
        refuse("installed-root boot payload identity mismatch")
    shutil.copyfile(image, boot_dir / image.name)
    shutil.copyfile(dtb, boot_dir / dtb.name)
    (boot_dir / image.name).chmod(0o644)
    (boot_dir / dtb.name).chmod(0o644)

    write_text(
        root / "etc/default/grub",
        (
            'GRUB_DEFAULT="sp11-linux"\n'
            "GRUB_TIMEOUT=5\n"
            "GRUB_TIMEOUT_STYLE=menu\n"
            "GRUB_DISABLE_SUBMENU=y\n"
            "GRUB_DISABLE_OS_PROBER=true\n"
        ),
    )
    grub_lines = [
        "#!/bin/sh",
        "cat <<'SP11_GRUB_EOF'",
        "menuentry 'SP11 Linux' --id sp11-linux {",
        f"    search --no-floppy --fs-uuid --set=root {root_uuid}",
        (
            "    devicetree /boot/sp11/"
            "x1e80100-microsoft-denali-oled.dtb"
        ),
        (
            f"    linux /boot/sp11/Image-{RELEASE} "
            f"root=UUID={root_uuid} rw rootwait quiet systemd.tpm2_wait=false"
        ),
        f"    initrd /boot/sp11/initramfs-{RELEASE}.img",
        "}",
    ]
    if windows is not None:
        windows_uuid = windows["partition"]["filesystem_uuid"]
        grub_lines.extend(
            [
                "menuentry 'Windows Boot Manager' --id windows {",
                f"    search --no-floppy --fs-uuid --set=win {windows_uuid}",
                "    chainloader ($win)/EFI/Microsoft/Boot/bootmgfw.efi",
                "}",
            ]
        )
    grub_lines.extend(("SP11_GRUB_EOF", ""))
    write_text(
        root / "etc/grub.d/09_sp11_fresh",
        "\n".join(grub_lines),
        0o755,
    )

    run(["chroot", os.fspath(root), "/usr/bin/depmod", RELEASE], stdout=None)
    run(
        [
            "chroot",
            os.fspath(root),
            "/usr/bin/mkinitcpio",
            "-k",
            RELEASE,
            "-g",
            f"/boot/sp11/initramfs-{RELEASE}.img",
        ],
        stdout=None,
    )
    run(
        [
            "chroot",
            os.fspath(root),
            "/usr/bin/grub-install",
            "--target=arm64-efi",
            "--efi-directory=/efi",
            "--bootloader-id=SP11Linux",
            "--no-nvram",
            "--removable",
            "--recheck",
        ],
        stdout=None,
    )
    run(
        [
            "chroot",
            os.fspath(root),
            "/usr/bin/grub-mkconfig",
            "-o",
            "/boot/grub/grub.cfg",
        ],
        stdout=None,
    )
    # Keep the firmware tooling and the beta documentation on the installed
    # system so firmware can be (re)collected from Windows later.
    for relative in INSTALLED_TOOLS:
        source = Path("/") / relative
        if source.is_symlink() or not source.is_file():
            continue
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        destination.chmod(0o755)
    live_docs = Path("/usr/share/doc/sp11-beta")
    if live_docs.is_dir():
        target_docs = root / "usr/share/doc/sp11-beta"
        target_docs.mkdir(parents=True, exist_ok=True)
        for document in live_docs.iterdir():
            if document.is_file() and not document.is_symlink():
                shutil.copyfile(document, target_docs / document.name)
                (target_docs / document.name).chmod(0o644)

    with (root / "etc/sp11-installed-root-release").open(
        "a", encoding="utf-8"
    ) as release_file:
        release_file.write(
            f"SP11_EXTERNAL_FIRMWARE_INSTALLED={1 if firmware else 0}\n"
        )
        release_file.write(f"SP11_ACCOUNT_PROVISIONED={username}\n")
        release_file.write("SP11_BOOT_PROVISIONED=grub-arm64-efi\n")


def populate(args: argparse.Namespace, script_dir: Path) -> None:
    isolate_mount_namespace()
    journal, plan, device, created, parent, target_kind = journal_context(
        args.journal, args.test_marker, allowed_states={"PARTITIONED"}
    )
    artifact = validate_artifact(args.artifact, script_dir)
    firmware_source = args.owner_firmware_root.resolve(strict=True)
    firmware_manifest = Path("/etc/sp11-external-firmware-manifest.tsv")
    if firmware_manifest.is_file() and not firmware_manifest.is_symlink():
        firmware = load_external_firmware(firmware_manifest, firmware_source)
    elif all(
        (firmware_source / relative).is_file() for relative in OWNER_FIRMWARE_PATHS
    ):
        firmware = load_external_firmware(None, firmware_source)
    elif args.allow_missing_owner_firmware:
        firmware = []
    else:
        refuse(
            "owner firmware is not imported in this live session; run "
            "RUN-IN-WINDOWS.cmd or 'sudo sp11-firmware collect --to-usb' and "
            "reboot the USB, or choose to install without firmware"
        )
    password_hash = validate_account(args.username, args.password_hash_file)
    roles = created_by_role(plan, created)
    root_device = partition_path(device, roles["linux-root"]["number"])
    esp_device = partition_path(device, roles["linux-esp"]["number"])
    root_uuid = filesystem_uuid(root_device)
    esp_uuid = filesystem_uuid(esp_device)
    windows = windows_boot_record(plan, parent)
    mount_root = parent / "populate-mount"
    if mount_root.exists() or mount_root.is_symlink():
        refuse("population mount namespace already exists")

    replace_state(journal / "STATE", "POPULATING")
    append_event(journal, "population-started")
    boot_record: dict[str, Any] | None = None
    try:
        mount_installation(root_device, esp_device, mount_root, read_only=False)
        run(
            [
                "tar",
                "--zstd",
                "--extract",
                "--preserve-permissions",
                "--numeric-owner",
                "--xattrs",
                "--acls",
                "-f",
                os.fspath(artifact / "sp11-installed-rootfs.tar.zst"),
                "-C",
                os.fspath(mount_root),
            ],
            stdout=None,
        )
        mount_runtime(mount_root)
        try:
            configure_target(
                mount_root,
                artifact,
                firmware,
                args.username,
                password_hash,
                args.timezone,
                root_uuid,
                esp_uuid,
                windows,
            )
        finally:
            unmount_runtime(mount_root)
        if target_kind == "live-internal":
            boot_record = provision_linux_uefi_entry(
                device, roles["linux-esp"]
            )
            write_json(journal / "uefi-boot-entry.json", boot_record)
            append_event(
                journal,
                "uefi-boot-entry-created",
                entry_number=boot_record["entry_number"],
                original_boot_order=boot_record["original_boot_order"],
                final_boot_order=boot_record["final_boot_order"],
            )
        install_record = {
            "schema": "sp11.installed-target.v1",
            "plan_id": plan["plan_id"],
            "root_device": root_device,
            "root_uuid": root_uuid,
            "esp_device": esp_device,
            "esp_uuid": esp_uuid,
            "username": args.username,
            "timezone": args.timezone,
            "artifact_sha256": EXPECTED_ARCHIVE_SHA,
            "firmware": [
                {
                    key: record[key]
                    for key in ("path", "bytes", "sha256", "purpose")
                }
                for record in firmware
            ],
            "windows": windows,
            "uefi_boot_entry": boot_record,
        }
        write_json(journal / "installed-target.json", install_record)
        manifest = journal / "installed-target-files.tsv"
        run(
            [
                os.fspath(script_dir / "manifest-installed-rootfs.py"),
                os.fspath(mount_root),
                os.fspath(manifest),
            ],
            stdout=None,
        )
        run(["sync"], stdout=None)
        replace_state(journal / "STATE", "INSTALLED-UNVERIFIED")
        append_event(journal, "population-complete")
    except BaseException as error:
        if boot_record is not None:
            rollback_linux_uefi_entry(boot_record)
            append_event(
                journal,
                "uefi-boot-entry-rolled-back",
                entry_number=boot_record["entry_number"],
            )
        replace_state(journal / "STATE", "POPULATION-FAILED")
        append_event(journal, "population-failed", error=repr(error))
        raise
    finally:
        unmount_installation(mount_root)

    print("Held root population completed.")
    print(f"Plan ID: {plan['plan_id']}")
    print(f"Journal: {journal}")


def verify_installed(args: argparse.Namespace, script_dir: Path) -> None:
    journal, plan, device, created, parent, target_kind = journal_context(
        args.journal,
        args.test_marker,
        allowed_states={"INSTALLED-UNVERIFIED", "VERIFIED"},
    )
    record = read_json(journal / "installed-target.json")
    if not isinstance(record, dict) or record.get("plan_id") != plan["plan_id"]:
        refuse("installed-target record is malformed")
    roles = created_by_role(plan, created)
    root_device = partition_path(device, roles["linux-root"]["number"])
    esp_device = partition_path(device, roles["linux-esp"]["number"])
    if (
        record.get("root_device") != root_device
        or record.get("esp_device") != esp_device
        or record.get("root_uuid") != filesystem_uuid(root_device)
        or record.get("esp_uuid") != filesystem_uuid(esp_device)
    ):
        refuse("installed filesystem identity changed")
    current_windows = windows_boot_record(plan, parent)
    if canonical_bytes(current_windows) != canonical_bytes(record.get("windows")):
        refuse("preserved Windows Boot Manager identity changed")
    boot_record = record.get("uefi_boot_entry")
    if target_kind == "live-internal":
        if (
            not isinstance(boot_record, dict)
            or boot_record.get("schema") != "sp11.uefi-boot-entry.v1"
            or boot_record.get("esp_number") != roles["linux-esp"]["number"]
            or boot_record.get("esp_partuuid")
            != roles["linux-esp"]["partuuid"]
            or not re.fullmatch(
                r"[0-9A-F]{4}", str(boot_record.get("entry_number", ""))
            )
        ):
            refuse("installed UEFI boot-entry journal is malformed")
        assert_linux_uefi_entry(
            read_uefi_boot_state(),
            str(boot_record["entry_number"]),
            roles["linux-esp"],
        )
    elif boot_record is not None:
        refuse("non-internal test unexpectedly journaled a UEFI boot entry")
    mount_root = parent / "verify-mount"
    if mount_root.exists() or mount_root.is_symlink():
        refuse("verification mount namespace already exists")
    backing = (
        loop_backing_path(device)
        if target_kind == "loop"
        else Path(device).resolve(strict=True)
    )
    read_only_loop = ""
    try:
        read_only_loop = run(
            [
                "losetup",
                "--find",
                "--show",
                "--read-only",
                "--partscan",
                os.fspath(backing),
            ]
        ).stdout.strip()
        run(["udevadm", "settle"], stdout=None)
        if (
            not re.fullmatch(r"/dev/loop[0-9]+", read_only_loop)
            or read_only_loop == device
            or run(["blockdev", "--getro", read_only_loop]).stdout.strip() != "1"
            or loop_backing_path(read_only_loop) != backing
        ):
            refuse("read-only verification loop identity mismatch")
        read_only_root = partition_path(
            read_only_loop, roles["linux-root"]["number"]
        )
        read_only_esp = partition_path(
            read_only_loop, roles["linux-esp"]["number"]
        )
        mount_installation(
            read_only_root, read_only_esp, mount_root, read_only=True
        )
        verification = parent / f"verify-files-{os.getpid()}.tsv"
        run(
            [
                os.fspath(script_dir / "manifest-installed-rootfs.py"),
                os.fspath(mount_root),
                os.fspath(verification),
            ],
            stdout=None,
        )
        if subprocess.run(
            [
                "cmp",
                "--",
                os.fspath(journal / "installed-target-files.tsv"),
                os.fspath(verification),
            ],
            check=False,
        ).returncode != 0:
            refuse("installed target differs from its complete manifest")
        verification.unlink()

        root_uuid = str(record["root_uuid"])
        esp_uuid = str(record["esp_uuid"])
        expected_fstab = (
            f"UUID={root_uuid}\t/\text4\tdefaults\t0 1\n"
            f"UUID={esp_uuid}\t/efi\tvfat\tumask=0077\t0 2\n"
        )
        if (mount_root / "etc/fstab").read_text(encoding="utf-8") != expected_fstab:
            refuse("installed fstab differs from the journal")
        machine_id = (mount_root / "etc/machine-id").read_text(
            encoding="utf-8"
        ).strip()
        if not re.fullmatch(r"[0-9a-f]{32}", machine_id):
            refuse("installed machine ID is invalid")
        if (mount_root / "etc/nvme/hostid").read_text(
            encoding="utf-8"
        ).strip().lower() != root_uuid.lower():
            refuse("installed NVMe host ID mismatch")

        username = str(record["username"])
        shadow_lines = (mount_root / "etc/shadow").read_text(
            encoding="utf-8"
        ).splitlines()
        matching = [line.split(":", 2) for line in shadow_lines if line]
        accounts = [fields for fields in matching if fields[0] == username]
        if (
            len(accounts) != 1
            or not accounts[0][1]
            or accounts[0][1].startswith(("!", "*"))
        ):
            refuse("installed user account is missing or locked")
        if not (mount_root / "home" / username).is_dir():
            refuse("installed user home is missing")

        for firmware in record["firmware"]:
            firmware_file = mount_root / "usr/lib/firmware" / firmware["path"]
            if (
                not firmware_file.is_file()
                or firmware_file.is_symlink()
                or firmware_file.stat().st_size != firmware["bytes"]
                or file_digest(firmware_file) != firmware["sha256"]
            ):
                refuse(f"installed owner firmware mismatch: {firmware['path']}")

        image = mount_root / f"boot/sp11/Image-{RELEASE}"
        dtb = mount_root / "boot/sp11/x1e80100-microsoft-denali-oled.dtb"
        initramfs = mount_root / f"boot/sp11/initramfs-{RELEASE}.img"
        if (
            file_digest(image) != EXPECTED_IMAGE_SHA
            or file_digest(dtb) != EXPECTED_DTB_SHA
            or not initramfs.is_file()
        ):
            refuse("installed boot payload identity mismatch")
        initramfs_listing = run(["lsinitcpio", os.fspath(initramfs)]).stdout
        if not re.search(r"(^|/)videocc-sm8550\.ko(\.(gz|xz|zst))?$", initramfs_listing, re.M):
            refuse("installed initramfs lacks the required VideoCC module")
        grub_config = (mount_root / "boot/grub/grub.cfg").read_text(
            encoding="utf-8"
        )
        if (
            root_uuid not in grub_config
            or f"Image-{RELEASE}" not in grub_config
            or "x1e80100-microsoft-denali-oled.dtb" not in grub_config
            or not (mount_root / "efi/EFI/BOOT/BOOTAA64.EFI").is_file()
        ):
            refuse("installed ARM64 GRUB state is incomplete")
        module_count = sum(
            1
            for module in (mount_root / f"usr/lib/modules/{RELEASE}").rglob("*.ko")
            if module.is_file()
        )
        if module_count != 3759:
            refuse(f"installed module count mismatch: {module_count}")
    finally:
        unmount_installation(mount_root)
        if read_only_loop:
            run(["losetup", "--detach", read_only_loop], stdout=None)

    replace_state(journal / "STATE", "VERIFIED")
    append_event(journal, "installed-verification-passed")
    print("Held installed-system verification passed.")
    print(f"Plan ID: {plan['plan_id']}")


def remove(args: argparse.Namespace) -> None:
    journal, plan, device, expected_created, _parent, _target_kind = (
        journal_context(
        args.journal,
        args.test_marker,
        allowed_states={"PARTITIONED", "VERIFIED"},
        )
    )
    if plan["mode"] != "dual-boot":
        refuse("held removal supports dual-boot transactions only")
    serial = str(plan["disk"]["serial"])
    if args.confirm != f"REMOVE {serial}":
        refuse("typed removal confirmation does not exactly match")
    if plan["executor_status"] == LOOP_EXECUTOR_STATUS:
        expected_second = SECOND_CONFIRMATION
    elif plan["executor_status"] == USB_EXECUTOR_STATUS:
        expected_second = USB_SECOND_CONFIRMATION
    elif plan["mode"] == "dual-boot":
        expected_second = LIVE_DUAL_SECOND_CONFIRMATION
    else:
        expected_second = LIVE_WIPE_SECOND_CONFIRMATION
    if args.second_confirm != expected_second:
        refuse("second disposable confirmation does not exactly match")

    live_before = live_inventory(device)
    assert_unmounted(live_before)
    records = live_partition_records(live_before)
    assert_created_unchanged(expected_created, records)
    validate_preserved_after(plan, records)

    append_event(journal, "removal-started")
    replace_state(journal / "STATE", "REMOVING")
    try:
        for item in sorted(
            expected_created, key=lambda value: value["number"], reverse=True
        ):
            run(
                ["sfdisk", "--delete", device, str(item["number"])],
                stdout=None,
            )
        run(["sfdisk", "--verify", device], stdout=None)
        settle(device)
        live_after = live_inventory(device)
        assert_unmounted(live_after)
        records_after = live_partition_records(live_after)
        actual_preserved = [
            preserved_projection(record) for record in records_after
        ]
        if canonical_bytes(actual_preserved) != canonical_bytes(
            plan["preserved_partitions"]
        ):
            refuse("preserved partition identity changed during removal")
        write_json(journal / "live-after-removal.json", live_after)
        replace_state(journal / "STATE", "REMOVED")
        append_event(journal, "removed")
    except BaseException as error:
        replace_state(journal / "STATE", "REMOVAL-FAILED")
        append_event(journal, "removal-failed", error=repr(error))
        raise

    print("Held dual-boot removal passed.")
    print(f"Plan ID: {plan['plan_id']}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Held mutation executor. It accepts only qualified disposable "
            "tests or an identity-bound internal target from the SP11 live image."
        )
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    apply_parser = subparsers.add_parser("apply")
    apply_parser.add_argument("--plan", type=Path, required=True)
    apply_parser.add_argument("--inventory-json", type=Path)
    apply_parser.add_argument("--test-marker", type=Path, required=True)
    apply_parser.add_argument("--journal", type=Path, required=True)
    apply_parser.add_argument("--confirm", required=True)
    apply_parser.add_argument("--second-confirm", required=True)

    populate_parser = subparsers.add_parser("populate")
    populate_parser.add_argument("--journal", type=Path, required=True)
    populate_parser.add_argument("--test-marker", type=Path, required=True)
    populate_parser.add_argument("--artifact", type=Path, required=True)
    populate_parser.add_argument(
        "--owner-firmware-root", type=Path, required=True
    )
    populate_parser.add_argument("--username", required=True)
    populate_parser.add_argument(
        "--password-hash-file", type=Path, required=True
    )
    populate_parser.add_argument("--timezone", default="UTC")
    populate_parser.add_argument(
        "--allow-missing-owner-firmware",
        action="store_true",
        help="install even when no owner firmware was imported (no audio/GPU "
        "acceleration until 'sp11-firmware install' is run later)",
    )

    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("--journal", type=Path, required=True)
    verify_parser.add_argument("--test-marker", type=Path, required=True)

    remove_parser = subparsers.add_parser("remove")
    remove_parser.add_argument("--journal", type=Path, required=True)
    remove_parser.add_argument("--test-marker", type=Path, required=True)
    remove_parser.add_argument("--confirm", required=True)
    remove_parser.add_argument("--second-confirm", required=True)
    return parser.parse_args()


def main() -> int:
    if os.geteuid() != 0:
        refuse("run with sudo/root")
    for command in (
        "blkid",
        "blockdev",
        "chroot",
        "cmp",
        "losetup",
        "lsblk",
        "lsinitcpio",
        "mkfs.ext4",
        "mkfs.fat",
        "mount",
        "mountpoint",
        "partprobe",
        "sfdisk",
        "sync",
        "systemd-machine-id-setup",
        "tar",
        "udevadm",
        "umount",
        "zstd",
    ):
        if shutil.which(command) is None:
            refuse(f"missing required command: {command}")

    script_dir = Path(__file__).resolve().parent
    planner = script_dir / "sp11-install-plan.py"
    if not planner.is_file() or not os.access(planner, os.X_OK):
        refuse("read-only planner is missing")

    lock_path = Path("/run/lock/sp11-install-executor-held.lock")
    with lock_path.open("w", encoding="utf-8") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            refuse("another held executor is running")
        args = parse_args()
        if args.command == "apply":
            apply(args, planner)
        elif args.command == "populate":
            populate(args, script_dir)
        elif args.command == "verify":
            verify_installed(args, script_dir)
        else:
            remove(args)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        ExecutorRefusal,
        OSError,
        subprocess.CalledProcessError,
        json.JSONDecodeError,
    ) as error:
        print(f"REFUSED: {error}", file=sys.stderr)
        raise SystemExit(1) from None
