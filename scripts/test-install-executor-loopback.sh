#!/bin/bash

# Exercise held partition apply/removal semantics on one marked sparse loop
# image. Every mutation target is revalidated as a loop device first.

set -euo pipefail

report=""
artifact=""
while (($#)); do
	case "$1" in
	--artifact)
		artifact="$2"
		shift 2
		;;
	--report)
		report="$2"
		shift 2
		;;
	-h|--help)
		printf 'Usage: sudo %s [--artifact DIRECTORY] [--report NEW_FILE]\n' "$0"
		exit 0
		;;
	*)
		printf 'Usage: sudo %s [--artifact DIRECTORY] [--report NEW_FILE]\n' "$0" >&2
		exit 2
		;;
	esac
done

[[ $EUID -eq 0 ]] || {
	printf 'Run with sudo/root.\n' >&2
	exit 1
}
if [[ -n "$report" ]]; then
	report="$(realpath -m -- "$report")"
	[[ ! -e "$report" && ! -L "$report" &&
		-d "$(dirname -- "$report")" ]] || {
		printf 'Report must be a new file in an existing directory.\n' >&2
		exit 1
	}
	exec > >(tee "$report") 2>&1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
if [[ -z "$artifact" ]]; then
	artifact="$repo_root/work/installed-rootfs-review20-held-deterministic1-20260730"
fi
artifact="$(realpath -e -- "$artifact")"
planner="$script_dir/sp11-install-plan.py"
executor="$script_dir/sp11-install-executor.py"
for command in \
	cmp flock jq losetup lsblk mkfs.fat mktemp mount mountpoint realpath \
	sfdisk sha256sum tee truncate udevadm umount; do
	command -v "$command" >/dev/null || {
		printf 'Missing required command: %s\n' "$command" >&2
		exit 1
	}
done

exec 9>/run/lock/sp11-install-executor-integration.lock
flock -n 9 || {
	printf 'Another loopback executor integration test is running.\n' >&2
	exit 1
}

temporary="$(mktemp -d /tmp/sp11-install-executor-loopback.XXXXXX)"
disk_image="$temporary/windows-shrunk.img"
marker="$temporary/DISPOSABLE-MARKER"
loop_device=""
test_mount=""
cleanup() {
	if [[ -n "$test_mount" ]] && mountpoint -q "$test_mount"; then
		umount "$test_mount"
	fi
	if [[ -n "$loop_device" ]]; then
		[[ "$loop_device" == /dev/loop* &&
			"$(lsblk -dnro TYPE "$loop_device" 2>/dev/null || true)" == \
				"loop" ]] || {
			printf 'Refusing cleanup of non-loop device: %s\n' \
				"$loop_device" >&2
			return
		}
		losetup -d "$loop_device"
	fi
	[[ "$temporary" == /tmp/sp11-install-executor-loopback.* ]] &&
		find "$temporary" -depth -delete
}
trap cleanup EXIT

printf 'SP11 DISPOSABLE INSTALL EXECUTOR LOOP TEST\n' >"$marker"
# shellcheck disable=SC2016 # The literal crypt hash must not expand.
printf '%s\n' \
	'$6$sp11test$zLTk7vrWIjQwvjIpSbbhJ.QZ3UoWsu6PkUBn.555.gP1egwM5Ux4481d2hHrLfJU2MBLoOFAfu/cMo7SVhx1F.' \
	>"$temporary/password.hash"
truncate -s 45G "$disk_image"
sfdisk "$disk_image" >/dev/null <<'EOF'
label: gpt
unit: sectors

start=2048, size=532480, type=c12a7328-f81f-11d2-ba4b-00a0c93ec93b, name="SYSTEM"
start=534528, size=32768, type=e3c9e316-0b5c-4db8-817d-f92df00215ae, name="Microsoft reserved"
start=567296, size=10485760, type=ebd0a0a2-b9e5-4433-87c0-68b6b72699c7, name="Windows"
start=11053056, size=2097152, type=c12a7328-f81f-11d2-ba4b-00a0c93ec93b, name="SP11 Linux EFI"
start=13150208, size=81219584, type=0fc63daf-8483-4772-8e79-3d69d8477de4, name="SP11 Linux Root"
EOF

loop_device="$(losetup --find --show --partscan "$disk_image")"
[[ "$loop_device" == /dev/loop* &&
	"$(lsblk -dnro TYPE "$loop_device")" == "loop" ]] || {
	printf 'Unexpected loop-device identity: %s\n' "$loop_device" >&2
	exit 1
}
udevadm settle

