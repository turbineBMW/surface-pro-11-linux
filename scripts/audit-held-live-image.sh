#!/bin/bash

set -euo pipefail

release="7.1.3-sp11-suspend-review20"
expected_image="918ed2560654355555535290fd0d9657e1afc7022b3e46cc8396155d3575f256"
expected_dtb="5e9009f5bd96a760a33086d1a8842e3228e3d28c413f96d70aca4914f7e397ed"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
output_dir="${1:-}"

usage() {
	printf 'Usage: sudo %s HELD-LIVE-IMAGE-DIRECTORY\n' "$0"
}

[[ "$EUID" -eq 0 && -n "$output_dir" ]] || {
	usage >&2
	exit 2
}
output_dir="$(realpath -e -- "$output_dir")"
case "$output_dir" in
"$repo_root/work"/*) ;;
*)
	printf 'Refusing to audit outside %s/work: %s\n' \
		"$repo_root" "$output_dir" >&2
	exit 1
	;;
esac

rootfs="$output_dir/rootfs"
iso_tree="$output_dir/iso-tree"
tool_root="$output_dir/tool-root"
iso_file="$output_dir/sp11-beta-review20-aarch64-HELD-local.iso"
efi_image="$output_dir/sp11-efiboot.img"
grub_efi="$output_dir/BOOTAA64.EFI"
initramfs="$iso_tree/sp11/initramfs-$release-live.img"
squashfs="$iso_tree/sp11/rootfs.sfs"
manifest="$output_dir/ARTIFACTS.tsv"

for required in \
	"$output_dir/LOCAL-STAGING-NOT-FOR-RELEASE" \
	"$output_dir/HOLD-REASONS" \
	"$rootfs/etc/sp11-live-release" \
	"$iso_file" \
	"$efi_image" \
	"$grub_efi" \
	"$initramfs" \
	"$squashfs" \
	"$manifest"; do
	[[ -e "$required" && ! -L "$required" ]] || {
		printf 'Missing or unsafe held-image member: %s\n' "$required" >&2
		exit 1
	}
done

for command_name in \
	chroot cmp fdisk file find getcap lsinitcpio pacman realpath rg \
	sha256sum stat systemd-analyze; do
	command -v "$command_name" >/dev/null || {
		printf 'Missing audit command: %s\n' "$command_name" >&2
		exit 1
	}
done

[[ "$(sha256sum "$iso_tree/sp11/Image-$release" | awk '{print $1}')" == \
	"$expected_image" ]]
[[ "$(sha256sum "$iso_tree/sp11/x1e80100-microsoft-denali-oled.dtb" |
	awk '{print $1}')" == "$expected_dtb" ]]
[[ "$(stat -c '%a' "$initramfs")" == "644" ]]
[[ "$(stat -c '%s' "$rootfs/etc/machine-id")" == "0" ]]
[[ "$(stat -c '%u:%g:%a' "$rootfs/home/live")" == "1000:1000:700" ]] || {
	printf 'Live root has an unusable home ownership or mode.\n' >&2
	exit 1
}
[[ ! -e "$rootfs/etc/brlapi.key" ]]
[[ ! -e "$rootfs/usr/bin/archinstall" ]]
[[ ! -e "$rootfs/var/lib/bluetooth" ]]
if find "$rootfs/etc/NetworkManager/system-connections" \
	-mindepth 1 -print -quit | grep -q .; then
	printf 'Live root contains a NetworkManager connection profile.\n' >&2
	exit 1
fi

for masked_unit in \
	iio-sensor-proxy.service \
	sp11-sensors.service \
	sp11-ir-bridge.service; do
	[[ -L "$rootfs/etc/systemd/system/$masked_unit" &&
		"$(readlink "$rootfs/etc/systemd/system/$masked_unit")" == \
		"/dev/null" ]] || {
		printf 'Unsafe live unit is not masked: %s\n' "$masked_unit" >&2
		exit 1
	}
done
for excluded_path in \
	"$rootfs/etc/sp11-ir-bridge.conf" \
	"$rootfs/etc/modprobe.d/sp11-ir-loopback.conf" \
	"$rootfs/usr/local/libexec/sp11-ir-bridge" \
	"$rootfs/usr/local/libexec/sp11-ir-light-off" \
	"$rootfs/usr/local/libexec/sp11-hexagonrpcd" \
	"$rootfs/var/lib/sp11-sensors"; do
	[[ ! -e "$excluded_path" ]] || {
		printf 'Excluded live-root path is present: %s\n' "$excluded_path" >&2
		exit 1
	}
done

actual_firmware="$(mktemp /tmp/sp11-audit-firmware.XXXXXX)"
expected_firmware="$(mktemp /tmp/sp11-audit-expected.XXXXXX)"
initramfs_members="$(mktemp /tmp/sp11-audit-initramfs.XXXXXX)"
iso_report="$(mktemp /tmp/sp11-audit-iso.XXXXXX)"
partition_report="$(mktemp /tmp/sp11-audit-partitions.XXXXXX)"
squashfs_report="$(mktemp /tmp/sp11-audit-squashfs.XXXXXX)"
initramfs_extract="$(mktemp -d /tmp/sp11-audit-initramfs-tree.XXXXXX)"
capability_extract="$(mktemp -d /tmp/sp11-audit-capability.XXXXXX)"
cleanup() {
	rm -f -- \
		"$actual_firmware" \
		"$expected_firmware" \
		"$initramfs_members" \
		"$iso_report" \
		"$partition_report" \
		"$squashfs_report"
	find "$initramfs_extract" -depth -delete
	find "$capability_extract" -depth -delete
}
trap cleanup EXIT

find "$rootfs/usr/lib/firmware" -type f \
	-printf '%P\n' | LC_ALL=C sort >"$actual_firmware"
awk -F '\t' 'NR > 1 { print $1 }' \
	"$repo_root/firmware/allowlist.tsv" |
	LC_ALL=C sort >"$expected_firmware"
cmp -- "$expected_firmware" "$actual_firmware" || {
	printf 'Firmware files do not exactly match the allowlist.\n' >&2
	exit 1
}
while IFS=$'\t' read -r path _package _version size expected_sha _rest; do
	[[ "$path" != "path" ]] || continue
	firmware_file="$rootfs/usr/lib/firmware/$path"
	[[ "$(stat -c '%s' "$firmware_file")" == "$size" ]]
	[[ "$(sha256sum "$firmware_file" | awk '{print $1}')" == \
		"$expected_sha" ]]
done <"$repo_root/firmware/allowlist.tsv"

lsinitcpio "$initramfs" >"$initramfs_members"
for required_member in \
	hooks/sp11live \
	"usr/lib/modules/$release/kernel/drivers/clk/qcom/videocc-sm8550.ko" \
	"usr/lib/modules/$release/kernel/drivers/gpu/drm/msm/msm.ko" \
	"usr/lib/modules/$release/kernel/drivers/gpu/drm/panel/panel-samsung-atna33xc20.ko" \
	"usr/lib/modules/$release/kernel/drivers/hid/surface-hid/surface_hid.ko" \
	"usr/lib/modules/$release/kernel/drivers/platform/surface/aggregator/surface_aggregator.ko" \
	"usr/lib/modules/$release/kernel/drivers/usb/storage/uas.ko" \
	"usr/lib/modules/$release/kernel/drivers/usb/storage/usb-storage.ko" \
	"usr/lib/modules/$release/kernel/fs/isofs/isofs.ko" \
	"usr/lib/modules/$release/kernel/fs/overlayfs/overlay.ko" \
	"usr/lib/modules/$release/kernel/fs/squashfs/squashfs.ko"; do
	grep -Fxq "$required_member" "$initramfs_members" || {
		printf 'Initramfs member is missing: %s\n' "$required_member" >&2
		exit 1
	}
done
if rg -n \
	'(^|/)(sp11-ir|sp11-sensors|surface-registry)|^etc/modprobe\.d/' \
	"$initramfs_members"; then
	printf 'Host-only or excluded policy found in initramfs.\n' >&2
	exit 1
fi

build_owner="$(stat -c '%U' "$repo_root")"
if rg -Il -F \
	-e "/home/$build_owner" \
	-e archive-private \
	-e lab-private \
	-e root-lab-data \
	"$rootfs/etc" "$rootfs/var" "$rootfs/root" "$rootfs/home" |
	grep -q .; then
	printf 'Private host-path marker found in live root.\n' >&2
	exit 1
fi
(
	cd -- "$initramfs_extract"
	lsinitcpio -x "$initramfs"
)
initramfs_module_config="$(
	sed -n 's/^MODULES="\([^"]*\)"$/\1/p' \
		"$initramfs_extract/config"
)"
for early_module in \
	isofs \
	msm \
	panel_samsung_atna33xc20 \
	surface_aggregator \
	surface_hid; do
	case " $initramfs_module_config " in
	*" $early_module "*) ;;
	*)
		printf 'Required initramfs module is not loaded early: %s\n' \
			"$early_module" >&2
		exit 1
		;;
	esac
done
if rg -Il -F \
	-e "/home/$build_owner" \
	-e archive-private \
	-e lab-private \
	-e root-lab-data \
	"$initramfs_extract" | grep -q .; then
	printf 'Private host-path marker found in initramfs.\n' >&2
	exit 1
fi

package_count="$(
	pacman \
		--root "$rootfs" \
		--dbpath "$rootfs/var/lib/pacman" \
		-Qq 2>/dev/null | wc -l
)"
[[ "$package_count" -eq 662 ]] || {
	printf 'Unexpected live root package count: %s\n' "$package_count" >&2
	exit 1
}
module_count="$(
	find "$rootfs/usr/lib/modules/$release" \
		-type f -name '*.ko' -printf . | wc -c
)"
[[ "$module_count" -eq 3759 ]] || {
	printf 'Unexpected live root module count: %s\n' "$module_count" >&2
	exit 1
}
for binary in \
	/usr/local/libexec/sp11-iptsd \
	/usr/local/libexec/sp11-iptsd-check-device \
	/usr/local/libexec/power-profiles-daemon-sp11; do
	ldd_output="$(chroot "$rootfs" /usr/bin/ldd "$binary")"
	if rg -q 'not found' <<<"$ldd_output"; then
		printf 'Missing live-root dependency for %s\n' "$binary" >&2
		exit 1
	fi
done
systemd-analyze --man=no --root="$rootfs" verify \
	sp11-bluetooth-address.service \
	sp11-iptsd@.service \
	sp11-live-session.service \
	sp11-noidle.service \
	sp11-power-profile-cpufreq.service \
	systemd-suspend.service
"$tool_root/usr/bin/unsquashfs" -s "$squashfs" >"$squashfs_report"
grep -Fq 'Compression gzip' "$squashfs_report" || {
	printf 'Live SquashFS does not use the qualified kernel gzip codec.\n' >&2
	exit 1
}
grep -Fxq 'CONFIG_SQUASHFS_ZLIB=y' "$repo_root/kernel/config" || {
	printf 'Qualified kernel lacks the live SquashFS gzip codec.\n' >&2
	exit 1
}
grep -Fq 'root=LABEL=SP11BETA' "$iso_tree/boot/grub/grub.cfg"
if grep -Fq 'root=/dev/ram0' "$iso_tree/boot/grub/grub.cfg"; then
	printf 'Live GRUB still requests the nonexistent ramdisk root.\n' >&2
	exit 1
fi
"$tool_root/usr/bin/unsquashfs" \
	-quiet \
	-dest "$capability_extract" \
	"$squashfs" \
	usr/lib/gstreamer-1.0/gst-ptp-helper \
	home/live
getcap "$capability_extract/usr/lib/gstreamer-1.0/gst-ptp-helper" |
	grep -Fq 'cap_net_bind_service,cap_net_admin=ep' || {
	printf 'SquashFS did not preserve the required file capability.\n' >&2
	exit 1
}
[[ "$(stat -c '%u:%g:%a' "$capability_extract/home/live")" == \
	"1000:1000:700" ]] || {
	printf 'SquashFS did not preserve the live home ownership or mode.\n' >&2
	exit 1
}

file "$grub_efi" | grep -Fq \
	'PE32+ executable for EFI (application), ARM64'
"$tool_root/usr/bin/mdir" -i "$efi_image" \
	::/EFI/BOOT/BOOTAA64.EFI >/dev/null
LD_LIBRARY_PATH="$tool_root/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
	"$tool_root/usr/bin/xorriso" \
	-indev "$iso_file" \
	-report_el_torito plain \
	-report_system_area plain >"$iso_report" 2>&1
grep -Eq 'El Torito boot img .*UEFI|El Torito images' "$iso_report"
grep -Fq 'GPT' "$iso_report"
grep -Fq "Volume id    : 'SP11BETA'" "$iso_report"
fdisk -l "$iso_file" >"$partition_report"
grep -Fq 'EFI System' "$partition_report"

awk -F '\t' '
	NR == 1 {
		if ($0 != "artifact\tsha256\tbytes")
			exit 1
		next
	}
	NF != 3 || $2 !~ /^[0-9a-f]{64}$/ || $3 !~ /^[0-9]+$/ {
		exit 1
	}
	{ count++ }
	END { exit count != 5 }
' "$manifest" || {
	printf 'Malformed artifact manifest.\n' >&2
	exit 1
}
while IFS=$'\t' read -r artifact expected_sha expected_size; do
	[[ "$artifact" != "artifact" ]] || continue
	case "$artifact" in
	rootfs.sfs) artifact_path="$squashfs" ;;
	"initramfs-$release-live.img") artifact_path="$initramfs" ;;
	BOOTAA64.EFI) artifact_path="$grub_efi" ;;
	sp11-efiboot.img) artifact_path="$efi_image" ;;
	sp11-beta-review20-aarch64-HELD-local.iso) artifact_path="$iso_file" ;;
	*)
		printf 'Unknown artifact manifest member: %s\n' "$artifact" >&2
		exit 1
		;;
	esac
	[[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == \
		"$expected_sha" ]]
	[[ "$(stat -c '%s' "$artifact_path")" == "$expected_size" ]]
done <"$manifest"

printf 'Held live-image audit passed: 662 packages, 3,759 modules, 11 firmware files, ARM64 UEFI/GPT, clean initramfs policy.\n'
