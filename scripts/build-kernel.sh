#!/bin/bash

set -euo pipefail

release="7.1.3-sp11-camera-review7"
expected_commit="2651afaca79b7e0e3a31d70eb21a6a000e172cf1"
expected_tree="2b70e7f701f7906db855ad27e527fc8fff891870"
expected_config="b2497f1a5340c6491dd86014d90a9cdd6dcf0a8b1f45806ceb76be35d972517f"
expected_python="Python 3.14.6"
python3_make_command="python3 -S"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"

usage() {
	printf 'Usage: %s --source LINUX_TREE --output BUILD_DIR [--jobs N]\n' "$0"
}

source_tree=""
output_dir=""
jobs="$(nproc)"

while (($#)); do
	case "$1" in
		--source) source_tree="$2"; shift 2 ;;
		--output) output_dir="$2"; shift 2 ;;
		--jobs) jobs="$2"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done

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

printf 'Reproducible build identity: %s@%s #%s %s (SOURCE_DATE_EPOCH=%s)\n' \
	"$KBUILD_BUILD_USER" "$KBUILD_BUILD_HOST" "$KBUILD_BUILD_VERSION" \
	"$KBUILD_BUILD_TIMESTAMP" "$SOURCE_DATE_EPOCH"

"$source_tree/scripts/kconfig/merge_config.sh" -m -O "$output_dir" \
	"$repo_root/kernel/config" \
	"$repo_root/kernel/camera-review.config.fragment"
make -C "$source_tree" O="$output_dir" KERNELRELEASE="$release" \
	LOCALVERSION= LLVM=1 PYTHON3="$python3_make_command" olddefconfig
actual_config="$(sha256sum "$output_dir/.config" | awk '{print $1}')"
[[ "$actual_config" == "$expected_config" ]] || {
	printf 'Unexpected merged config hash: %s\n' "$actual_config" >&2
	exit 1
}
make -C "$source_tree" O="$output_dir" KERNELRELEASE="$release" \
	LOCALVERSION= LLVM=1 PYTHON3="$python3_make_command" W=1 \
	KALLSYMS_EXTRA_PASS=1 \
	-j"$jobs" Image modules dtbs

actual_release="$(make -s -C "$source_tree" O="$output_dir" \
	KERNELRELEASE="$release" LOCALVERSION= LLVM=1 \
	PYTHON3="$python3_make_command" kernelrelease)"
[[ "$actual_release" == "$release" ]] || {
	printf 'Unexpected kernel release: %s\n' "$actual_release" >&2
	exit 1
}

sha256sum \
	"$output_dir/.config" \
	"$output_dir/Module.symvers" \
	"$output_dir/arch/arm64/boot/Image" \
	"$output_dir/arch/arm64/boot/dts/qcom/x1e80100-microsoft-denali-oled.dtb"
