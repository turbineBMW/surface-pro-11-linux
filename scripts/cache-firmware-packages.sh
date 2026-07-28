#!/bin/bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
package_lock="$repo_root/firmware/packages.lock.tsv"
output_dir="$repo_root/work/firmware-package-cache-20260622"
mirror="https://ca.us.mirror.archlinuxarm.org"
local_staging=0

usage() {
	cat <<EOF
Usage: $0 --local-staging [--output DIRECTORY]

Cache and verify the exact signed packages that contain the firmware
allowlist. Output is restricted to work/ while the binary/ISO hold is active.
EOF
}

while (($#)); do
	case "$1" in
	--local-staging)
		local_staging=1
		shift
		;;
	--output)
		[[ $# -ge 2 ]] || {
			usage >&2
			exit 2
		}
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

if [[ -e "$repo_root/BINARY-RELEASE-HOLD.md" && "$local_staging" -ne 1 ]]; then
	printf 'Refusing firmware package output: binary/ISO hold is active.\n' >&2
	exit 1
fi

mkdir -p -- "$repo_root/work"
output_dir="$(realpath -m -- "$output_dir")"
case "$output_dir" in
"$repo_root/work"/*) ;;
*)
	printf 'Refusing output outside %s/work: %s\n' \
		"$repo_root" "$output_dir" >&2
	exit 1
	;;
esac
mkdir -p -- "$output_dir"
find "$output_dir" -maxdepth 1 -type f -name '*.part' -delete

for command_name in curl pacman-key sha256sum; do
	command -v "$command_name" >/dev/null || {
		printf 'Missing command: %s\n' "$command_name" >&2
		exit 1
	}
done

while IFS=$'\t' read -r repository _package _pkgbase _version \
	_architecture filename expected_sha _pkgbuild_sha _source _identity; do
	[[ "$repository" != "repository" ]] || continue
	target="$output_dir/$filename"
	signature="$target.sig"
	url="$mirror/aarch64/$repository/$filename"

	if [[ ! -f "$target" ]]; then
		curl --fail --show-error --location --retry 3 \
			--output "$target.part" "$url"
		mv -- "$target.part" "$target"
	fi
	actual_sha="$(sha256sum "$target" | awk '{print $1}')"
	[[ "$actual_sha" == "$expected_sha" ]] || {
		printf 'Firmware package hash mismatch: %s\n' "$filename" >&2
		exit 1
	}

	if [[ ! -f "$signature" ]]; then
		curl --fail --show-error --location --retry 3 \
			--output "$signature.part" "$url.sig"
		mv -- "$signature.part" "$signature"
	fi
	pacman-key --verify "$signature" "$target" >/dev/null
	printf 'Verified %s\n' "$filename"
done <"$package_lock"

printf '%s\n' \
	'BINARY/ISO RELEASE HOLD ACTIVE — LOCAL ENGINEERING STAGING ONLY' \
	>"$output_dir/LOCAL-STAGING-NOT-FOR-RELEASE"
checksum_temp="$(mktemp /tmp/sp11-firmware-checksums.XXXXXX)"
trap 'rm -f -- "$checksum_temp"' EXIT
(
	cd -- "$output_dir"
	find . -maxdepth 1 -type f \
		! -name SHA256SUMS -printf '%P\n' |
		LC_ALL=C sort |
		xargs -r sha256sum >"$checksum_temp"
)
mv -- "$checksum_temp" "$output_dir/SHA256SUMS"
trap - EXIT
printf 'Firmware package cache: %s\n' "$output_dir"
