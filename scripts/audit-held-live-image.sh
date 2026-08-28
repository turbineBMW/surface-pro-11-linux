#!/bin/bash

set -euo pipefail

release="7.1.3-sp11-suspend-review20"
expected_image="918ed2560654355555535290fd0d9657e1afc7022b3e46cc8396155d3575f256"
expected_dtb="5e9009f5bd96a760a33086d1a8842e3228e3d28c413f96d70aca4914f7e397ed"
expected_wallpaper="1fdc98d786badbf332460460da51496c3674cbead0d501f0e98708c4bb0bb5ac"

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
firmware_image="$output_dir/sp11-firmware.img"
grub_efi="$output_dir/BOOTAA64.EFI"
initramfs="$iso_tree/sp11/initramfs-$release-live.img"
squashfs="$iso_tree/sp11/rootfs.sfs"
squashfs_checksum="$iso_tree/sp11/rootfs.sfs.sha256"
manifest="$output_dir/ARTIFACTS.tsv"

for required in \
	"$output_dir/LOCAL-STAGING-NOT-FOR-RELEASE" \
	"$output_dir/LOCAL-WALLPAPER-IMPORT" \
	"$output_dir/HOLD-REASONS" \
	"$rootfs/etc/sp11-live-release" \
	"$iso_file" \
	"$efi_image" \
	"$firmware_image" \
	"$grub_efi" \
	"$initramfs" \
	"$squashfs" \
	"$squashfs_checksum" \
	"$manifest"; do
	[[ -e "$required" && ! -L "$required" ]] || {
		printf 'Missing or unsafe held-image member: %s\n' "$required" >&2
		exit 1
	}
done

for command_name in \
	chroot cmp diff fdisk file find getcap lsinitcpio pacman realpath rg \
	readlink sha256sum stat systemd-analyze; do
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
chroot "$rootfs" /usr/bin/id -nG live |
	grep -Eq '(^| )render( |$)' || {
	printf 'Live user lacks render-group access required by camera processing.\n' >&2
	exit 1
}
[[ ! -e "$rootfs/etc/brlapi.key" ]]
[[ ! -e "$rootfs/usr/bin/archinstall" ]]
[[ ! -e "$rootfs/var/lib/bluetooth" ]]
wallpaper="$rootfs/usr/share/backgrounds/sp11/tux-surface.png"
[[ -f "$wallpaper" && ! -L "$wallpaper" &&
	"$(stat -c '%s' "$wallpaper")" == "4789340" &&
	"$(sha256sum "$wallpaper" | awk '{print $1}')" == \
	"$expected_wallpaper" ]]
file "$wallpaper" |
	grep -Fq 'PNG image data, 2880 x 1920, 8-bit/color RGB'
grep -Fxq \
	"$expected_wallpaper  usr/share/backgrounds/sp11/tux-surface.png" \
	"$output_dir/LOCAL-WALLPAPER-IMPORT"
cmp -- "$repo_root/iso/desktop/dconf-profile-user" \
	"$rootfs/etc/dconf/profile/user"
cmp -- "$repo_root/iso/desktop/00-sp11-live" \
	"$rootfs/etc/dconf/db/local.d/00-sp11-live"
[[ -f "$rootfs/etc/dconf/db/local" ]]
grep -Fxq "SP11_WALLPAPER_SHA256=$expected_wallpaper" \
	"$rootfs/etc/sp11-live-release"
grep -Fxq 'SP11_GNOME_ACCENT=orange' \
	"$rootfs/etc/sp11-live-release"
grep -Fxq 'SP11_RNOTE_VERSION=0.14.2-2' \
	"$rootfs/etc/sp11-live-release"
[[ "$(chroot "$rootfs" /usr/bin/gsettings get \
	org.gnome.desktop.background picture-uri)" == \
	"'file:///usr/share/backgrounds/sp11/tux-surface.png'" ]]
[[ "$(chroot "$rootfs" /usr/bin/gsettings get \
	org.gnome.desktop.background picture-uri-dark)" == \
	"'file:///usr/share/backgrounds/sp11/tux-surface.png'" ]]
[[ "$(chroot "$rootfs" /usr/bin/gsettings get \
	org.gnome.desktop.interface accent-color)" == "'orange'" ]]
chroot "$rootfs" /usr/bin/pacman -Q rnote |
	grep -Fxq 'rnote 0.14.2-2'
