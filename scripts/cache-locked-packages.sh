#!/bin/bash

# Cache and audit the exact signed Arch Linux ARM packages named by the live
# image lock. This is held engineering staging, not a release assembler.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
lock="$repo_root/iso/packages.lock.tsv"
repository_lock="$repo_root/iso/repositories.lock.tsv"
output_dir="$repo_root/work/package-snapshot"
local_staging=0

usage() {
	cat <<EOF
Usage: $0 --local-staging [--output DIRECTORY]

The output must be a new directory below this repository's ignored work/
directory. No package is installed on the host.
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

[[ $local_staging -eq 1 ]] || {
	printf 'Package caching requires explicit --local-staging.\n' >&2
	exit 1
}
[[ -e "$repo_root/BINARY-RELEASE-HOLD.md" ]] || {
	printf 'This helper is only for held local engineering staging.\n' >&2
	exit 1
}
[[ "$(uname -m)" == "aarch64" ]] || {
	printf 'Package caching requires native aarch64.\n' >&2
	exit 1
}

for command_name in awk bsdtar cp fakeroot pacman pacman-key \
	realpath sha256sum sort; do
	command -v "$command_name" >/dev/null || {
		printf 'Missing required command: %s\n' "$command_name" >&2
		exit 1
	}
done

"$script_dir/audit-package-lock.sh"

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
[[ ! -e "$output_dir" ]] || {
	printf 'Refusing to replace existing output: %s\n' "$output_dir" >&2
	exit 1
}

temporary="$(mktemp -d "$repo_root/work/package-download.XXXXXX")"
cleanup() {
	rm -r -- "$temporary"
}
trap cleanup EXIT

cache="$temporary/packages"
metadata="$temporary/metadata"
database="$temporary/database"
root="$temporary/root"
mkdir -p -- "$cache" "$metadata" "$database/sync" "$root"

while IFS=$'\t' read -r repo database_file expected_hash; do
	[[ "$repo" != "repository" ]] || continue
	source_db="/var/lib/pacman/sync/$database_file"
	actual_hash="$(sha256sum "$source_db" | awk '{print $1}')"
	[[ "$actual_hash" == "$expected_hash" ]] || {
		printf 'Repository database changed: %s\n' "$repo" >&2
		exit 1
	}
	cp -- "$source_db" "$database/sync/$database_file"
done <"$repository_lock"

# Reuse byte-identical packages already present in the host package cache.
while IFS=$'\t' read -r scope repo package pkgbase version architecture \
	filename expected_hash compressed _installed _unused; do
	[[ "$scope" != "scope" ]] || continue
	host_package="/var/cache/pacman/pkg/$filename"
	[[ -f "$host_package" ]] || continue
	actual_hash="$(sha256sum "$host_package" | awk '{print $1}')"
	[[ "$actual_hash" == "$expected_hash" ]] || continue
	cp --reflink=auto --preserve=timestamps \
		"$host_package" "$cache/$filename"
	if [[ -f "$host_package.sig" ]]; then
		cp --reflink=auto --preserve=timestamps \
			"$host_package.sig" "$cache/$filename.sig"
	fi
done <"$lock"

mapfile -t targets < <(
	awk -F '\t' 'NR > 1 { print $3 "=" $5 }' "$lock" |
		LC_ALL=C sort
)

pacman_command=(
	pacman
	--disable-sandbox
	--root "$root"
	--dbpath "$database"
	--cachedir "$cache"
	--gpgdir /etc/pacman.d/gnupg
	--logfile /dev/null
	--config /etc/pacman.conf
	--noconfirm
	--noprogressbar
	-Sw
)
if [[ $EUID -eq 0 ]]; then
	"${pacman_command[@]}" "${targets[@]}"
else
	fakeroot "${pacman_command[@]}" "${targets[@]}"
fi

printf '%s\n' \
	'BINARY/ISO RELEASE HOLD ACTIVE — LOCAL PACKAGE STAGING ONLY' \
	>"$temporary/LOCAL-STAGING-NOT-FOR-RELEASE"

snapshot_manifest="$temporary/PACKAGE-SNAPSHOT.tsv"
printf 'repository\tpackage\tpkgbase\tversion\tarchitecture\tfilename\tsha256\tsignature_sha256\tbuildinfo_sha256\tpkginfo_sha256\tmtree_sha256\n' \
	>"$snapshot_manifest"

while IFS=$'\t' read -r scope repo package pkgbase version architecture \
	filename expected_hash compressed _installed _unused; do
	[[ "$scope" != "scope" ]] || continue
	package_file="$cache/$filename"
	signature_file="$package_file.sig"
	[[ -f "$package_file" && ! -L "$package_file" ]] || {
		printf 'Missing cached package: %s\n' "$filename" >&2
		exit 1
	}
	[[ -f "$signature_file" && ! -L "$signature_file" ]] || {
		printf 'Missing detached package signature: %s.sig\n' "$filename" >&2
		exit 1
	}
	actual_hash="$(sha256sum "$package_file" | awk '{print $1}')"
	[[ "$actual_hash" == "$expected_hash" ]] || {
		printf 'Package hash mismatch: %s\n' "$filename" >&2
		exit 1
	}
	[[ "$(stat -c '%s' "$package_file")" == "$compressed" ]] || {
		printf 'Package size mismatch: %s\n' "$filename" >&2
		exit 1
	}
	pacman-key --verify "$signature_file" "$package_file" \
		>/dev/null 2>&1

	package_metadata="$metadata/$package"
	mkdir -p -- "$package_metadata"
	for member in .BUILDINFO .PKGINFO .MTREE; do
		bsdtar -xOf "$package_file" "$member" \
			>"$package_metadata/${member#.}"
	done

	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$repo" \
		"$package" \
		"$pkgbase" \
		"$version" \
		"$architecture" \
		"$filename" \
		"$actual_hash" \
		"$(sha256sum "$signature_file" | awk '{print $1}')" \
		"$(sha256sum "$package_metadata/BUILDINFO" | awk '{print $1}')" \
		"$(sha256sum "$package_metadata/PKGINFO" | awk '{print $1}')" \
		"$(sha256sum "$package_metadata/MTREE" | awk '{print $1}')" \
		>>"$snapshot_manifest"
done <"$lock"

expected_count="$(awk 'NR > 1 { count++ } END { print count + 0 }' "$lock")"
package_count="$(find "$cache" -maxdepth 1 -type f -name '*.pkg.tar.*' \
	! -name '*.sig' -printf . | wc -c)"
signature_count="$(find "$cache" -maxdepth 1 -type f -name '*.pkg.tar.*.sig' \
	-printf . | wc -c)"
metadata_count="$(find "$metadata" -mindepth 2 -maxdepth 2 -type f \
	-printf . | wc -c)"
[[ "$package_count" -eq "$expected_count" ]] || {
	printf 'Unexpected package count: %s (expected %s)\n' \
		"$package_count" "$expected_count" >&2
	exit 1
}
[[ "$signature_count" -eq "$expected_count" ]] || {
	printf 'Unexpected signature count: %s (expected %s)\n' \
		"$signature_count" "$expected_count" >&2
	exit 1
}
[[ "$metadata_count" -eq $((expected_count * 3)) ]] || {
	printf 'Unexpected metadata-file count: %s (expected %s)\n' \
		"$metadata_count" "$((expected_count * 3))" >&2
	exit 1
}

cp -- "$lock" "$temporary/packages.lock.tsv"
cp -- "$repository_lock" "$temporary/repositories.lock.tsv"
mv -- "$temporary" "$output_dir"
trap - EXIT

printf 'Package snapshot: %s\n' "$output_dir"
printf 'Packages: %s; signatures: %s; metadata files: %s\n' \
	"$package_count" "$signature_count" "$metadata_count"
sha256sum "$output_dir/PACKAGE-SNAPSHOT.tsv"
