#!/bin/bash

# Require two independently built installed-root artifacts to be byte-identical.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
first="${1:-}"
second="${2:-}"

[[ $EUID -eq 0 ]] || {
	printf 'Run with sudo/root so both complete staged roots can be audited.\n' \
		>&2
	exit 1
}
[[ -n "$first" && -n "$second" ]] || {
	printf 'Usage: %s FIRST_ARTIFACT_DIRECTORY SECOND_ARTIFACT_DIRECTORY\n' \
		"$0" >&2
	exit 2
}
first="$(realpath -e -- "$first")"
second="$(realpath -e -- "$second")"
for artifact_dir in "$first" "$second"; do
	case "$artifact_dir" in
	"$repo_root/work"/installed-rootfs-*) ;;
	*)
		printf 'Refusing artifact outside the installed-rootfs work namespace.\n' \
			>&2
		exit 1
		;;
	esac
done
[[ "$first" != "$second" ]] || {
	printf 'Reproducibility requires two distinct artifact directories.\n' >&2
	exit 1
}

"$script_dir/audit-installed-rootfs.sh" "$first"
"$script_dir/audit-installed-rootfs.sh" "$second"

for relative in \
	ROOTFS-FILES.tsv \
	BOOT-PAYLOAD.tsv \
	ARTIFACTS.tsv \
	sp11-installed-rootfs.tar.zst \
	boot/Image-7.2.0-sp11-73beta1 \
	boot/x1e80100-microsoft-denali-oled.dtb; do
	cmp -- "$first/$relative" "$second/$relative" || {
		printf 'Installed-root reproducibility mismatch: %s\n' \
			"$relative" >&2
		exit 1
	}
done

archive="$first/sp11-installed-rootfs.tar.zst"
printf 'Installed-root clean-build reproducibility gate passed.\n'
printf 'Archive bytes: %s\n' "$(stat -c '%s' "$archive")"
printf 'Archive SHA-256: %s\n' \
	"$(sha256sum "$archive" | awk '{print $1}')"
printf 'Rootfs manifest SHA-256: %s\n' \
	"$(sha256sum "$first/ROOTFS-FILES.tsv" | awk '{print $1}')"
printf 'Boot manifest SHA-256: %s\n' \
	"$(sha256sum "$first/BOOT-PAYLOAD.tsv" | awk '{print $1}')"
