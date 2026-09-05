#!/bin/bash

# Reproducible kernel build for the SP11 project. Two profiles are kept:
#
#   port-7.3  (default) the Linux 7.3 forward port shipped by the current beta
#   review20  the original 7.1.3 review20 kernel of the 2026-08-28 beta
#
# Each profile pins the exact source commit and tree, the merged configuration
# hash, the compiler family and the Python inputs, so a build in a different
# directory or on a different day produces byte-identical Image, DTB,
# Module.symvers and modules when the declared toolchain matches.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"

usage() {
	printf 'Usage: %s [--profile port-7.3|review20] --source LINUX_TREE --output BUILD_DIR [--jobs N]\n' "$0"
}

profile="port-7.3"
source_tree=""
output_dir=""
jobs="$(nproc)"

while (($#)); do
	case "$1" in
		--profile) profile="$2"; shift 2 ;;
		--source) source_tree="$2"; shift 2 ;;
		--output) output_dir="$2"; shift 2 ;;
		--jobs) jobs="$2"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done

case "$profile" in
	port-7.3)
		release="7.2.0-sp11-73beta1"
		expected_commit="1cd9ebdd1584403e14408de1c559883acf064cc6"
		expected_tree="1f776364a949e575bfdc72ad1b8c92a7d7f97b30"
		expected_config="7798b8bebf2d286c0dfea770d357ceea7ff3b6e55c14bcb70cf5dfad6dc2d011"
		expected_python="Python 3.14.7"
		expected_lxml="6.1.3"
		expected_cc="gcc (GCC) 16.1.1 20260430"
		toolchain=()
		config_mode="full"
		config_files=("$repo_root/kernel/port-7.3/config")
		;;
	review20)
		release="7.1.3-sp11-suspend-review20"
		expected_commit="18d7951a10dc49e383d16c6af82fc2c07784de3d"
		expected_tree="b820f10abba096e23a28506d7ad591dffdedf1a8"
		expected_config="c68c4b072713503c8282cb09ff8f05aa4876966503c65331732bfe0775196c52"
		expected_python="Python 3.14.6"
		expected_lxml="6.1.1"
		expected_cc="clang version 22.1.8"
		toolchain=(LLVM=1)
		config_mode="merge"
		config_files=("$repo_root/kernel/config" "$repo_root/kernel/camera-review.config.fragment")
		;;
	*)
		printf 'Unknown profile: %s\n' "$profile" >&2
		exit 2
		;;
esac
python3_make_command="python3"

[[ -n "$source_tree" && -n "$output_dir" ]] || { usage >&2; exit 2; }
source_tree="$(cd -- "$source_tree" && pwd -P)"
mkdir -p -- "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd -P)"

actual_commit="$(git -C "$source_tree" rev-parse 'HEAD^{commit}')"
actual_tree="$(git -C "$source_tree" rev-parse 'HEAD^{tree}')"
[[ "$actual_commit" == "$expected_commit" ]] || {
	printf 'Wrong kernel commit: %s\n' "$actual_commit" >&2
	exit 1
}
[[ "$actual_tree" == "$expected_tree" ]] || {
	printf 'Wrong kernel tree: %s\n' "$actual_tree" >&2
	exit 1
}
[[ -z "$(git -C "$source_tree" status --porcelain --untracked-files=no)" ]] || {
	printf 'Kernel source has tracked modifications\n' >&2
	exit 1
}
actual_python="$(python3 -S --version 2>&1)"
[[ "$actual_python" == "$expected_python" ]] || {
	printf 'Unexpected Python version: %s\n' "$actual_python" >&2
	exit 1
}
actual_lxml="$(python3 -c 'import lxml; print(lxml.__version__)')"
[[ "$actual_lxml" == "$expected_lxml" ]] || {
	printf 'Unexpected Python lxml version: %s\n' "$actual_lxml" >&2
	exit 1
}
if ((${#toolchain[@]})); then
	actual_cc="$(clang --version | head -n1)"
else
	actual_cc="$(gcc --version | head -n1)"
fi
[[ "$actual_cc" == "$expected_cc" ]] || {
	printf 'Unexpected compiler: %s (expected %s)\n' "$actual_cc" "$expected_cc" >&2
	exit 1
}

# Keep release artifacts independent of the local account, hostname, wall
# clock, and output directory. The source commit time is stable and auditable.
source_epoch="$(git -C "$source_tree" show -s --format=%ct "$expected_commit")"
build_timestamp="$(date --utc --date="@$source_epoch" '+%Y-%m-%dT%H:%M:%SZ')"
export LC_ALL=C
export TZ=UTC
export SOURCE_DATE_EPOCH="$source_epoch"
export KBUILD_BUILD_TIMESTAMP="$build_timestamp"
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_USER=sp11
export KBUILD_BUILD_HOST=reproducible

printf 'Profile %s: release %s\n' "$profile" "$release"
printf 'Reproducible build identity: %s@%s #%s %s (SOURCE_DATE_EPOCH=%s)\n' \
	"$KBUILD_BUILD_USER" "$KBUILD_BUILD_HOST" "$KBUILD_BUILD_VERSION" \
	"$KBUILD_BUILD_TIMESTAMP" "$SOURCE_DATE_EPOCH"

make_args=(-C "$source_tree" O="$output_dir" KERNELRELEASE="$release"
	LOCALVERSION= "${toolchain[@]}" PYTHON3="$python3_make_command")

case "$config_mode" in
	merge)
		"$source_tree/scripts/kconfig/merge_config.sh" -m -O "$output_dir" "${config_files[@]}"
		;;
	full)
		install -m0644 "${config_files[0]}" "$output_dir/.config"
		;;
esac
make "${make_args[@]}" olddefconfig
actual_config="$(sha256sum "$output_dir/.config" | awk '{print $1}')"
[[ "$actual_config" == "$expected_config" ]] || {
	printf 'Unexpected merged config hash: %s\n' "$actual_config" >&2
	exit 1
}
make "${make_args[@]}" W=1 KALLSYMS_EXTRA_PASS=1 -j"$jobs" Image modules dtbs

actual_release="$(make -s "${make_args[@]}" kernelrelease)"
[[ "$actual_release" == "$release" ]] || {
	printf 'Unexpected kernel release: %s\n' "$actual_release" >&2
	exit 1
}

sha256sum \
	"$output_dir/.config" \
	"$output_dir/Module.symvers" \
	"$output_dir/arch/arm64/boot/Image" \
	"$output_dir/arch/arm64/boot/dts/qcom/x1e80100-microsoft-denali-oled.dtb"
