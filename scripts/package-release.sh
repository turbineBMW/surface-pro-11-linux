#!/bin/bash
# SPDX-License-Identifier: MIT
#
# Turn an audited live-image build directory into the files that get attached
# to a GitHub release: a clean ISO name, SHA256SUMS, and (because GitHub caps
# release assets at 2 GiB) split parts when the ISO is larger than that.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
build_dir="${1:-}"
date_tag="${2:-$(date -u +%Y%m%d)}"
part_size="${SP11_RELEASE_PART_SIZE:-1900M}"

usage() {
	printf 'Usage: %s BUILD-DIRECTORY [DATE-TAG]\n' "$0"
	printf 'Example: %s work/live-image-beta-20260828 20260828\n' "$0"
}

[[ -n "$build_dir" ]] || {
	usage >&2
	exit 2
}
build_dir="$(realpath -e -- "$build_dir")"
iso_source="$build_dir/sp11-beta-review20-aarch64-HELD-local.iso"
[[ -f "$iso_source" && -f "$build_dir/ARTIFACTS.tsv" ]] || {
	printf 'Not an audited build directory: %s\n' "$build_dir" >&2
	exit 1
}
release_name="sp11-linux-beta-$date_tag-aarch64"
release_dir="$repo_root/work/release-$date_tag"
[[ ! -e "$release_dir" ]] || {
	printf 'Refusing to replace existing release directory: %s\n' "$release_dir" >&2
	exit 1
}
mkdir -p -- "$release_dir"

printf 'Copying ISO ...\n'
cp --reflink=auto -- "$iso_source" "$release_dir/$release_name.iso"
iso_bytes="$(stat -c '%s' "$release_dir/$release_name.iso")"
cp -- "$build_dir/ARTIFACTS.tsv" "$release_dir/BUILD-ARTIFACTS.tsv"

(
	cd -- "$release_dir"
	if ((iso_bytes > 2147483648)); then
		printf 'ISO is %s bytes (> 2 GiB): splitting into %s parts ...\n' \
			"$iso_bytes" "$part_size"
		split --bytes="$part_size" --suffix-length=2 \
			-- "$release_name.iso" "$release_name.iso.part-"
	fi
	sha256sum -- "$release_name.iso" "$release_name.iso.part-"* 2>/dev/null >SHA256SUMS ||
		sha256sum -- "$release_name.iso" >SHA256SUMS
	cat >README.txt <<EOF
Surface Pro 11 Linux beta $date_tag (aarch64)

Files:
  $release_name.iso            hybrid UEFI ISO, write it to a whole USB stick
  $release_name.iso.part-*     the same ISO split for GitHub's 2 GiB limit (if present)
  SHA256SUMS                    checksums of everything above

Join the parts (if you downloaded them) and verify:
  cat $release_name.iso.part-* > $release_name.iso
  sha256sum -c SHA256SUMS

Then read docs/GETTING-STARTED.md in the repository (also on the USB stick's
SP11FW partition after writing the image).
EOF
)
printf '\nRelease files in %s:\n' "$release_dir"
ls -la -- "$release_dir"
