#!/bin/bash

# Maintainer helper: assemble the exact review20 AArch64 beta candidate payload
# from the test machine. This intentionally excludes firmware and initramfs.

set -euo pipefail

release="7.1.3-sp11-suspend-review20"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
output_dir="${1:-$repo_root/work/payload}"

if [[ -e "$repo_root/BINARY-RELEASE-HOLD.md" ]]; then
	printf 'Refusing release assembly: binary/ISO release hold is active.\n' >&2
	printf 'See %s/BINARY-RELEASE-HOLD.md and docs/REDISTRIBUTION-REVIEW.md.\n' \
		"$repo_root" >&2
	exit 1
fi

expected_image="b3ca9ba56570ff1bf8217a866563f1e9788c5dfdc3a153a9b673e3b6e9624ed5"
expected_dtb="5e9009f5bd96a760a33086d1a8842e3228e3d28c413f96d70aca4914f7e397ed"
expected_iptsd="45ce0fcabdda04a9fcf3ce30f7f0c64ba7098fd2351127ef0e54cf0ac0b3f083"
expected_checker="54fcdaef90b0bd4239df670865cf8b258c3ae6e3988e42b0b9a3b58aaa4b08f5"
expected_ppd="9e1d72935f2b916de1c44950e425948e60c7bdf83c69bede2a079e7a79a82252"

mkdir -p -- "$repo_root/work"
output_dir="$(realpath -m -- "$output_dir")"
case "$output_dir" in
	"$repo_root/work"/*) ;;
	*)
		printf 'Refusing output outside %s/work: %s\n' "$repo_root" "$output_dir" >&2
		exit 1
		;;
esac
rm -rf -- "$output_dir"
mkdir -p -- "$output_dir"

qualified_boot_dir="${SP11_QUALIFIED_BOOT_DIR:-/boot/sp11-suspend-review20-20260726}"

install -m0644 "$qualified_boot_dir/Image-$release" \
	"$output_dir/Image-$release"
install -m0644 "$qualified_boot_dir/x1e80100-microsoft-denali-oled.dtb" \
	"$output_dir/x1e80100-microsoft-denali-oled.dtb"
install -m0755 /usr/local/libexec/sp11-iptsd "$output_dir/sp11-iptsd"
install -m0755 /usr/local/libexec/sp11-iptsd-check-device \
	"$output_dir/sp11-iptsd-check-device"
install -m0755 /usr/local/libexec/power-profiles-daemon-sp11 \
	"$output_dir/power-profiles-daemon-sp11"

[[ "$(sha256sum "$output_dir/Image-$release" | awk '{print $1}')" == "$expected_image" ]]
[[ "$(sha256sum "$output_dir/x1e80100-microsoft-denali-oled.dtb" | awk '{print $1}')" == "$expected_dtb" ]]
[[ "$(sha256sum "$output_dir/sp11-iptsd" | awk '{print $1}')" == "$expected_iptsd" ]]
[[ "$(sha256sum "$output_dir/sp11-iptsd-check-device" | awk '{print $1}')" == "$expected_checker" ]]
[[ "$(sha256sum "$output_dir/power-profiles-daemon-sp11" | awk '{print $1}')" == "$expected_ppd" ]]

tar --zstd -cf "$output_dir/modules-$release.tar.zst" \
	--exclude="$release/build" \
	-C /usr/lib/modules "$release"

(
	cd -- "$output_dir"
	sha256sum \
		"Image-$release" \
		x1e80100-microsoft-denali-oled.dtb \
		"modules-$release.tar.zst" \
		sp11-iptsd \
		sp11-iptsd-check-device \
		power-profiles-daemon-sp11 >SHA256SUMS
)

archive="$(dirname -- "$output_dir")/sp11-beta-review20-aarch64-payload.tar.zst"
tar --zstd -cf "$archive" -C "$output_dir" .
printf 'Payload: %s\n' "$output_dir"
printf 'Archive: %s\n' "$archive"
sha256sum "$archive"
