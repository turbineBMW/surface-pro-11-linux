#!/usr/bin/env python3

"""Interactive SP11 live installer with an unprivileged planning phase."""

from __future__ import annotations

import argparse
import getpass
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


class UiError(RuntimeError):
    """A user-facing planning refusal."""


COMMON_TIMEZONES = (
    "UTC",
    "America/New_York",
    "America/Chicago",
    "America/Denver",
    "America/Los_Angeles",
    "America/Anchorage",
    "Pacific/Honolulu",
    "America/Toronto",
    "America/Vancouver",
    "Europe/London",
    "Europe/Berlin",
    "Asia/Tokyo",
    "Australia/Sydney",
)


LIVE_EXECUTOR_STATUS = "held-live-internal-only"
LIVE_DUAL_SECOND_CONFIRMATION = (
    "I UNDERSTAND THIS MODIFIES THE INTERNAL DISK AND REQUIRES A BACKUP"
)
LIVE_WIPE_SECOND_CONFIRMATION = (
    "I UNDERSTAND THIS ERASES WINDOWS RECOVERY AND ALL DATA"
)


def run_planner(
    planner: Path,
    arguments: list[str],
) -> dict[str, Any]:
    result = subprocess.run(
        [os.fspath(planner), *arguments],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        message = result.stderr.strip()
        if message.startswith("REFUSED: "):
            message = message.removeprefix("REFUSED: ")
        raise UiError(message or "the read-only planner refused this request")
    value = json.loads(result.stdout)
    if not isinstance(value, dict):
        raise UiError("the planner returned malformed output")
    return value


def choose(prompt: str, upper: int) -> int:
    while True:
        response = input(prompt).strip()
        if response.isdigit() and 1 <= int(response) <= upper:
            return int(response)
        print(f"Please enter a number from 1 through {upper}.")


def size_text(size: Any) -> str:
    if not isinstance(size, int) or isinstance(size, bool):
        return "unknown size"
    return f"{size / (1024**3):.1f} GiB"


def print_inventory(disks: list[dict[str, Any]]) -> None:
    print("\nDetected whole disks:")
    for index, disk in enumerate(disks, start=1):
        flags = []
        if disk.get("removable"):
            flags.append("removable")
        if disk.get("hotplug"):
            flags.append("hot-plug")
        if disk.get("read_only"):
            flags.append("read-only")
        if str(disk.get("transport", "")).lower() == "usb":
            flags.append("USB")
        if disk.get("mountpoints"):
            flags.append("mounted")
        suffix = f" — REFUSED: {', '.join(flags)}" if flags else ""
        print(
            f"  {index}. {disk.get('path')} — "
            f"{disk.get('model') or 'unknown model'} — "
            f"{size_text(disk.get('size_bytes'))} — "
            f"serial {disk.get('serial') or '(missing)'}{suffix}"
        )
        partitions = disk.get("partitions")
        if not isinstance(partitions, list) or not partitions:
            print("       no existing partitions")
            continue
        for partition in partitions:
            filesystem = partition.get("fstype") or "unknown filesystem"
            label = partition.get("label") or "no label"
            mounted = partition.get("mountpoints")
            mount_text = ""
            if isinstance(mounted, list) and mounted:
                mount_text = f" — mounted at {', '.join(map(str, mounted))}"
            print(
                f"       {partition.get('path')} — "
                f"{size_text(partition.get('size_bytes'))} — "
                f"{filesystem} — {label}{mount_text}"
            )


def print_plan(plan: dict[str, Any]) -> None:
    disk = plan["disk"]
    print("\nImmutable plan preview")
    print(f"  Plan ID: {plan['plan_id']}")
    print(f"  Mode: {plan['mode']}")
    print(
        f"  Disk: {disk['path']} — {disk['model']} — "
        f"{size_text(disk['size_bytes'])} — serial {disk['serial']}"
    )
    print("  Proposed partitions:")
    for partition in plan["proposed_partitions"]:
        print(
            f"    - {partition['role']}: GPT #{partition['number']}, "
            f"start {partition['start_bytes']} bytes, "
            f"{size_text(partition['size_bytes'])}, "
            f"{partition['filesystem']} label "
            f"{partition['filesystem_label']}"
        )
    reclaimed = plan.get("reclaimed_partitions", [])
    if reclaimed:
        print("  Existing partition to erase and reclaim:")
        for partition in reclaimed:
            print(
                f"    - {partition['path']}: GPT #{partition['number']}, "
                f"{size_text(partition['size_bytes'])}, "
                f"{partition.get('fstype') or 'unknown filesystem'}"
            )
    print("  Warnings:")
    for warning in plan["warnings"]:
        print(f"    - {warning}")
    print(
        "  Future execution confirmation: "
        f"{plan['confirmation']['required_text']}"
    )


def output_path(argument: Path | None) -> Path:
    if argument is not None:
        candidate = argument.expanduser().resolve()
    else:
        candidate = (Path.home() / "Downloads/sp11-install-plan.json").resolve()
    if candidate.exists() or candidate.is_symlink():
        raise UiError(f"refusing to replace existing plan: {candidate}")
    if not candidate.parent.is_dir():
        raise UiError(f"plan output directory does not exist: {candidate.parent}")
    return candidate


def default_tool(installed: str, repository_name: str) -> Path:
    installed_path = Path(installed)
    if installed_path.is_file():
        return installed_path
    return Path(__file__).with_name(repository_name)


def select_timezone() -> str:
    print("\nTimezone (region names automatically handle daylight saving time)")
    for number, timezone in enumerate(COMMON_TIMEZONES, start=1):
        print(f"  {number:2}. {timezone}")
    answer = input(
        "Choose a number or enter another Region/City name [1]: "
    ).strip()
    if not answer:
        return "UTC"
    if answer.isdigit():
        number = int(answer)
        if 1 <= number <= len(COMMON_TIMEZONES):
            return COMMON_TIMEZONES[number - 1]
        raise UiError("timezone choice is outside the displayed list")
    if (
        answer.startswith("/")
        or ".." in Path(answer).parts
        or "/" not in answer
        or not re.fullmatch(r"[A-Za-z0-9_+.-]+(?:/[A-Za-z0-9_+.-]+)+", answer)
    ):
        raise UiError("use a region-based timezone such as America/New_York")
    zone = Path("/usr/share/zoneinfo") / answer
    if zone.is_symlink() or not zone.is_file():
        raise UiError(f"timezone is not available: {answer}")
    return answer


def prompt_account() -> tuple[str, str, str]:
    print("\nInstalled user account")
    while True:
        username = input("Username: ").strip()
        if re.fullmatch(r"[a-z_][a-z0-9_-]{0,30}", username) and username not in {
            "root",
            "gdm",
            "nobody",
            "alpm",
        }:
            break
        print("Use 1–31 lowercase letters, digits, underscores, or hyphens.")
    password = getpass.getpass("Password (minimum 8 characters): ")
    if len(password) < 8 or "\n" in password or "\0" in password:
        raise UiError("password does not satisfy the installer policy")
    if getpass.getpass("Confirm password: ") != password:
        raise UiError("passwords did not match")
    timezone = select_timezone()
    return username, password, timezone


def password_hash(password: str) -> str:
    openssl = shutil.which("openssl")
    if openssl is None:
        raise UiError("openssl is unavailable for password hashing")
    result = subprocess.run(
        [openssl, "passwd", "-6", "-stdin"],
        input=password + "\n",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    value = result.stdout.strip()
    if result.returncode != 0 or not value.startswith("$6$"):
        raise UiError(result.stderr.strip() or "password hashing failed")
    return value


def run_executor(executor: Path, arguments: list[str]) -> None:
    result = subprocess.run(
        ["sudo", "--", os.fspath(executor), *arguments],
        check=False,
    )
    if result.returncode != 0:
        raise UiError(f"privileged installer stopped with status {result.returncode}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--planner",
        type=Path,
        default=default_tool(
            "/usr/local/libexec/sp11-fresh-installer/scripts/sp11-install-plan.py",
            "sp11-install-plan.py",
        ),
    )
    parser.add_argument(
        "--inventory-json",
        type=Path,
        help="test/offline inventory passed through to the read-only planner",
    )
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--executor",
        type=Path,
        default=default_tool(
            "/usr/local/libexec/sp11-fresh-installer/scripts/sp11-install-executor.py",
            "sp11-install-executor.py",
        ),
    )
    parser.add_argument(
        "--artifact",
        type=Path,
        default=Path("/opt/sp11-fresh-installer/artifact"),
    )
    parser.add_argument(
        "--owner-firmware-root",
        type=Path,
        default=Path("/usr/lib/firmware"),
    )
    parser.add_argument(
        "--live-proof",
        type=Path,
        default=Path("/etc/sp11-live-release"),
    )
    parser.add_argument(
        "--no-final-prompt",
        action="store_true",
        help="do not wait for Enter after saving (test automation)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    planner_candidate = args.planner.expanduser()
    if planner_candidate.is_symlink():
        raise UiError(f"read-only planner is unavailable: {planner_candidate}")
    planner = planner_candidate.resolve(strict=True)
    if not planner.is_file() or not os.access(
        planner, os.X_OK
    ):
        raise UiError(f"read-only planner is unavailable: {planner}")

    inventory_arguments = ["--mode", "inventory"]
    if args.inventory_json:
        inventory_arguments.extend(
            ("--inventory-json", os.fspath(args.inventory_json))
        )
    inventory = run_planner(planner, inventory_arguments)
    disks = inventory.get("disks")
    if not isinstance(disks, list) or not disks:
        raise UiError("no whole disks were detected")

    preview_only = args.inventory_json is not None
    print(
        "SP11 Linux installer — planning preview"
        if preview_only
        else "SP11 Linux installer"
    )
    print("=" * 43)
    if preview_only:
        print("\nFixture preview mode cannot install or modify a disk.")
    else:
        print(
            "\nPlanning is read-only. Disk changes begin only after two exact "
            "confirmations and privileged live/hardware revalidation."
        )
        print(
            "Secure Boot must be disabled for this beta image. Microsoft UEFI "
            "keys are not changed or enrolled by the installer."
        )
    print(
        "\nFor dual boot, first shrink Windows from Windows Disk Management "
        "and leave at least 33 GiB unallocated. Do not create or format a "
        "partition in that space."
    )
    print_inventory(disks)
    selected = disks[choose("\nSelect the exact target disk: ", len(disks)) - 1]

    print("\nInstallation mode:")
    print("  1. Dual boot with Windows (recommended)")
    print("  2. Wipe the selected disk and install Linux")
    mode = "dual-boot" if choose("Select a mode: ", 2) == 1 else "wipe"
    if mode == "wipe":
        print(
            "\nWARNING: wipe mode destroys Windows, Surface recovery "
            "partitions, and all data on the selected disk."
        )

    plan_arguments = [
        "--mode",
        mode,
        "--disk",
        str(selected["path"]),
    ]
    if args.inventory_json:
        plan_arguments.extend(
            ("--inventory-json", os.fspath(args.inventory_json))
        )
    plan = run_planner(planner, plan_arguments)
    print_plan(plan)

    if preview_only:
        if input("\nType SAVE to write this non-executable plan: ").strip() != "SAVE":
            raise UiError("plan was not saved")
        destination = output_path(args.output)
        rendered = json.dumps(plan, indent=2, sort_keys=True) + "\n"
        with destination.open("x", encoding="utf-8", newline="\n") as output:
            output.write(rendered)
        print(f"\nSaved read-only plan preview: {destination}")
        print("No disk, partition, filesystem, boot entry, or EFI variable changed.")
        print("Physical installation is not enabled in fixture preview mode.")
    else:
        if (
            plan.get("execution_eligible") is not True
            or plan.get("executor_status") != LIVE_EXECUTOR_STATUS
        ):
            raise UiError("planner did not authorize a live internal-disk plan")
        required = str(plan["confirmation"]["required_text"])
        if input(f"\nType {required} exactly: ").strip() != required:
            raise UiError("disk confirmation did not match")
        second = (
            LIVE_DUAL_SECOND_CONFIRMATION
            if mode == "dual-boot"
            else LIVE_WIPE_SECOND_CONFIRMATION
        )
        print(f"\nFinal confirmation phrase:\n{second}")
        if input("Type the complete phrase: ").strip() != second:
            raise UiError("final destructive confirmation did not match")
        firmware_arguments: list[str] = []
        if not Path("/etc/sp11-external-firmware").is_file():
            print(
                "\nNo owner firmware has been imported in this live session, so "
                "the installed system would start without audio, microphones, "
                "or GPU acceleration."
            )
            print(
                "Recommended: quit now, run RUN-IN-WINDOWS.cmd from Windows (or "
                "'sudo sp11-firmware collect --to-usb' here), boot the USB again, "
                "and install then."
            )
            print(
                "You can also add the firmware later on the installed system with "
                "'sudo sp11-firmware install --from-windows' (dual boot) or from a pack."
            )
            answer = input(
                "Type INSTALL WITHOUT FIRMWARE to continue anyway, or press Enter to quit: "
            ).strip()
            if answer != "INSTALL WITHOUT FIRMWARE":
                raise UiError("installation cancelled; collect the firmware first")
            firmware_arguments = ["--allow-missing-owner-firmware"]
        username, password, timezone = prompt_account()
        executor = args.executor.resolve(strict=True)
        if executor.is_symlink() or not os.access(executor, os.X_OK):
            raise UiError("privileged executor is unavailable")
        with tempfile.TemporaryDirectory(
            prefix="sp11-installer-ui.", dir="/tmp"
        ) as temporary:
            private = Path(temporary)
            private.chmod(0o700)
            plan_path = private / "plan.json"
            plan_path.write_text(
                json.dumps(plan, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            hash_path = private / "password.hash"
            hash_path.write_text(password_hash(password) + "\n", encoding="utf-8")
            hash_path.chmod(0o600)
            password = ""
            journal_name = f"transaction-{plan['plan_id'][:16]}"
            journal = Path("/run/sp11-installer") / journal_name
            print("\nPartitioning and formatting the identity-bound target …")
            run_executor(
                executor,
                [
                    "apply",
                    "--plan",
                    os.fspath(plan_path),
                    "--test-marker",
                    os.fspath(args.live_proof),
                    "--journal",
                    journal_name,
                    "--confirm",
                    required,
                    "--second-confirm",
                    second,
                ],
            )
            print("\nInstalling the verified system and owner firmware …")
            run_executor(
                executor,
                [
                    "populate",
                    "--journal",
                    os.fspath(journal),
                    "--test-marker",
                    os.fspath(args.live_proof),
                    "--artifact",
                    os.fspath(args.artifact),
                    "--owner-firmware-root",
                    os.fspath(args.owner_firmware_root),
                    "--username",
                    username,
                    "--password-hash-file",
                    os.fspath(hash_path),
                    "--timezone",
                    timezone,
                    *firmware_arguments,
                ],
            )
            for pass_number in (1, 2):
                print(f"\nIndependent installed-system verification {pass_number}/2 …")
                run_executor(
                    executor,
                    [
                        "verify",
                        "--journal",
                        os.fspath(journal),
                        "--test-marker",
                        os.fspath(args.live_proof),
                    ],
                )
        print("\nInstallation and both verification passes completed successfully.")
        print("Shut down, remove the live USB, and boot SP11 Linux.")
    if not args.no_final_prompt:
        input("\nPress Enter to close.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        UiError,
        OSError,
        subprocess.SubprocessError,
        json.JSONDecodeError,
        EOFError,
        KeyboardInterrupt,
    ) as error:
        print(f"\nStopped: {error}", file=sys.stderr)
        raise SystemExit(1) from None
