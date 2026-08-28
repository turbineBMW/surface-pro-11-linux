#!/bin/bash

# Finalize a fully prepared installed root into a deterministic held artifact.
# This helper refuses incomplete, changed, or previously finalized trees.

set -euo pipefail

release="7.1.3-sp11-suspend-review20"
source_date_epoch=1785076525
expected_image="918ed2560654355555535290fd0d9657e1afc7022b3e46cc8396155d3575f256"
expected_dtb="5e9009f5bd96a760a33086d1a8842e3228e3d28c413f96d70aca4914f7e397ed"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
output_dir="${1:-}"

[[ $EUID -eq 0 ]] || {
	printf 'Run with sudo/root.\n' >&2
	exit 1
}
[[ -n "$output_dir" ]] || {
	printf 'Usage: sudo %s ARTIFACT_DIRECTORY\n' "$0" >&2
	exit 2
}
output_dir="$(realpath -e -- "$output_dir")"
case "$output_dir" in
"$repo_root/work"/installed-rootfs-*) ;;
*)
	printf 'Refusing output outside the installed-rootfs work namespace.\n' >&2
	exit 1
	;;
esac
grep -Fxq \
	'BINARY/ISO RELEASE HOLD ACTIVE — LOCAL ENGINEERING ARTIFACT ONLY' \
	"$output_dir/LOCAL-STAGING-NOT-FOR-RELEASE" || {
	printf 'Held installed-root marker mismatch.\n' >&2
	exit 1
}

rootfs="$output_dir/rootfs"
rootfs_manifest="$output_dir/ROOTFS-FILES.tsv"
boot_manifest="$output_dir/BOOT-PAYLOAD.tsv"
archive="$output_dir/sp11-installed-rootfs.tar.zst"
[[ -d "$rootfs" && ! -L "$rootfs" &&
	-f "$rootfs_manifest" && ! -L "$rootfs_manifest" &&
	-f "$boot_manifest" && ! -L "$boot_manifest" ]] || {
	printf 'Prepared root or manifest is missing or unsafe.\n' >&2
	exit 1
}
for forbidden_output in "$archive" "$output_dir/ARTIFACTS.tsv" \
	"$output_dir/HOLD-REASONS"; do
	[[ ! -e "$forbidden_output" && ! -L "$forbidden_output" ]] || {
		printf 'Refusing existing final artifact member: %s\n' \
			"$forbidden_output" >&2
		exit 1
	}
done

image="$output_dir/boot/Image-$release"
dtb="$output_dir/boot/x1e80100-microsoft-denali-oled.dtb"
[[ -f "$image" && ! -L "$image" &&
	"$(sha256sum "$image" | awk '{print $1}')" == "$expected_image" &&
	-f "$dtb" && ! -L "$dtb" &&
	"$(sha256sum "$dtb" | awk '{print $1}')" == "$expected_dtb" ]] || {
	printf 'Prepared boot payload identity mismatch.\n' >&2
	exit 1
}
awk -F '\t' '
	NR == 1 {
		if ($0 != "path\tbytes\tsha256")
			bad = 1
		next
	}
	NF != 3 || $2 !~ /^[0-9]+$/ || $3 !~ /^[0-9a-f]{64}$/ {
		bad = 1
	}
	END { exit bad || NR != 3 }
' "$boot_manifest" || {
	printf 'Prepared boot manifest is malformed.\n' >&2
	exit 1
}

printf 'Revalidating the prepared installed-root manifest ...\n'
verification_dir="$(mktemp -d /tmp/sp11-installed-root-manifest.XXXXXX)"
verification_manifest="$verification_dir/ROOTFS-FILES.tsv"
trap 'find "$verification_dir" -depth -delete' EXIT
"$script_dir/manifest-installed-rootfs.py" \
	"$rootfs" "$verification_manifest"
cmp -- "$rootfs_manifest" "$verification_manifest" || {
	printf 'Prepared root changed after its manifest was recorded.\n' >&2
	exit 1
}
find "$verification_dir" -depth -delete
trap - EXIT

printf 'Creating deterministic installed-root archive ...\n'
tar \
	--create \
	--sort=name \
	--format=pax \
	--pax-option=delete=atime,delete=ctime \
	--mtime="@$source_date_epoch" \
	--numeric-owner \
	--xattrs \
	--acls \
	-C "$rootfs" . |
	zstd -q -T1 -10 -o "$archive"

{
	printf 'artifact\tsha256\tbytes\n'
	for artifact in \
		"$archive" \
		"$rootfs_manifest" \
		"$boot_manifest" \
		"$image" \
		"$dtb"; do
		printf '%s\t%s\t%s\n' \
			"$(basename "$artifact")" \
			"$(sha256sum "$artifact" | awk '{print $1}')" \
			"$(stat -c '%s' "$artifact")"
	done
} >"$output_dir/ARTIFACTS.tsv"
printf '%s\n' \
	'HELD: source closure, executor, account, boot, rollback, and physical installation qualification remain incomplete.' \
	>"$output_dir/HOLD-REASONS"
find "$output_dir" -type f -exec touch -d "@$source_date_epoch" {} +

"$script_dir/audit-installed-rootfs.sh" "$output_dir"
printf '\nInstalled-root artifact: %s\n' "$archive"
sha256sum "$archive"