[[ -x "$rootfs/usr/local/bin/sp11-firmware" ]]
cmp -- "$repo_root/scripts/sp11-firmware.py" \
	"$rootfs/usr/local/bin/sp11-firmware"
cmp -- "$repo_root/scripts/validate-external-firmware.py" \
	"$rootfs/usr/local/libexec/sp11-validate-external-firmware"
[[ -x "$rootfs/usr/local/libexec/sp11-validate-external-firmware" ]]
[[ -x "$rootfs/usr/local/bin/sp11-install-preflight" ]]
[[ -x "$rootfs/usr/local/bin/sp11-rollback-live" ]]
[[ -x "$rootfs/usr/local/bin/sp11-capture-install-baseline" ]]
[[ -x "$rootfs/usr/local/bin/sp11-installer-ui" ]]
fresh_root="$rootfs/usr/local/libexec/sp11-fresh-installer"
fresh_artifact="$rootfs/opt/sp11-fresh-installer/artifact"
for fresh_script in \
	sp11-install-plan.py \
	sp11-install-executor.py \
	manifest-installed-rootfs.py; do
	cmp -- "$repo_root/scripts/$fresh_script" \
		"$fresh_root/scripts/$fresh_script"
	[[ "$(stat -c '%a' "$fresh_root/scripts/$fresh_script")" == "755" ]]
done
cmp -- "$repo_root/scripts/sp11-installer-ui.py" \
	"$rootfs/usr/local/bin/sp11-installer-ui"
cmp -- "$repo_root/firmware/external-required.tsv" \
	"$fresh_root/firmware/external-required.tsv"
cmp -- \
	"$repo_root/iso/installer-ui-staging/usr/share/applications/sp11-installer-preview.desktop" \
	"$rootfs/usr/share/applications/sp11-installer.desktop"
[[ ! -e "$fresh_artifact/rootfs" ]]
for fresh_member in \
	ARTIFACTS.tsv \
	BOOT-PAYLOAD.tsv \
	ROOTFS-FILES.tsv \
	sp11-installed-rootfs.tar.zst \
	"boot/Image-$release" \
	boot/x1e80100-microsoft-denali-oled.dtb; do
	[[ -f "$fresh_artifact/$fresh_member" && \
		! -L "$fresh_artifact/$fresh_member" ]]
done
archive_sha="$(awk -F '\t' \
	'$1 == "sp11-installed-rootfs.tar.zst" { print $2 }' \
	"$fresh_artifact/ARTIFACTS.tsv")"
[[ "$archive_sha" =~ ^[0-9a-f]{64}$ ]]
[[ "$(sha256sum "$fresh_artifact/sp11-installed-rootfs.tar.zst" | \
	awk '{print $1}')" == "$archive_sha" ]]
grep -Fxq 'SP11_FRESH_INSTALLER=1' "$rootfs/etc/sp11-live-release"
grep -Fxq "SP11_INSTALLED_ROOTFS_SHA256=$archive_sha" \
	"$rootfs/etc/sp11-live-release"
cmp -- "$repo_root/firmware/external-required.tsv" \
	"$rootfs/usr/share/sp11/external-required.tsv"
cmp -- "$repo_root/firmware/derived.tsv" \
	"$rootfs/usr/share/sp11/derived-firmware.tsv"
cmp -- "$repo_root/scripts/sp11-collect-firmware.ps1" \
	"$iso_tree/sp11-tools/sp11-collect-firmware.ps1"
cmp -- "$repo_root/scripts/RUN-IN-WINDOWS.cmd" \
	"$iso_tree/sp11-tools/RUN-IN-WINDOWS.cmd"
cmp -- "$repo_root/scripts/sp11-firmware.py" \
	"$iso_tree/sp11-tools/sp11-firmware.py"

installer_root="$rootfs/opt/sp11-beta-installer"
installer_manifest="$installer_root/INSTALLER-FILES.tsv"
for installer_member in \
	"$installer_manifest" \
	"$installer_root/RELEASE-STATUS.md" \
	"$installer_root/scripts/install.sh" \
	"$installer_root/scripts/rollback.sh" \
	"$installer_root/scripts/verify.sh" \
	"$installer_root/scripts/verify-install.sh" \
	"$installer_root/scripts/capture-install-baseline.sh" \
	"$installer_root/iso/audio-ucm.tsv" \
	"$installer_root/payload/MODULES.tsv" \
	"$installer_root/payload/SHA256SUMS"; do
	[[ -f "$installer_member" && ! -L "$installer_member" ]] || {
		printf 'Missing or unsafe installer-kit member: %s\n' \
			"$installer_member" >&2
		exit 1
	}
