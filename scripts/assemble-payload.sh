#!/bin/bash

# Maintainer helper: assemble the exact sanitized AArch64 candidate payload
# from the test machine. This intentionally excludes firmware and initramfs.

set -euo pipefail

release="7.1.3-sp11-sanitized2"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
output_dir="${1:-$repo_root/work/payload}"

if [[ -e "$repo_root/BINARY-RELEASE-HOLD.md" ]]; then
	printf 'Refusing release assembly: binary/ISO release hold is active.\n' >&2
	printf 'See %s/BINARY-RELEASE-HOLD.md and docs/REDISTRIBUTION-REVIEW.md.\n' \
		"$repo_root" >&2
	exit 1
fi

expected_image="d95b1cbba0e017f2430e65ce6ca5e3e276ef3d0dbcab7f68e999db2dd4143152"
expected_dtb="3de1d2e6b0d40fef35866ef6e024cb5164f30f1e44f0c0d0051cc7cf9a384ede"
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

install -m0644 "/boot/sp11-alpha/Image-$release" \
	"$output_dir/Image-$release"
install -m0644 /boot/sp11-alpha/x1e80100-microsoft-denali-oled.dtb \
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

archive="$(dirname -- "$output_dir")/sp11-field-test-alpha-aarch64-payload.tar.zst"
tar --zstd -cf "$archive" -C "$output_dir" .
printf 'Payload: %s\n' "$output_dir"
printf 'Archive: %s\n' "$archive"
sha256sum "$archive"
