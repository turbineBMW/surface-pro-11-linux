#!/bin/bash

# Build the first non-installing ARM64 UEFI GNOME live image from frozen,
# signed inputs. The output is always held local engineering material while
# BINARY-RELEASE-HOLD.md exists.

set -euo pipefail

release="7.1.3-sp11-suspend-review20"
volume_id="SP11BETA"
source_date_epoch=1785076525
expected_snapshot_manifest="cb336c6fa1dfab9644f304e89a797ab70d2e1131c6192484a5d043559c7221fe"
expected_image="918ed2560654355555535290fd0d9657e1afc7022b3e46cc8396155d3575f256"
expected_dtb="5e9009f5bd96a760a33086d1a8842e3228e3d28c413f96d70aca4914f7e397ed"
expected_iptsd="45ce0fcabdda04a9fcf3ce30f7f0c64ba7098fd2351127ef0e54cf0ac0b3f083"
expected_checker="54fcdaef90b0bd4239df670865cf8b258c3ae6e3988e42b0b9a3b58aaa4b08f5"
expected_ppd="9e1d72935f2b916de1c44950e425948e60c7bdf83c69bede2a079e7a79a82252"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
package_snapshot="$repo_root/work/package-snapshot-469dfdf921d1-20260728"
firmware_cache="$repo_root/work/firmware-package-cache-20260622"
payload="$repo_root/work/payload-review20-videocc-qualified-20260728"
output_dir="$repo_root/work/live-image-review20-held-20260728"
local_staging=0

usage() {
	cat <<EOF
Usage: sudo $0 --local-staging [options]

Options:
  --package-snapshot DIRECTORY
  --firmware-cache DIRECTORY
  --payload DIRECTORY
  --output DIRECTORY

The output must be a new directory below work/. The script never installs to
the host, writes firmware variables, partitions disks, or includes an
installer.
EOF
}

while (($#)); do
	case "$1" in
	--local-staging)
		local_staging=1
		shift
		;;
	--package-snapshot)
		package_snapshot="$2"
		shift 2
		;;
	--firmware-cache)
		firmware_cache="$2"
		shift 2
		;;
	--payload)
		payload="$2"
		shift 2
		;;
	--output)
		output_dir="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		usage >&2
		exit 2
		;;
	esac
done

[[ "$local_staging" -eq 1 ]] || {
	printf 'Live-image construction requires explicit --local-staging.\n' >&2
	exit 1
}
[[ -e "$repo_root/BINARY-RELEASE-HOLD.md" ]] || {
	printf 'This helper is restricted to held local engineering builds.\n' >&2
	exit 1
}
[[ "$EUID" -eq 0 ]] || {
	printf 'Run with sudo/root; only a new work/ tree is modified.\n' >&2
	exit 1
}
[[ "$(uname -m)" == "aarch64" ]] || {
	printf 'Native aarch64 is required.\n' >&2
	exit 1
}