done
for installer_script in \
	install.sh \
	rollback.sh \
	verify.sh \
	verify-install.sh \
	capture-install-baseline.sh; do
	cmp -- "$repo_root/scripts/$installer_script" \
		"$installer_root/scripts/$installer_script"
	[[ "$(stat -c '%a' "$installer_root/scripts/$installer_script")" == \
		"755" ]]
done
grep -Fq \
  'systemctl stop power-profiles-daemon.service 2>/dev/null || true' \
  "$installer_root/scripts/rollback.sh"
cmp -- "$repo_root/scripts/sp11-install-live-preflight.sh" \
	"$rootfs/usr/local/bin/sp11-install-preflight"
cmp -- "$repo_root/scripts/capture-install-baseline.sh" \
	"$rootfs/usr/local/bin/sp11-capture-install-baseline"
cmp -- "$repo_root/RELEASE-STATUS.md" \
	"$installer_root/RELEASE-STATUS.md"
cmp -- "$repo_root/iso/audio-ucm.tsv" \
	"$installer_root/iso/audio-ucm.tsv"
diff -qr --no-dereference "$repo_root/rootfs" \
	"$installer_root/rootfs"
(
	cd -- "$installer_root/payload"
	sha256sum -c SHA256SUMS
)
awk -F '\t' '
	NR == 1 {
		if ($0 != "path\tbytes\tsha256")
			exit 1
		next
	}
	NF != 3 ||
	$1 !~ /^kernel\/.*\.ko$/ ||
	$1 ~ /(^|\/)\.\.?(\/|$)/ ||
	$2 !~ /^[0-9]+$/ ||
	$3 !~ /^[0-9a-f]{64}$/ {
		exit 1
	}
	{ count++ }
	END { exit count != 3759 }
' "$installer_root/payload/MODULES.tsv" || {
	printf 'Malformed embedded module manifest.\n' >&2
	exit 1
}
awk -F '\t' '
	NR == 1 {
		if ($0 != "path\tbytes\tsha256")
			exit 1
		next
	}
	NF != 3 ||
	$1 ~ /(^|\/)\.\.?(\/|$)/ ||
	$1 == "INSTALLER-FILES.tsv" ||
	$2 !~ /^[0-9]+$/ ||
	$3 !~ /^[0-9a-f]{64}$/ {
		exit 1
	}
	{ count++ }
	END { exit count < 1 }
' "$installer_manifest" || {
	printf 'Malformed installer-kit manifest.\n' >&2
	exit 1
}
while IFS=$'\t' read -r installer_path expected_size expected_sha; do
	[[ "$installer_path" != "path" ]] || continue
	installer_file="$installer_root/$installer_path"
	[[ -f "$installer_file" && ! -L "$installer_file" ]]
	[[ "$(stat -c '%s' "$installer_file")" == "$expected_size" ]]
	[[ "$(sha256sum "$installer_file" | awk '{print $1}')" == \
		"$expected_sha" ]]
done <"$installer_manifest"
cmp \
	<(awk -F '\t' 'NR > 1 { print $1 }' "$installer_manifest" |
		LC_ALL=C sort) \
	<(find "$installer_root" -type f \
		! -name INSTALLER-FILES.tsv -printf '%P\n' |
		LC_ALL=C sort) || {
	printf 'Installer-kit files do not exactly match its manifest.\n' >&2
	exit 1
}
installer_manifest_sha="$(
	sha256sum "$installer_manifest" | awk '{print $1}'
)"
grep -Fxq 'SP11_INSTALL_PREFLIGHT=1' \
	"$rootfs/etc/sp11-live-release"
grep -Fxq 'SP11_OFFLINE_ROLLBACK=1' \
	"$rootfs/etc/sp11-live-release"
grep -Fxq \
	"SP11_INSTALLER_MANIFEST_SHA256=$installer_manifest_sha" \
	"$rootfs/etc/sp11-live-release"
grep -Fq "mount -o ro \"\$root_device\"" \
	"$rootfs/usr/local/bin/sp11-install-preflight"
