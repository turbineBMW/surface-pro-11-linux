#!/bin/bash

# Validate and optionally apply an installed-system rollback from the held
# SP11 live image. Target filesystems stay read-only unless both the apply flag
# and the exact held-local confirmation are present.

set -euo pipefail

entry_id="sp11-beta-port73"
installer_root="${SP11_INSTALLER_ROOT:-/opt/sp11-beta-installer}"
root_device=""
efi_device=""
state_path="/var/lib/sp11-beta/latest"
report=""
apply=0
held_confirmation=""

usage() {
	cat <<EOF
Usage: sudo $0 --root-device DEVICE --efi-device DEVICE [options]

Options:
  --state TARGET_STATE_PATH
      Default: /var/lib/sp11-beta/latest
  --report NEW_REPORT_FILE
  --apply
  --confirm-held-local-rollback $entry_id
      Required with --apply.

The wrapper first mounts both target filesystems read-only and validates the
complete rollback transaction. It mounts them writable only after --apply and
the exact held-local confirmation are both present.
EOF
}

while (($#)); do
	case "$1" in
	--root-device) root_device="$2"; shift 2 ;;
	--efi-device) efi_device="$2"; shift 2 ;;
	--state) state_path="$2"; shift 2 ;;
	--report) report="$2"; shift 2 ;;
	--apply) apply=1; shift ;;
	--confirm-held-local-rollback)
		held_confirmation="$2"
		shift 2
		;;
	-h|--help) usage; exit 0 ;;
	*) usage >&2; exit 2 ;;
	esac
done

[[ $EUID -eq 0 ]] || { printf 'Run with sudo/root.\n' >&2; exit 1; }
if [[ ! -f /etc/sp11-live-release ]] ||
	! grep -Fxq 'SP11_HELD_LIVE=1' /etc/sp11-live-release; then
	printf 'This wrapper may run only from the SP11 held live image.\n' >&2
	exit 1
fi
[[ "$(uname -m)" == "aarch64" ]] || {
	printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2
	exit 1
}
dmi="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
compatible="$(tr '\0' '\n' </proc/device-tree/compatible 2>/dev/null || true)"
if [[ "$dmi" != "Microsoft Surface Pro, 11th Edition" ]] ||
	! grep -Fxq 'microsoft,denali' <<<"$compatible"; then
	printf 'This wrapper requires the exact Surface Pro 11 target.\n' >&2
	exit 1
fi
[[ -x "$installer_root/scripts/rollback.sh" ]] || {
	printf 'Held rollback kit is incomplete: %s\n' "$installer_root" >&2
	exit 1
}
case "$state_path" in
/var/lib/sp11-beta/latest|\
/var/lib/sp11-beta/backups/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z) ;;
*)
	printf 'Unsafe target rollback-state path: %s\n' "$state_path" >&2
	exit 2
	;;
esac
if [[ $apply -eq 1 ]]; then
	[[ "$held_confirmation" == "$entry_id" ]] || {
		printf 'Held-local rollback apply requires: %s\n' \
			"--confirm-held-local-rollback $entry_id" >&2
		exit 1
	}
elif [[ -n "$held_confirmation" ]]; then
	printf '--confirm-held-local-rollback is valid only with --apply.\n' >&2
	exit 2
fi

[[ -b "$root_device" && -b "$efi_device" &&
	"$root_device" != "$efi_device" ]] || {
	printf 'Two distinct block-device paths are required.\n' >&2
	exit 2
}
root_device="$(readlink -f -- "$root_device")"
efi_device="$(readlink -f -- "$efi_device")"
[[ "$(lsblk -dnro TYPE "$root_device")" == "part" &&
	"$(lsblk -dnro FSTYPE "$root_device")" == "ext4" ]] || {
	printf 'Root target must be an ext4 partition: %s\n' "$root_device" >&2
	exit 1
}
[[ "$(lsblk -dnro TYPE "$efi_device")" == "part" &&
	"$(lsblk -dnro FSTYPE "$efi_device")" == "vfat" ]] || {
	printf 'EFI target must be a vfat partition: %s\n' "$efi_device" >&2
	exit 1
}
root_parent="$(lsblk -dnro PKNAME "$root_device")"
efi_parent="$(lsblk -dnro PKNAME "$efi_device")"
[[ -n "$root_parent" && "$root_parent" == "$efi_parent" ]] || {
	printf 'Root and EFI devices are not partitions of the same disk.\n' >&2
	exit 1
}
if findmnt -rn -S "$root_device" -o TARGET | grep -q . ||
	findmnt -rn -S "$efi_device" -o TARGET | grep -q .; then
	printf 'Refusing already-mounted target device. Unmount it first.\n' >&2
	exit 1
fi

if [[ -n "$report" ]]; then
	report="$(realpath -m -- "$report")"
	[[ ! -e "$report" && -d "$(dirname -- "$report")" ]] || {
		printf 'Report must be a new file in an existing directory: %s\n' \
			"$report" >&2
		exit 1
	}
	exec > >(tee "$report") 2>&1
fi

target_root="$(mktemp -d /run/sp11-live-rollback.XXXXXX)"
cleanup() {
	sync
	if mountpoint -q "$target_root"; then
		umount -R "$target_root"
	fi
	find "$target_root" -depth -delete
}
trap cleanup EXIT

mount -o ro "$root_device" "$target_root"
for directory in dev proc sys run mnt efi boot var; do
	[[ -d "$target_root/$directory" &&
		! -L "$target_root/$directory" ]] || {
		printf 'Target root lacks safe /%s mountpoint.\n' "$directory" >&2
		exit 1
	}
