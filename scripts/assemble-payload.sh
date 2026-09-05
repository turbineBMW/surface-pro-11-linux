#!/bin/bash

# Maintainer helper: assemble the exact AArch64 beta payload (7.3 port kernel)
# from audited kernel staging and qualified userspace binaries. This
# intentionally excludes firmware and initramfs.

set -euo pipefail

release="7.2.0-sp11-73beta1"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
output_dir="$repo_root/work/payload"
local_staging=0

usage() {
	cat <<EOF
Usage: $0 [--output DIRECTORY] [--local-staging]

Required environment:
  SP11_KERNEL_STAGE       Audited modules_install staging root

Optional environment:
  SP11_USERSPACE_BIN_DIR  Qualified binary directory
                           (default: /usr/local/libexec)

While BINARY-RELEASE-HOLD.md exists, --local-staging is required. Output is
restricted to this repository's work/ directory and marked not for release.
EOF
}

while (($#)); do
	case "$1" in
	--output)
		[[ $# -ge 2 ]] || {
			usage >&2
			exit 2
		}
		output_dir="$2"
		shift 2
		;;
	--local-staging)
		local_staging=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		printf 'Unknown argument: %s\n' "$1" >&2
		usage >&2
		exit 2
		;;
	esac
done

hold_active=0
if [[ -e "$repo_root/BINARY-RELEASE-HOLD.md" ]]; then
	hold_active=1
	if ((local_staging == 0)); then
		printf 'Refusing release assembly: binary/ISO release hold is active.\n' >&2
		printf 'Use --local-staging only for held engineering output.\n' >&2
		exit 1
	fi
fi

expected_image="a2118d41b4edb8f6b11c050d9ca2c6208e30da1472f4f198959f0f0b44fb8bde"
expected_dtb="54a14d4f6841740e9a911affc58e2b17f097fb900d38472fd0386be311b6cead"
expected_iptsd="45ce0fcabdda04a9fcf3ce30f7f0c64ba7098fd2351127ef0e54cf0ac0b3f083"
expected_checker="54fcdaef90b0bd4239df670865cf8b258c3ae6e3988e42b0b9a3b58aaa4b08f5"
expected_ppd="9e1d72935f2b916de1c44950e425948e60c7bdf83c69bede2a079e7a79a82252"
expected_videocc="ae08b71931935955332d3f80e060edde37d1f8084b4011442394c60d3cd47b5b"
expected_module_count=3767
source_date_epoch=1788637836

mkdir -p -- "$repo_root/work"
output_dir="$(realpath -m -- "$output_dir")"
case "$output_dir" in
	"$repo_root/work"/*) ;;
	*)
		printf 'Refusing output outside %s/work: %s\n' "$repo_root" "$output_dir" >&2
		exit 1
		;;
esac
if [[ -e "$output_dir" ]]; then
	printf 'Refusing to replace existing output: %s\n' "$output_dir" >&2
	exit 1
fi

kernel_stage="${SP11_KERNEL_STAGE:-}"
if [[ -z "$kernel_stage" ]]; then
	printf 'SP11_KERNEL_STAGE is required.\n' >&2
	exit 1
fi
kernel_stage="$(realpath -e -- "$kernel_stage")"
stage_boot="$kernel_stage/boot"
stage_modules="$kernel_stage/lib/modules/$release"
userspace_bin_dir="$(realpath -e -- "${SP11_USERSPACE_BIN_DIR:-/usr/local/libexec}")"

image="$stage_boot/Image-$release"
dtb="$stage_boot/x1e80100-microsoft-denali-oled.dtb"
videocc="$stage_modules/kernel/drivers/clk/qcom/videocc-sm8550.ko"
iptsd="$userspace_bin_dir/sp11-iptsd"
checker="$userspace_bin_dir/sp11-iptsd-check-device"
ppd="$userspace_bin_dir/power-profiles-daemon-sp11"

for required in "$image" "$dtb" "$videocc" "$iptsd" "$checker" "$ppd"; do
	[[ -f "$required" && ! -L "$required" ]] || {
		printf 'Missing or unsafe payload input: %s\n' "$required" >&2
		exit 1
	}
done

[[ "$(sha256sum "$image" | awk '{print $1}')" == "$expected_image" ]]
[[ "$(sha256sum "$dtb" | awk '{print $1}')" == "$expected_dtb" ]]
[[ "$(sha256sum "$videocc" | awk '{print $1}')" == "$expected_videocc" ]]
[[ "$(sha256sum "$iptsd" | awk '{print $1}')" == "$expected_iptsd" ]]
[[ "$(sha256sum "$checker" | awk '{print $1}')" == "$expected_checker" ]]
[[ "$(sha256sum "$ppd" | awk '{print $1}')" == "$expected_ppd" ]]

module_count="$(find "$stage_modules" -type f -name '*.ko' -printf . | wc -c)"
[[ "$module_count" -eq "$expected_module_count" ]] || {
	printf 'Unexpected module count: %s (expected %s)\n' \
		"$module_count" "$expected_module_count" >&2
	exit 1
}
if find "$stage_modules" -type l -print -quit | grep -q .; then
	printf 'Refusing module stage containing symlinks.\n' >&2
	exit 1
fi
if find "$stage_modules" ! -type d ! -type f -print -quit | grep -q .; then
	printf 'Refusing module stage containing special files.\n' >&2
	exit 1
fi

mkdir -p -- "$output_dir"

install -m0644 "$image" "$output_dir/Image-$release"
install -m0644 "$dtb" "$output_dir/x1e80100-microsoft-denali-oled.dtb"
install -m0755 "$iptsd" "$output_dir/sp11-iptsd"
install -m0755 "$checker" "$output_dir/sp11-iptsd-check-device"
install -m0755 "$ppd" "$output_dir/power-profiles-daemon-sp11"
install -m0644 "$repo_root/kernel/port-7.3/BUILDINFO" "$output_dir/BUILDINFO"

{
	printf 'path\tbytes\tsha256\n'
	while IFS= read -r -d '' module_file; do
		printf '%s\t%s\t%s\n' \
			"${module_file#"$stage_modules/"}" \
			"$(stat -c '%s' "$module_file")" \
			"$(sha256sum "$module_file" | awk '{print $1}')"
	done < <(
		find "$stage_modules" -type f -name '*.ko' -print0 |
			LC_ALL=C sort -z
	)
} >"$output_dir/MODULES.tsv"
[[ "$(awk 'NR > 1 { count++ } END { print count + 0 }' \
	"$output_dir/MODULES.tsv")" -eq "$expected_module_count" ]] || {
	printf 'Unexpected module-manifest count.\n' >&2
	exit 1
}

if ((hold_active == 1)); then
	printf '%s\n' \
		'BINARY/ISO RELEASE HOLD ACTIVE — LOCAL ENGINEERING STAGING ONLY' \
		>"$output_dir/LOCAL-STAGING-NOT-FOR-RELEASE"
fi

tar --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 \
	--numeric-owner --format=posix \
	--pax-option=delete=atime,delete=ctime \
	--zstd -cf "$output_dir/modules-$release.tar.zst" \
	-C "$kernel_stage/lib/modules" "$release"

(
	cd -- "$output_dir"
	mapfile -t checksum_files < <(
		find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' |
			LC_ALL=C sort
	)
	sha256sum "${checksum_files[@]}" >SHA256SUMS
)

archive="$output_dir.tar.zst"
if [[ -e "$archive" ]]; then
	printf 'Refusing to replace existing archive: %s\n' "$archive" >&2
	exit 1
fi
tar --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 \
	--numeric-owner --format=posix \
	--pax-option=delete=atime,delete=ctime \
	--zstd -cf "$archive" -C "$output_dir" .
printf 'Payload: %s\n' "$output_dir"
printf 'Archive: %s\n' "$archive"
sha256sum "$archive"