if grep -Fq -- '--apply' \
	"$rootfs/usr/local/bin/sp11-install-preflight"; then
	printf 'Live preflight wrapper exposes an apply path.\n' >&2
	exit 1
fi
cmp -- "$repo_root/scripts/sp11-rollback-live.sh" \
	"$rootfs/usr/local/bin/sp11-rollback-live"
grep -Fq "mount -o ro \"\$root_device\"" \
	"$rootfs/usr/local/bin/sp11-rollback-live"
grep -Fq -- '--confirm-held-local-rollback' \
	"$rootfs/usr/local/bin/sp11-rollback-live"
grep -Fq "mount -o remount,rw \"\$root_device\" \"\$target_root\"" \
	"$rootfs/usr/local/bin/sp11-rollback-live"
grep -Fq 'SP11_LIVE_OFFLINE_ROLLBACK=' \
	"$rootfs/usr/local/bin/sp11-rollback-live"
grep -Fq -- '--confirm-held-local-install' \
	"$installer_root/scripts/install.sh"
grep -Fq 'systemd-enable-state-before.tsv' \
	"$installer_root/scripts/install.sh"
grep -Fq 'state-symlinks.tsv' \
	"$installer_root/scripts/install.sh"
grep -Fq -- '--offline-target' \
	"$installer_root/scripts/rollback.sh"
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
firmware_seed_extract="$(mktemp -d /tmp/sp11-audit-sp11fw.XXXXXX)"
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
	find "$firmware_seed_extract" -depth -delete
}
trap cleanup EXIT

find "$rootfs/usr/lib/firmware" -type f \
	-printf '%P\n' | LC_ALL=C sort >"$actual_firmware"
local_firmware_count=0
if [[ -e "$output_dir/LOCAL-PROPRIETARY-FIRMWARE-IMPORT" ]]; then
	[[ -f "$output_dir/LOCAL-PROPRIETARY-FIRMWARE-IMPORT" &&
		! -L "$output_dir/LOCAL-PROPRIETARY-FIRMWARE-IMPORT" &&
		-f "$rootfs/etc/sp11-local-proprietary-firmware" &&
		! -L "$rootfs/etc/sp11-local-proprietary-firmware" ]]
	cmp -- \
		"$output_dir/LOCAL-PROPRIETARY-FIRMWARE-IMPORT" \
		"$rootfs/etc/sp11-local-proprietary-firmware"
	grep -Fxq 'SP11_LOCAL_PROPRIETARY_FIRMWARE=1' \
		"$rootfs/etc/sp11-live-release"
	local_firmware_count=5
else
	[[ ! -e "$rootfs/etc/sp11-local-proprietary-firmware" ]]
	if grep -q '^SP11_LOCAL_PROPRIETARY_FIRMWARE=' \
		"$rootfs/etc/sp11-live-release"; then
		printf 'Unmarked local firmware mode in live release metadata.\n' >&2
		exit 1
	fi
fi
{
	awk -F '\t' 'NR > 1 { print $1 }' \
		"$repo_root/firmware/allowlist.tsv"
	awk -F '\t' 'NR > 1 { print $1 }' \
		"$repo_root/firmware/derived.tsv"
	printf '%s\n' \
		qcom/x1e80100/X1E80100-Microsoft-Surface-Pro-11-tplg.bin
	if [[ "$local_firmware_count" -eq 5 ]]; then
		awk -F '\t' 'NR > 1 { print $1 }' \
			"$repo_root/firmware/external-required.tsv"
	fi
} | LC_ALL=C sort >"$expected_firmware"
cmp -- "$expected_firmware" "$actual_firmware" || {
	printf 'Firmware files do not exactly match the selected manifests.\n' >&2
	exit 1
}
while IFS=$'\t' read -r path _package _version size expected_sha _rest; do
	[[ "$path" != "path" ]] || continue
	firmware_file="$rootfs/usr/lib/firmware/$path"
	[[ "$(stat -c '%s' "$firmware_file")" == "$size" ]]
	[[ "$(sha256sum "$firmware_file" | awk '{print $1}')" == \
		"$expected_sha" ]]
done <"$repo_root/firmware/allowlist.tsv"
while IFS=$'\t' read -r path _source_path _record size expected_sha _rest; do
	[[ "$path" != "path" ]] || continue
	firmware_file="$rootfs/usr/lib/firmware/$path"
	[[ -f "$firmware_file" && ! -L "$firmware_file" ]]
	[[ "$(stat -c '%s' "$firmware_file")" == "$size" ]]
	[[ "$(sha256sum "$firmware_file" | awk '{print $1}')" == \
		"$expected_sha" ]]
