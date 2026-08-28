#!/bin/bash

# Exercise the read-only planner against a real disposable GPT/loop device.
# No non-loop block device is accepted or written.

set -euo pipefail

[[ $EUID -eq 0 ]] || {
	printf 'Run with sudo/root.\n' >&2
	exit 1
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
planner="$script_dir/sp11-install-plan.py"
required_commands=(flock jq losetup lsblk mktemp sfdisk truncate)
for required_command in "${required_commands[@]}"; do
	command -v "$required_command" >/dev/null || {
		printf 'Missing required command: %s\n' "$required_command" >&2
		exit 1
	}
done
[[ -x "$planner" ]] || {
	printf 'Missing planner: %s\n' "$planner" >&2
	exit 1
}

exec 9>/run/lock/sp11-install-plan-loopback.lock
flock -n 9 || {
	printf 'Another loopback planner test is running.\n' >&2
	exit 1
}

temporary="$(mktemp -d /tmp/sp11-install-plan-loopback.XXXXXX)"
disk_image="$temporary/windows-shrunk.img"
loop_device=""
cleanup() {
	if [[ -n "$loop_device" ]]; then
		[[ "$(lsblk -dnro TYPE "$loop_device" 2>/dev/null || true)" == "loop" ]] ||
			{
				printf 'Refusing cleanup of non-loop device: %s\n' \
					"$loop_device" >&2
				return
			}
		losetup -d "$loop_device"
	fi
	[[ "$temporary" == /tmp/sp11-install-plan-loopback.* ]] &&
		find "$temporary" -depth -delete
}
trap cleanup EXIT

# Sparse allocation: this describes a 45 GiB disk but consumes only GPT blocks.
truncate -s 45G "$disk_image"
sfdisk "$disk_image" >/dev/null <<'EOF'
label: gpt
unit: sectors

start=2048, size=532480, type=c12a7328-f81f-11d2-ba4b-00a0c93ec93b, name="SYSTEM"
start=534528, size=32768, type=e3c9e316-0b5c-4db8-817d-f92df00215ae, name="Microsoft reserved"
start=567296, size=10485760, type=ebd0a0a2-b9e5-4433-87c0-68b6b72699c7, name="Windows"
start=82356224, size=4194304, type=de94bba4-06d1-4d40-a16a-bfd50179d6ac, name="Windows RE tools"
EOF

loop_device="$(losetup --find --show --partscan "$disk_image")"
[[ "$loop_device" == /dev/loop* &&
	"$(lsblk -dnro TYPE "$loop_device")" == "loop" ]] || {
	printf 'Unexpected loop-device identity: %s\n' "$loop_device" >&2
	exit 1
}
udevadm settle

fields='NAME,PATH,TYPE,SIZE,START,LOG-SEC,PHY-SEC,MIN-IO,OPT-IO,ALIGNMENT,RO,RM,HOTPLUG,TRAN,MODEL,SERIAL,PTTYPE,PTUUID,FSTYPE,FSVER,LABEL,UUID,PARTTYPE,PARTTYPENAME,PARTUUID,PARTLABEL,PARTN,PKNAME,MOUNTPOINTS'
lsblk --json --bytes -o "$fields" "$loop_device" |
	jq '
		.blockdevices[0].serial = "SP11-LOOPBACK-TEST" |
		.blockdevices[0].model = "Disposable SP11 planner test" |
		.blockdevices[0].tran = "nvme" |
		.blockdevices[0].type = "disk"
	' >"$temporary/lsblk.json"

"$planner" \
	--inventory-json "$temporary/lsblk.json" \
	--mode dual-boot \
	--disk "$loop_device" \
	--output "$temporary/dual-boot-plan.json"

jq -e '
	.schema == "sp11.install-plan.v1" and
	.mode == "dual-boot" and
	.execution_eligible == false and
	.executor_status == "held-disposable-loop-only" and
	(.preserved_partitions | length) == 4 and
	(.proposed_partitions | length) == 2 and
	.proposed_partitions[0].role == "linux-esp" and
	.proposed_partitions[0].start_bytes == 5659164672 and
	.proposed_partitions[0].size_bytes == 1073741824 and
	.proposed_partitions[1].role == "linux-root" and
	.proposed_partitions[1].start_bytes == 6732906496 and
	.proposed_partitions[1].size_bytes == 35433480192 and
	.confirmation.required_text == "INSTALL SP11-LOOPBACK-TEST"
' "$temporary/dual-boot-plan.json" >/dev/null

"$planner" \
	--inventory-json "$temporary/lsblk.json" \
	--mode wipe \
	--disk "$loop_device" \
	--output "$temporary/wipe-plan.json"
jq -e '
	.mode == "wipe" and
	.execution_eligible == false and
	(.preserved_partitions | length) == 0 and
	.confirmation.required_text == "ERASE SP11-LOOPBACK-TEST" and
	.confirmation.second_confirmation_required == true
' "$temporary/wipe-plan.json" >/dev/null

printf 'Disposable GPT loopback planner tests passed: %s\n' "$loop_device"