test_mount="$temporary/windows-esp"
mkdir "$test_mount"
mkfs.fat -F 32 -n SYSTEM "${loop_device}p1" >/dev/null
mkfs.fat -F 32 -n SP11EFI "${loop_device}p4" >/dev/null
mkfs.ext4 -F -L sp11root "${loop_device}p5" >/dev/null
mount "${loop_device}p1" "$test_mount"
mkdir -p "$test_mount/EFI/Microsoft/Boot"
printf 'synthetic disposable Windows boot manager\n' \
	>"$test_mount/EFI/Microsoft/Boot/bootmgfw.efi"
windows_loader_sha="$(
	sha256sum "$test_mount/EFI/Microsoft/Boot/bootmgfw.efi" |
		awk '{print $1}'
)"
umount "$test_mount"

planner_fields='NAME,PATH,TYPE,SIZE,START,LOG-SEC,PHY-SEC,MIN-IO,OPT-IO,ALIGNMENT,RO,RM,HOTPLUG,TRAN,MODEL,SERIAL,PTTYPE,PTUUID,FSTYPE,FSVER,LABEL,UUID,PARTTYPE,PARTTYPENAME,PARTUUID,PARTLABEL,PARTN,PKNAME,MOUNTPOINTS'
write_fixture() {
	local output="$1"
	lsblk --json --bytes -o "$planner_fields" "$loop_device" |
		jq '
			.blockdevices[0].serial = "SP11-DISPOSABLE-LOOP-TEST" |
			.blockdevices[0].model = "Disposable SP11 executor test" |
			.blockdevices[0].tran = "nvme" |
			.blockdevices[0].type = "disk"
		' >"$output"
}

write_fixture "$temporary/windows-layout.json"
sfdisk --dump "$loop_device" >"$temporary/sfdisk-original.txt"

"$planner" \
	--inventory-json "$temporary/windows-layout.json" \
	--mode dual-boot \
	--disk "$loop_device" \
	--output "$temporary/dual-plan.json"
jq -e '
	[.reclaimed_partitions[].number] == [4, 5] and
	[.preserved_partitions[].number] == [1, 2, 3] and
	[.proposed_partitions[].number] == [4, 5]
' "$temporary/dual-plan.json" >/dev/null

if "$executor" apply \
	--plan "$temporary/dual-plan.json" \
	--inventory-json "$temporary/windows-layout.json" \
	--test-marker "$marker" \
	--journal wrong-confirmation-journal \
	--confirm 'INSTALL WRONG-SERIAL' \
	--second-confirm 'I UNDERSTAND THIS IS A DISPOSABLE LOOP TEST'; then
	printf 'Executor accepted a wrong disk confirmation.\n' >&2
	exit 1
fi
sfdisk --dump "$loop_device" >"$temporary/sfdisk-after-refusal.txt"
cmp "$temporary/sfdisk-original.txt" "$temporary/sfdisk-after-refusal.txt"
[[ ! -e "$temporary/wrong-confirmation-journal" ]]

"$executor" apply \
	--plan "$temporary/dual-plan.json" \
	--inventory-json "$temporary/windows-layout.json" \
	--test-marker "$marker" \
	--journal dual-transaction \
	--confirm 'INSTALL SP11-DISPOSABLE-LOOP-TEST' \
	--second-confirm 'I UNDERSTAND THIS IS A DISPOSABLE LOOP TEST'

[[ "$(<"$temporary/dual-transaction/STATE")" == "PARTITIONED" ]]
jq -e '
	.mode == "dual-boot" and
	.initial_status == "PREPARED"