done
mount -o ro "$efi_device" "$target_root/efi"
mount --rbind /dev "$target_root/dev"
mount --make-rslave "$target_root/dev"
mount -t proc -o nosuid,nodev,noexec proc "$target_root/proc"
mount --rbind /sys "$target_root/sys"
mount --make-rslave "$target_root/sys"
mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs "$target_root/run"
mount --bind "$installer_root" "$target_root/mnt"
mount -o remount,bind,ro "$target_root/mnt"
printf '%s' "$entry_id" \
	>"$target_root/run/sp11-live-offline-rollback-authorized"
chmod 0600 "$target_root/run/sp11-live-offline-rollback-authorized"

rollback_arguments=(
	/mnt/scripts/rollback.sh
	--state "$state_path"
	--offline-target
)
rollback_environment=(
	/usr/bin/env
	SP11_LIVE_OFFLINE_ROLLBACK="$entry_id"
)

printf 'SP11 held live-image offline rollback preflight\n'
printf 'Root device: %s\n' "$root_device"
printf 'EFI device:  %s\n' "$efi_device"
printf 'Target disk: /dev/%s\n' "$root_parent"
printf 'State:       %s\n\n' "$state_path"
chroot "$target_root" \
	"${rollback_environment[@]}" "${rollback_arguments[@]}"
printf '\nRead-only rollback preflight passed; target filesystems were not modified.\n'

if [[ $apply -ne 1 ]]; then
	printf 'Re-run with --apply and the exact held-local confirmation to continue.\n'
	exit 0
fi

resolved_state="$(
	chroot "$target_root" /usr/bin/readlink -f -- "$state_path"
)"
case "$resolved_state" in
/var/lib/sp11-beta/backups/*) ;;
*)
	printf 'Unsafe resolved rollback state: %s\n' "$resolved_state" >&2
	exit 1
	;;
esac
state_host="$target_root$resolved_state"
expected_windows_sha="$(
	sed -n 's/^windows_loader_sha256=//p' "$state_host/install-info"
)"
module_state="$(
	sed -n 's/^module_state=//p' "$state_host/install-info"
)"
boot_state="$(
	sed -n 's/^boot_state=//p' "$state_host/install-info"
)"
[[ "$expected_windows_sha" =~ ^[0-9a-f]{64}$ &&
	"$module_state" =~ ^(fresh|reuse-compatible)$ &&
	"$boot_state" =~ ^(fresh|repair)$ ]] || {
	printf 'Unsafe rollback install metadata.\n' >&2
	exit 1
}

mount -o remount,rw "$root_device" "$target_root"
mount -o remount,rw "$efi_device" "$target_root/efi"
for writable_target in "$target_root" "$target_root/efi"; do
	mount_options="$(findmnt -no OPTIONS -T "$writable_target")"
	case ",$mount_options," in
	*,rw,*) ;;
	*)
		printf 'Failed to make target writable: %s\n' \
			"$writable_target" >&2
		exit 1
		;;
	esac
done

printf '\nHeld-local confirmation accepted; applying offline rollback.\n\n'
chroot "$target_root" \
	"${rollback_environment[@]}" \
	"${rollback_arguments[@]}" \
	--apply

windows_loader="$target_root/efi/EFI/Microsoft/Boot/bootmgfw.efi"
[[ -f "$windows_loader" &&
	"$(sha256sum "$windows_loader" | awk '{print $1}')" == \
	"$expected_windows_sha" ]] || {
	printf 'Windows Boot Manager identity changed after live rollback.\n' >&2
	exit 1
}
efibootmgr -v | grep -Fq 'Windows Boot Manager' || {
	printf 'Windows Boot Manager EFI entry is missing after live rollback.\n' >&2
	exit 1
}
grep -Fq 'chainloader /EFI/Microsoft/Boot/bootmgfw.efi' \
	"$target_root/boot/grub/grub.cfg" || {
	printf 'Windows GRUB chainloader is missing after live rollback.\n' >&2
	exit 1
}
next_entry="$(
	grub-editenv "$target_root/boot/grub/grubenv" list |
		sed -n 's/^next_entry=//p' |
		head -n1
)"
[[ "$next_entry" != "$entry_id" ]] || {
	printf 'Installed candidate remains armed after live rollback.\n' >&2
	exit 1
}
if [[ "$boot_state" == "fresh" ]]; then
	[[ ! -e "$target_root/boot/sp11-beta" &&
		! -e "$target_root/etc/grub.d/09_sp11_beta" ]] || {
		printf 'Fresh candidate boot state remains after live rollback.\n' >&2
		exit 1
	}
fi
if [[ "$module_state" == "fresh" ]]; then
	[[ ! -e "$target_root/usr/lib/modules/7.1.3-sp11-suspend-review20" &&
		! -e "$target_root/usr/lib/modules/7.2.0-sp11-73beta1" ]] || {
		printf 'Fresh candidate module tree remains after live rollback.\n' >&2
		exit 1
	}
else
	[[ -d "$target_root/usr/lib/modules/7.1.3-sp11-suspend-review20" ||
		-d "$target_root/usr/lib/modules/7.2.0-sp11-73beta1" ]] || {
		printf 'Reused compatible module tree was removed by live rollback.\n' >&2
		exit 1
	}
fi

sync -f "$target_root"
sync -f "$target_root/efi"
printf '\nOffline rollback and independent post-checks passed.\n'
printf 'Shut down the live image, remove the USB, and boot the restored system.\n'
