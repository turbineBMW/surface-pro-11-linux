#!/bin/bash

# Capture the boot/storage state needed to prove a reversible SP11 install.

set -euo pipefail

output=""

usage() {
	printf 'Usage: sudo %s --output NEW_REPORT_FILE\n' "$0"
}

while (($#)); do
	case "$1" in
	--output) output="$2"; shift 2 ;;
	-h|--help) usage; exit 0 ;;
	*) usage >&2; exit 2 ;;
	esac
done

[[ $EUID -eq 0 ]] || { printf 'Run with sudo/root.\n' >&2; exit 1; }
[[ -n "$output" ]] || { usage >&2; exit 2; }
output="$(realpath -m -- "$output")"
[[ ! -e "$output" && -d "$(dirname -- "$output")" ]] || {
	printf 'Output must be a new file in an existing directory: %s\n' \
		"$output" >&2
	exit 1
}

exec > >(tee "$output") 2>&1

printf '=== identity ===\n'
date --iso-8601=ns
uname -a
printf 'DMI: '
cat /sys/class/dmi/id/product_name
printf 'Compatible:\n'
tr '\0' '\n' </proc/device-tree/compatible

printf '\n=== mounts ===\n'
findmnt -R -o SOURCE,TARGET,FSTYPE,OPTIONS,UUID,PARTUUID /
findmnt -T /efi -o SOURCE,TARGET,FSTYPE,OPTIONS,UUID,PARTUUID

printf '\n=== block layout ===\n'
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,UUID,PARTUUID,MOUNTPOINTS,MODEL,SERIAL,TRAN

printf '\n=== EFI entries ===\n'
efibootmgr -v

printf '\n=== Windows Boot Manager ===\n'
windows_loader="/efi/EFI/Microsoft/Boot/bootmgfw.efi"
stat -c '%F %a %U:%G %s %n' "$windows_loader"
sha256sum "$windows_loader"

printf '\n=== GRUB environment ===\n'
grub-editenv /boot/grub/grubenv list

printf '\n=== GRUB identities ===\n'
sha256sum /boot/grub/grub.cfg /boot/grub/grubenv
find /etc/grub.d -maxdepth 1 -type f -print0 |
	LC_ALL=C sort -z |
	xargs -0 sha256sum

printf '\n=== SP11 boot payloads ===\n'
find /boot -maxdepth 2 -type f \
	\( -name 'Image-*' -o -name 'initramfs-*' -o -name '*.dtb' \) \
	-printf '%p\t%s\n' |
	LC_ALL=C sort

printf '\n=== kernel module trees ===\n'
find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' |
	LC_ALL=C sort

printf '\n=== existing installer state ===\n'
for path in \
	/boot/sp11-beta \
	/etc/grub.d/09_sp11_beta \
	/var/lib/sp11-beta; do
	if [[ -e "$path" || -L "$path" ]]; then
		stat -c '%F %a %U:%G %n' "$path"
	else
		printf 'ABSENT %s\n' "$path"
	fi
done

printf '\n=== completion ===\n'
printf 'Baseline saved to: %s\n' "$output"