' "$temporary/dual-transaction/transaction.json" >/dev/null
[[ "$(
	lsblk -nrpo TYPE,FSTYPE,LABEL "$loop_device" |
		awk '$1 == "part" && $2 == "vfat" && $3 == "SP11EFI" { count++ }
			END { print count + 0 }'
)" -eq 1 ]]
[[ "$(
	lsblk -nrpo TYPE,FSTYPE,LABEL "$loop_device" |
		awk '$1 == "part" && $2 == "ext4" && $3 == "sp11root" { count++ }
			END { print count + 0 }'
)" -eq 1 ]]

root_number="$(jq -r '
	.proposed_partitions[] |
	select(.role == "linux-root") |
	.number
' "$temporary/dual-plan.json")"
test_mount="$temporary/mounted-root"
mkdir "$test_mount"
mount "${loop_device}p${root_number}" "$test_mount"
if "$executor" remove \
	--journal "$temporary/dual-transaction" \
	--test-marker "$marker" \
	--confirm 'REMOVE SP11-DISPOSABLE-LOOP-TEST' \
	--second-confirm 'I UNDERSTAND THIS IS A DISPOSABLE LOOP TEST'; then
	printf 'Removal accepted a mounted installation partition.\n' >&2
	exit 1
fi
[[ "$(<"$temporary/dual-transaction/STATE")" == "PARTITIONED" ]]
umount "$test_mount"

if "$executor" remove \
	--journal "$temporary/dual-transaction" \
	--test-marker "$marker" \
	--confirm 'REMOVE WRONG-SERIAL' \
	--second-confirm 'I UNDERSTAND THIS IS A DISPOSABLE LOOP TEST'; then
	printf 'Removal accepted a wrong disk confirmation.\n' >&2
	exit 1
fi
[[ "$(<"$temporary/dual-transaction/STATE")" == "PARTITIONED" ]]

"$executor" populate \
	--journal "$temporary/dual-transaction" \
	--test-marker "$marker" \
	--artifact \
	"$artifact" \
	--owner-firmware-root /usr/lib/firmware \
	--username sp11test \
	--password-hash-file "$temporary/password.hash" \
	--timezone UTC
[[ "$(<"$temporary/dual-transaction/STATE")" == "INSTALLED-UNVERIFIED" ]]

"$executor" verify \
	--journal "$temporary/dual-transaction" \
	--test-marker "$marker"
[[ "$(<"$temporary/dual-transaction/STATE")" == "VERIFIED" ]]
"$executor" verify \
	--journal "$temporary/dual-transaction" \
	--test-marker "$marker"

"$executor" remove \
	--journal "$temporary/dual-transaction" \
	--test-marker "$marker" \
	--confirm 'REMOVE SP11-DISPOSABLE-LOOP-TEST' \
	--second-confirm 'I UNDERSTAND THIS IS A DISPOSABLE LOOP TEST'
[[ "$(<"$temporary/dual-transaction/STATE")" == "REMOVED" ]]
sfdisk --dump "$loop_device" >"$temporary/sfdisk-after-removal.txt"
[[ "$(lsblk -nrpo TYPE "$loop_device" | awk '$1 == "part" { count++ } END { print count + 0 }')" -eq 3 ]]
for preserved_number in 1 2 3; do
	grep -Fq "${loop_device}p${preserved_number} :" \
		"$temporary/sfdisk-after-removal.txt"
done
mount -o ro "${loop_device}p1" "$test_mount"
[[ "$(
	sha256sum "$test_mount/EFI/Microsoft/Boot/bootmgfw.efi" |
		awk '{print $1}'
)" == "$windows_loader_sha" ]]
umount "$test_mount"

write_fixture "$temporary/windows-layout-after-removal.json"
jq -e '
	[.blockdevices[0].children[].partn] == [1, 2, 3]
' "$temporary/windows-layout-after-removal.json" >/dev/null

"$planner" \
	--inventory-json "$temporary/windows-layout-after-removal.json" \
	--mode wipe \
	--disk "$loop_device" \
	--output "$temporary/wipe-plan.json"
"$executor" apply \
	--plan "$temporary/wipe-plan.json" \
	--inventory-json "$temporary/windows-layout-after-removal.json" \
	--test-marker "$marker" \
	--journal wipe-transaction \
	--confirm 'ERASE SP11-DISPOSABLE-LOOP-TEST' \
	--second-confirm 'I UNDERSTAND THIS IS A DISPOSABLE LOOP TEST'
[[ "$(<"$temporary/wipe-transaction/STATE")" == "PARTITIONED" ]]

if "$executor" remove \
	--journal "$temporary/wipe-transaction" \
	--test-marker "$marker" \
	--confirm 'REMOVE SP11-DISPOSABLE-LOOP-TEST' \
	--second-confirm 'I UNDERSTAND THIS IS A DISPOSABLE LOOP TEST'; then
	printf 'Removal unexpectedly claimed it could restore a wiped disk.\n' >&2
	exit 1
fi
[[ "$(<"$temporary/wipe-transaction/STATE")" == "PARTITIONED" ]]

printf 'PASS held disposable loop executor: dual apply/removal and wipe apply\n'