done <"$repo_root/firmware/derived.tsv"
topology="$rootfs/usr/lib/firmware/qcom/x1e80100/X1E80100-Microsoft-Surface-Pro-11-tplg.bin"
[[ -f "$topology" && ! -L "$topology" &&
	"$(stat -c '%s' "$topology")" == "11320" &&
	"$(sha256sum "$topology" | awk '{print $1}')" == \
	"89b731f3f98fc2b84699bca39a56e390925a44a26d5aea80382cf617e00c08d8" ]]
if [[ "$local_firmware_count" -eq 5 ]]; then
	verified_local_count=0
	while IFS=$'\t' read -r path expected_size expected_sha _rest; do
		[[ "$path" != "path" ]] || continue
		firmware_file="$rootfs/usr/lib/firmware/$path"
		[[ -f "$firmware_file" && ! -L "$firmware_file" ]]
		[[ "$(stat -c '%s' "$firmware_file")" == "$expected_size" &&
			"$(sha256sum "$firmware_file" | awk '{print $1}')" == \
			"$expected_sha" ]]
		((verified_local_count += 1))
	done <"$repo_root/firmware/external-required.tsv"
	[[ "$verified_local_count" -eq "$local_firmware_count" ]]
fi

[[ ! -e "$output_dir/LOCAL-AUDIO-UCM-IMPORT" &&
	! -e "$rootfs/etc/sp11-local-audio-ucm" ]]
expected_ucm_manifest_sha="$(
	sha256sum "$repo_root/iso/audio-ucm.tsv" | awk '{print $1}'
)"
grep -Fxq \
	"SP11_AUDIO_UCM_MANIFEST_SHA256=$expected_ucm_manifest_sha" \
	"$rootfs/etc/sp11-live-release"
ucm_count=0
while IFS=$'\t' read -r path entry_type identity; do
	[[ "$path" != "path" ]] || continue
	ucm_entry="$rootfs/usr/share/alsa/ucm2/$path"
	case "$entry_type" in
	file)
		[[ "$identity" =~ ^[0-9a-f]{64}$ &&
			-f "$ucm_entry" && ! -L "$ucm_entry" ]]
		[[ "$(sha256sum "$ucm_entry" | awk '{print $1}')" == \
			"$identity" ]]
		;;
	symlink)
		[[ -L "$ucm_entry" &&
			"$(readlink "$ucm_entry")" == "$identity" ]]
		;;
	*)
		printf 'Unknown audio UCM manifest type for %s: %s\n' \
			"$path" "$entry_type" >&2
		exit 1
		;;
	esac
	((ucm_count += 1))
done <"$repo_root/iso/audio-ucm.tsv"
[[ "$ucm_count" -eq 4 ]]

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
cmp -- "$repo_root/iso/mkinitcpio/hooks/sp11live" \
	"$initramfs_extract/hooks/sp11live" || {
	printf 'Embedded SP11 live hook does not match the reviewed source.\n' >&2
	exit 1
}
grep -Fq 'copying SP11 live SquashFS into RAM' \
	"$initramfs_extract/hooks/sp11live" || {
	printf 'Initramfs does not copy the live root into RAM.\n' >&2
	exit 1
}
grep -Fq 'rootfs.sfs.sha256' \
	"$initramfs_extract/hooks/sp11live" || {
	printf 'Initramfs does not verify the RAM-backed live root.\n' >&2
	exit 1
}
for required_external_marker in \
	LABEL=SP11FW \
	SP11-FIRMWARE-MANIFEST.tsv \
	sp11-validate-external-firmware \
	run_earlyhook \
	'grub: five owner firmware files validated before module loading' \
	sp11_import_from_partition \
	'resolve_device LABEL=SP11FW'; do
	grep -Fq "$required_external_marker" \
		"$initramfs_extract/hooks/sp11live" || {
		printf 'Initramfs lacks SP11FW contract marker: %s\n' \
			"$required_external_marker" >&2
		exit 1
	}
done
for early_validator_member in \
	usr/bin/python3 \
	usr/local/libexec/sp11-validate-external-firmware; do
	grep -Fxq "$early_validator_member" "$initramfs_members" || {
		printf 'Initramfs early validator member is missing: %s\n' \
			"$early_validator_member" >&2
		exit 1
	}