package_snapshot="$(realpath -e -- "$package_snapshot")"
firmware_cache="$(realpath -e -- "$firmware_cache")"
payload="$(realpath -e -- "$payload")"
output_dir="$(realpath -m -- "$output_dir")"
case "$output_dir" in
"$repo_root/work"/*) ;;
*)
	printf 'Refusing output outside %s/work: %s\n' \
		"$repo_root" "$output_dir" >&2
	exit 1
	;;
esac
[[ ! -e "$output_dir" ]] || {
	printf 'Refusing to replace existing output: %s\n' "$output_dir" >&2
	exit 1
}

for command_name in \
	awk bsdtar chroot cmp depmod find getent grub-mkstandalone \
	install journalctl mkfs.fat mkinitcpio pacman pacman-key realpath rsync \
	sha256sum stat systemctl tar touch truncate; do
	command -v "$command_name" >/dev/null || {
		printf 'Missing required command: %s\n' "$command_name" >&2
		exit 1
	}
done

"$script_dir/audit-package-lock.sh"
"$script_dir/audit-firmware-manifest.sh"

[[ "$(sha256sum "$package_snapshot/PACKAGE-SNAPSHOT.tsv" |
	awk '{print $1}')" == "$expected_snapshot_manifest" ]] || {
	printf 'Unexpected package snapshot identity.\n' >&2
	exit 1
}
cmp -- "$repo_root/iso/packages.lock.tsv" \
	"$package_snapshot/packages.lock.tsv"
cmp -- "$repo_root/iso/repositories.lock.tsv" \
	"$package_snapshot/repositories.lock.tsv"

for required_payload in \
	"Image-$release" \
	x1e80100-microsoft-denali-oled.dtb \
	"modules-$release.tar.zst" \
	sp11-iptsd \
	sp11-iptsd-check-device \
	power-profiles-daemon-sp11 \
	SHA256SUMS; do
	[[ -f "$payload/$required_payload" && ! -L "$payload/$required_payload" ]] || {
		printf 'Missing or unsafe payload input: %s\n' \
			"$required_payload" >&2
		exit 1
	}
done
(
	cd -- "$payload"
	sha256sum -c SHA256SUMS
)
[[ "$(sha256sum "$payload/Image-$release" | awk '{print $1}')" == \
	"$expected_image" ]]
[[ "$(sha256sum "$payload/x1e80100-microsoft-denali-oled.dtb" |
	awk '{print $1}')" == "$expected_dtb" ]]
[[ "$(sha256sum "$payload/sp11-iptsd" | awk '{print $1}')" == \
	"$expected_iptsd" ]]
[[ "$(sha256sum "$payload/sp11-iptsd-check-device" |
	awk '{print $1}')" == "$expected_checker" ]]
[[ "$(sha256sum "$payload/power-profiles-daemon-sp11" |
	awk '{print $1}')" == "$expected_ppd" ]]

mkdir -p -- "$output_dir"
printf '%s\n' \
	'BINARY/ISO RELEASE HOLD ACTIVE — LOCAL ENGINEERING IMAGE ONLY' \
	>"$output_dir/LOCAL-STAGING-NOT-FOR-RELEASE"

rootfs="$output_dir/rootfs"
iso_tree="$output_dir/iso-tree"
tool_root="$output_dir/tool-root"
firmware_extract="$output_dir/firmware-extract"
hook_root="$output_dir/initcpio-hooks"
pacman_hook_dir="$output_dir/empty-pacman-hooks"
mkdir -p -- \
	"$rootfs/var/lib/pacman" \
	"$rootfs/var/cache/pacman/pkg" \
	"$rootfs/var/log" \
	"$iso_tree/boot/grub" \
	"$iso_tree/sp11" \
	"$tool_root" \
	"$firmware_extract" \
	"$hook_root/install" \
	"$hook_root/hooks" \
	"$pacman_hook_dir"

printf 'Verifying and installing the frozen live package closure ...\n'
package_files=()
while IFS=$'\t' read -r scope _repository package _pkgbase _version \
	_architecture filename expected_sha _compressed _installed _urls; do
	[[ "$scope" != "scope" ]] || continue
	[[ "$scope" == "live" || "$scope" == "live+build" ]] || continue
	package_file="$package_snapshot/packages/$filename"
	signature="$package_file.sig"
	[[ -f "$package_file" && -f "$signature" ]] || {
		printf 'Missing package or signature: %s\n' "$filename" >&2
		exit 1
	}
	[[ "$(sha256sum "$package_file" | awk '{print $1}')" == \
		"$expected_sha" ]] || {
		printf 'Package hash mismatch: %s\n' "$filename" >&2
		exit 1
	}
	pacman-key --verify "$signature" "$package_file" >/dev/null 2>&1
	package_files+=("$package_file")
done <"$repo_root/iso/packages.lock.tsv"
[[ "${#package_files[@]}" -eq 662 ]] || {
	printf 'Unexpected live package count: %s\n' "${#package_files[@]}" >&2
	exit 1
}

pacman \
	--disable-sandbox \
	--root "$rootfs" \
	--dbpath "$rootfs/var/lib/pacman" \
	--cachedir "$package_snapshot/packages" \
	--gpgdir /etc/pacman.d/gnupg \
	--logfile "$rootfs/var/log/pacman.log" \
	--config /etc/pacman.conf \
	--hookdir "$pacman_hook_dir" \
	--noconfirm \
	--noprogressbar \
	-U "${package_files[@]}"
systemd-tmpfiles --root="$rootfs" --create
journalctl --root="$rootfs" --update-catalog

printf 'Applying the explicit live-only SP11 overlay ...\n'
while IFS=$'\t' read -r source_relative destination; do
	[[ "$source_relative" != "source" ]] || continue
	source_file="$repo_root/$source_relative"
	[[ -f "$source_file" && ! -L "$source_file" ]] || {
		printf 'Missing live overlay source: %s\n' "$source_relative" >&2
		exit 1
	}
	source_mode="$(stat -c '%a' "$source_file")"
	install -D -m "$source_mode" "$source_file" \
		"$rootfs$destination"
done <"$repo_root/iso/live-rootfs-files.tsv"
rsync -a --chown=0:0 "$repo_root/iso/rootfs/" "$rootfs/"
chmod 0440 "$rootfs/etc/sudoers.d/10-sp11-live"

install -D -m0755 "$payload/sp11-iptsd" \
	"$rootfs/usr/local/libexec/sp11-iptsd"
install -D -m0755 "$payload/sp11-iptsd-check-device" \
	"$rootfs/usr/local/libexec/sp11-iptsd-check-device"
install -D -m0755 "$payload/power-profiles-daemon-sp11" \
	"$rootfs/usr/local/libexec/power-profiles-daemon-sp11"
mkdir -p -- "$rootfs/usr/lib/modules"
tar --zstd -xf "$payload/modules-$release.tar.zst" \
	-C "$rootfs/usr/lib/modules"
depmod -b "$rootfs" "$release"

printf 'Selecting only allowlisted firmware from verified packages ...\n'
while IFS=$'\t' read -r repository package _pkgbase _version \
	_architecture filename expected_sha _pkgbuild _source _identity; do
	[[ "$repository" != "repository" ]] || continue
	package_file="$firmware_cache/$filename"
	signature="$package_file.sig"
	[[ -f "$package_file" && -f "$signature" ]] || {
		printf 'Missing firmware package or signature: %s\n' "$filename" >&2
		exit 1
	}
	[[ "$(sha256sum "$package_file" | awk '{print $1}')" == \
		"$expected_sha" ]] || {
		printf 'Firmware package hash mismatch: %s\n' "$filename" >&2
		exit 1
	}
	pacman-key --verify "$signature" "$package_file" >/dev/null 2>&1
	mkdir -p -- "$firmware_extract/$package"
	bsdtar -xf "$package_file" -C "$firmware_extract/$package"
done <"$repo_root/firmware/packages.lock.tsv"

while IFS=$'\t' read -r path source_package _source_version size \
	expected_sha _license _purpose; do
	[[ "$path" != "path" ]] || continue
	source_file="$firmware_extract/$source_package/usr/lib/firmware/$path"
	[[ -f "$source_file" && ! -L "$source_file" ]] || {
		printf 'Allowlisted firmware missing from package: %s\n' "$path" >&2
		exit 1
	}
	[[ "$(stat -c '%s' "$source_file")" == "$size" &&
		"$(sha256sum "$source_file" | awk '{print $1}')" == \
		"$expected_sha" ]] || {
		printf 'Allowlisted firmware identity mismatch: %s\n' "$path" >&2
		exit 1
	}
	install -D -m0644 "$source_file" "$rootfs/usr/lib/firmware/$path"
done <"$repo_root/firmware/allowlist.tsv"

license_root="$rootfs/usr/share/licenses/sp11-firmware"
mkdir -p -- "$license_root"
for license_dir in \
	"$firmware_extract/linux-firmware-atheros/usr/share/licenses/linux-firmware-atheros" \
	"$firmware_extract/linux-firmware-qcom/usr/share/licenses/linux-firmware-qcom" \
	"$firmware_extract/linux-firmware-whence/usr/share/licenses/linux-firmware-whence" \
	"$firmware_extract/wireless-regdb/usr/share/licenses/wireless-regdb"; do
	[[ -d "$license_dir" ]] || {
		printf 'Missing firmware license directory: %s\n' "$license_dir" >&2
		exit 1
	}
	cp -a -- "$license_dir" "$license_root/"
done
install -m0644 \
	"$firmware_extract/linux-firmware-atheros/usr/lib/firmware/ath12k/WCN7850/hw2.0/Notice.txt" \
	"$license_root/WCN7850-Notice.txt"

actual_firmware="$output_dir/actual-firmware-paths.txt"
expected_firmware="$output_dir/expected-firmware-paths.txt"
find "$rootfs/usr/lib/firmware" -type f \
	-printf '%P\n' | LC_ALL=C sort >"$actual_firmware"
awk -F '\t' 'NR > 1 { print $1 }' \
	"$repo_root/firmware/allowlist.tsv" |
	LC_ALL=C sort >"$expected_firmware"
cmp -- "$expected_firmware" "$actual_firmware" || {
	printf 'Live root contains firmware outside the allowlist.\n' >&2
	exit 1
}

printf 'Creating the non-persistent live user and service policy ...\n'
systemd-sysusers --root="$rootfs"
chroot "$rootfs" /usr/bin/useradd \
	--create-home \
	--uid 1000 \
	--groups wheel,audio,video,input,storage \
	--shell /bin/bash \
	live
chroot "$rootfs" /usr/bin/passwd --delete live
chroot "$rootfs" /usr/bin/passwd --lock root

ln -sfn /run/systemd/resolve/stub-resolv.conf "$rootfs/etc/resolv.conf"
systemctl --root="$rootfs" set-default graphical.target
for unit in \
	gdm.service \
	NetworkManager.service \
	bluetooth.service \
	systemd-resolved.service \
	power-profiles-daemon.service \
	sp11-bluetooth-address.service \
	sp11-live-session.service \
	sp11-noidle.service \
	sp11-power-profile-cpufreq.service; do
	systemctl --root="$rootfs" enable "$unit"
done
for unit in \
	iio-sensor-proxy.service \
	sp11-sensors.service \
	sp11-ir-bridge.service; do
	systemctl --root="$rootfs" mask "$unit"
done

rm -f -- "$rootfs/etc/machine-id"
touch -d "@$source_date_epoch" "$rootfs/etc/machine-id"
if [[ -e "$rootfs/etc/brlapi.key" ]]; then
	rm -f -- "$rootfs/etc/brlapi.key"
fi
install -d -m0755 "$rootfs/usr/share/doc/sp11-beta"
for document in \
	README.md \
	RELEASE-NOTES.md \
	KNOWN-ISSUES.md \
	BINARY-RELEASE-HOLD.md \
	docs/BETA-ISO-ROADMAP.md \
	firmware/README.md; do
	install -m0644 "$repo_root/$document" \
		"$rootfs/usr/share/doc/sp11-beta/${document//\//-}"
done
{
	printf 'SP11_HELD_LIVE=1\n'
	printf 'SP11_KERNEL_RELEASE=%s\n' "$release"
	printf 'SP11_PACKAGE_LOCK_SHA256=%s\n' \
		"$(sha256sum "$repo_root/iso/packages.lock.tsv" | awk '{print $1}')"
	printf 'SP11_FIRMWARE_ALLOWLIST_SHA256=%s\n' \
		"$(sha256sum "$repo_root/firmware/allowlist.tsv" | awk '{print $1}')"
} >"$rootfs/etc/sp11-live-release"

find "$rootfs/var/cache/pacman/pkg" -mindepth 1 -delete
find "$rootfs/tmp" "$rootfs/var/tmp" -mindepth 1 -delete
: >"$rootfs/var/log/pacman.log"
find "$rootfs" -xdev -exec touch -h -d "@$source_date_epoch" {} +

printf 'Building the dedicated live initramfs ...\n'
for install_hook in /usr/lib/initcpio/install/*; do
	ln -s "$install_hook" "$hook_root/install/$(basename "$install_hook")"
done
for runtime_hook in /usr/lib/initcpio/hooks/*; do
	ln -s "$runtime_hook" "$hook_root/hooks/$(basename "$runtime_hook")"
done
install -m0755 "$repo_root/iso/mkinitcpio/install/sp11live" \
	"$hook_root/install/sp11live"
install -m0755 "$repo_root/iso/mkinitcpio/hooks/sp11live" \
	"$hook_root/hooks/sp11live"
mkinitcpio \
	-r "$rootfs" \
	-D "$hook_root" \
	-c "$repo_root/iso/mkinitcpio.conf" \
	-k "$release" \
	-g "$iso_tree/sp11/initramfs-$release-live.img"
chmod 0644 "$iso_tree/sp11/initramfs-$release-live.img"

install -m0644 "$payload/Image-$release" \
	"$iso_tree/sp11/Image-$release"
install -m0644 "$payload/x1e80100-microsoft-denali-oled.dtb" \
	"$iso_tree/sp11/x1e80100-microsoft-denali-oled.dtb"
install -m0644 "$repo_root/iso/grub.cfg" \
	"$iso_tree/boot/grub/grub.cfg"

printf 'Extracting the frozen image-construction tools ...\n'
for tool_package in squashfs-tools libburn libisofs libisoburn mtools; do
	tool_filename="$(
		awk -F '\t' -v package="$tool_package" \
			'NR > 1 && $3 == package { print $7; exit }' \
			"$repo_root/iso/packages.lock.tsv"
	)"
	[[ -n "$tool_filename" ]] || {
		printf 'Build tool is not locked: %s\n' "$tool_package" >&2
		exit 1
	}
	bsdtar -xf "$package_snapshot/packages/$tool_filename" -C "$tool_root"
done
mksquashfs="$tool_root/usr/bin/mksquashfs"
xorriso="$tool_root/usr/bin/xorriso"
mcopy="$tool_root/usr/bin/mcopy"
mmd="$tool_root/usr/bin/mmd"
for tool_binary in "$mksquashfs" "$xorriso" "$mcopy" "$mmd"; do
	[[ -x "$tool_binary" ]] || {
		printf 'Missing extracted build tool: %s\n' "$tool_binary" >&2
		exit 1
	}
done

printf 'Compressing the live root filesystem ...\n'
"$mksquashfs" "$rootfs" "$iso_tree/sp11/rootfs.sfs" \
	-noappend \
	-all-root \
	-comp gzip \
	-Xcompression-level 9 \
	-mkfs-time "$source_date_epoch"

printf 'Building the removable ARM64 UEFI loader ...\n'
grub_efi="$output_dir/BOOTAA64.EFI"
grub-mkstandalone \
	--format=arm64-efi \
	--output="$grub_efi" \
	--locales="" \
	--fonts="" \
	--modules="part_gpt fat iso9660 normal linux fdt search search_label configfile all_video gfxterm echo test" \
	"boot/grub/grub.cfg=$repo_root/iso/grub-embedded.cfg"
install -D -m0644 "$grub_efi" \
	"$iso_tree/EFI/BOOT/BOOTAA64.EFI"

efi_image="$output_dir/sp11-efiboot.img"
truncate -s 64M "$efi_image"
mkfs.fat -F32 -n SP11EFI "$efi_image"
MTOOLS_SKIP_CHECK=1 "$mmd" -i "$efi_image" ::/EFI ::/EFI/BOOT
MTOOLS_SKIP_CHECK=1 "$mcopy" -i "$efi_image" \
	"$grub_efi" ::/EFI/BOOT/BOOTAA64.EFI

printf 'Creating the held hybrid ISO ...\n'
iso_output="$output_dir/sp11-beta-review20-aarch64-HELD-local.iso"
LD_LIBRARY_PATH="$tool_root/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
	"$xorriso" -as mkisofs \
	-iso-level 3 \
	-full-iso9660-filenames \
	-rational-rock \
	-volid "$volume_id" \
	-appid "SP11 beta held engineering image" \
	-partition_offset 16 \
	-append_partition 2 0xef "$efi_image" \
	-appended_part_as_gpt \
	-e --interval:appended_partition_2:all:: \
	-no-emul-boot \
	-output "$iso_output" \
	"$iso_tree"

{
	printf 'artifact\tsha256\tbytes\n'
	for artifact in \
		"$iso_tree/sp11/rootfs.sfs" \
		"$iso_tree/sp11/initramfs-$release-live.img" \
		"$grub_efi" \
		"$efi_image" \
		"$iso_output"; do
		printf '%s\t%s\t%s\n' \
			"$(basename "$artifact")" \
			"$(sha256sum "$artifact" | awk '{print $1}')" \
			"$(stat -c '%s' "$artifact")"
	done
} >"$output_dir/ARTIFACTS.tsv"

printf '%s\n' \
	'HELD: no distribution-package source closure, installer, or release authorization.' \
	>"$output_dir/HOLD-REASONS"
find "$output_dir" -type f -exec touch -d "@$source_date_epoch" {} +

"$script_dir/audit-held-live-image.sh" "$output_dir"

printf '\nHeld live image: %s\n' "$iso_output"
printf 'Artifact manifest: %s\n' "$output_dir/ARTIFACTS.tsv"
sha256sum "$iso_output"
