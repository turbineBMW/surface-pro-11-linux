#!/bin/bash

# Mount an installed Linux root and ESP read-only, then run install.sh
# preflight from the held live image. No target filesystem write is permitted.

set -euo pipefail

installer_root="${SP11_INSTALLER_ROOT:-/opt/sp11-beta-installer}"
root_device=""
efi_device=""
report=""
reuse_compatible_modules=0

usage() {
	cat <<EOF
Usage: sudo $0 --root-device DEVICE --efi-device DEVICE [options]

Options:
  --reuse-compatible-modules
  --report NEW_REPORT_FILE

Both target filesystems are mounted read-only. This wrapper cannot install.
EOF
}

while (($#)); do
	case "$1" in
	--root-device) root_device="$2"; shift 2 ;;
	--efi-device) efi_device="$2"; shift 2 ;;
	--reuse-compatible-modules) reuse_compatible_modules=1; shift ;;
	--report) report="$2"; shift 2 ;;
	-h|--help) usage; exit 0 ;;
	*) usage >&2; exit 2 ;;
	esac
done

[[ $EUID -eq 0 ]] || { printf 'Run with sudo/root.\n' >&2; exit 1; }
[[ -f /etc/sp11-live-release ]] || {
	printf 'This wrapper may run only from the SP11 held live image.\n' >&2
	exit 1
}
[[ -b "$root_device" && -b "$efi_device" &&
	"$root_device" != "$efi_device" ]] || {
	printf 'Two distinct block-device paths are required.\n' >&2
	exit 2
}
[[ -x "$installer_root/scripts/install.sh" &&
	-d "$installer_root/payload" &&
	-d "$installer_root/rootfs" ]] || {
	printf 'Installer kit is incomplete: %s\n' "$installer_root" >&2
	exit 1
}
if findmnt -rn -S "$root_device" -o TARGET | grep -q . ||
	findmnt -rn -S "$efi_device" -o TARGET | grep -q .; then
	printf 'Refusing already-mounted target device. Unmount it first.\n' >&2
	exit 1
fi
[[ "$(lsblk -dnro FSTYPE "$root_device")" == "ext4" ]] || {
	printf 'Root device is not ext4: %s\n' "$root_device" >&2
	exit 1
}
[[ "$(lsblk -dnro FSTYPE "$efi_device")" == "vfat" ]] || {
	printf 'EFI device is not vfat: %s\n' "$efi_device" >&2
	exit 1
}
root_parent="$(lsblk -dnro PKNAME "$root_device")"
efi_parent="$(lsblk -dnro PKNAME "$efi_device")"
[[ -n "$root_parent" && "$root_parent" == "$efi_parent" ]] || {
	printf 'Root and EFI devices are not partitions of the same disk.\n' >&2
	exit 1
}

if [[ -n "$report" ]]; then
	report="$(realpath -m -- "$report")"
	[[ ! -e "$report" && -d "$(dirname -- "$report")" ]] || {
		printf 'Report must be a new file in an existing directory: %s\n' \
			"$report" >&2
		exit 1
	}
	exec > >(tee "$report") 2>&1
fi

target_root="$(mktemp -d /run/sp11-install-preflight.XXXXXX)"
cleanup() {
	if mountpoint -q "$target_root"; then
		umount -R "$target_root"
	fi
	find "$target_root" -depth -delete
}
trap cleanup EXIT

mount -o ro "$root_device" "$target_root"
for directory in dev proc sys run mnt efi; do
	[[ -d "$target_root/$directory" &&
		! -L "$target_root/$directory" ]] || {
		printf 'Target root lacks safe /%s mountpoint.\n' "$directory" >&2
		exit 1
	}
done
mount -o ro "$efi_device" "$target_root/efi"
mount --rbind /dev "$target_root/dev"
mount --make-rslave "$target_root/dev"
mount --rbind /proc "$target_root/proc"
mount --make-rslave "$target_root/proc"
mount --rbind /sys "$target_root/sys"
mount --make-rslave "$target_root/sys"
mount --rbind /run "$target_root/run"
mount --make-rslave "$target_root/run"
mount --bind "$installer_root" "$target_root/mnt"
mount -o remount,bind,ro "$target_root/mnt"

arguments=(
	/mnt/scripts/install.sh
	--payload /mnt/payload
	--held-local-test
)
if [[ $reuse_compatible_modules -eq 1 ]]; then
	arguments+=(--reuse-compatible-modules)
fi

printf 'SP11 held live-image installation preflight\n'
printf 'Root device: %s\n' "$root_device"
printf 'EFI device:  %s\n' "$efi_device"
printf 'Target disk: /dev/%s\n\n' "$root_parent"
chroot "$target_root" "${arguments[@]}"
printf '\nRead-only live-image preflight completed; target filesystems were not modified.\n'