done
grep -Eq '^usr/lib/python3[.][0-9]+/' "$initramfs_members" || {
	printf 'Initramfs Python standard library is missing.\n' >&2
	exit 1
}
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
for builtin_fat_option in \
	CONFIG_FAT_FS=y \
	CONFIG_VFAT_FS=y \
	CONFIG_NLS_CODEPAGE_437=y \
	CONFIG_NLS_ASCII=y; do
	grep -Fxq "$builtin_fat_option" "$repo_root/kernel/config" || {
		printf 'Required built-in SP11FW filesystem option is absent: %s\n' \
			"$builtin_fat_option" >&2
		exit 1
	}
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
[[ "$package_count" -eq 663 ]] || {
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
	sp11-firmware-import.service \
	sp11-iptsd@.service \
	sp11-live-session.service \
	sp11-noidle.service \
	sp11-power-profile-cpufreq.service \
	systemd-suspend.service
"$tool_root/usr/bin/unsquashfs" -s "$squashfs" >"$squashfs_report"
grep -Fq 'Compression xz' "$squashfs_report" || {
	printf 'Live SquashFS does not use the xz codec.\n' >&2
	exit 1
}
(
	cd -- "$iso_tree/sp11"
	sha256sum -c rootfs.sfs.sha256
)
grep -Fxq 'CONFIG_SQUASHFS_XZ=y' "$repo_root/kernel/config" || {
	printf 'Qualified kernel lacks the live SquashFS xz codec.\n' >&2
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
firmware_directory="$("$tool_root/usr/bin/mdir" -i "$firmware_image" ::)"
grep -Fq 'is SP11FW' <<<"$firmware_directory"
for firmware_seed_file in \
	START-HERE.txt \
	RUN-IN-WINDOWS.cmd \
	sp11-collect-firmware.ps1 \
	sp11-firmware.py \
	sp11-live-firstboot-capture.sh \
	GETTING-STARTED.md \
	FIRMWARE.md; do
	MTOOLS_SKIP_CHECK=1 "$tool_root/usr/bin/mcopy" \
		-i "$firmware_image" "::$firmware_seed_file" \
		"$firmware_seed_extract/$firmware_seed_file"
done
cmp -- "$repo_root/iso/START-HERE.txt" \
	"$firmware_seed_extract/START-HERE.txt"
cmp -- "$repo_root/scripts/RUN-IN-WINDOWS.cmd" \
	"$firmware_seed_extract/RUN-IN-WINDOWS.cmd"
cmp -- "$repo_root/scripts/sp11-collect-firmware.ps1" \
	"$firmware_seed_extract/sp11-collect-firmware.ps1"
cmp -- "$repo_root/scripts/sp11-firmware.py" \
	"$firmware_seed_extract/sp11-firmware.py"
cmp -- "$repo_root/scripts/sp11-live-firstboot-capture.sh" \
	"$firmware_seed_extract/sp11-live-firstboot-capture.sh"
cmp -- "$repo_root/docs/GETTING-STARTED.md" \
	"$firmware_seed_extract/GETTING-STARTED.md"
cmp -- "$repo_root/docs/FIRMWARE.md" \
	"$firmware_seed_extract/FIRMWARE.md"
[[ "$(find "$firmware_seed_extract" -maxdepth 1 -type f -printf . | wc -c)" \
	-eq 7 ]]
[[ "$(stat -c '%s' "$firmware_image")" -eq 134217728 ]]
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
grep -Eq 'iso3 +[0-9]+ +[0-9]+ +262144 +128M +Microsoft basic data' \
	"$partition_report" || {
	printf 'Hybrid ISO lacks the 128 MiB SP11FW data partition.\n' >&2
	exit 1
}

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
	END { exit count != 6 }
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
	sp11-firmware.img) artifact_path="$firmware_image" ;;
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

printf 'Held live-image audit passed: 663 packages (including Rnote), 3,759 modules, %s firmware files, orange GNOME accent, verified local Tux Surface wallpaper, 4 project UCM entries, verified overlay and fresh-machine installer kits, identity-pinned installed root artifact, ARM64 UEFI/GPT with helper-seeded SP11FW partition, clean initramfs policy.\n' \
	"$((13 + local_firmware_count))"
