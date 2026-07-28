#!/bin/bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
output="$repo_root/iso/package-recipes.lock.tsv"
mode=""
snapshot=""

usage() {
	cat <<EOF
Usage: $0 --write|--check PACKAGE-SNAPSHOT-DIRECTORY

Generate or verify the exact PKGBUILD checksum lock from the .BUILDINFO files
extracted by cache-locked-packages.sh.
EOF
}

while (($#)); do
	case "$1" in
	--write | --check)
		[[ -z "$mode" ]] || {
			usage >&2
			exit 2
		}
		mode="${1#--}"
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	-*)
		usage >&2
		exit 2
		;;
	*)
		[[ -z "$snapshot" ]] || {
			usage >&2
			exit 2
		}
		snapshot="$1"
		shift
		;;
	esac
done

[[ -n "$mode" && -n "$snapshot" ]] || {
	usage >&2
	exit 2
}
snapshot="$(realpath -e -- "$snapshot")"
[[ -f "$snapshot/PACKAGE-SNAPSHOT.tsv" ]] || {
	printf 'Not a package snapshot: %s\n' "$snapshot" >&2
	exit 1
}

temporary="$(mktemp -d /tmp/sp11-package-recipes.XXXXXX)"
trap 'rm -r -- "$temporary"' EXIT
rows="$temporary/rows.tsv"
: >"$rows"

while IFS=$'\t' read -r repository package pkgbase version architecture \
	_filename _sha256 _signature_sha256 buildinfo_sha256 _unused; do
	[[ "$repository" != "repository" ]] || continue
	buildinfo="$snapshot/metadata/$package/BUILDINFO"
	[[ -f "$buildinfo" && ! -L "$buildinfo" ]] || {
		printf 'Missing BUILDINFO for %s\n' "$package" >&2
		exit 1
	}
	actual_buildinfo="$(sha256sum "$buildinfo" | awk '{print $1}')"
	[[ "$actual_buildinfo" == "$buildinfo_sha256" ]] || {
		printf 'BUILDINFO hash mismatch for %s\n' "$package" >&2
		exit 1
	}
	built_name="$(awk -F ' = ' '$1 == "pkgname" { print $2; exit }' "$buildinfo")"
	built_base="$(awk -F ' = ' '$1 == "pkgbase" { print $2; exit }' "$buildinfo")"
	built_version="$(awk -F ' = ' '$1 == "pkgver" { print $2; exit }' "$buildinfo")"
	built_arch="$(awk -F ' = ' '$1 == "pkgarch" { print $2; exit }' "$buildinfo")"
	pkgbuild_hash="$(
		awk -F ' = ' '$1 == "pkgbuild_sha256sum" { print $2; exit }' \
			"$buildinfo"
	)"
	[[ "$built_name" == "$package" &&
		"$built_base" == "$pkgbase" &&
		"$built_version" == "$version" &&
		"$built_arch" == "$architecture" &&
		"$pkgbuild_hash" =~ ^[0-9a-f]{64}$ ]] || {
		printf 'BUILDINFO identity mismatch for %s\n' "$package" >&2
		exit 1
	}
	printf '%s\t%s\t%s\t%s\t%s\n' \
		"$repository" "$pkgbase" "$version" "$pkgbuild_hash" "$package" \
		>>"$rows"
done <"$snapshot/PACKAGE-SNAPSHOT.tsv"

LC_ALL=C sort -t $'\t' -k1,1 -k2,2 -k5,5 "$rows" -o "$rows"

{
	printf 'repository\tpkgbase\tversion\tpkgbuild_sha256\tpackages\tsource_files\n'
	awk -F '\t' '
		function emit() {
			if (key == "")
				return
			printf "%s\t%s\t%s\t%s\t%s\thttps://archlinuxarm.org/packages/aarch64/%s/files\n",
				repository, base, version, hash, packages, first_package
		}
		{
			next_key = $1 SUBSEP $2
			if (key != "" && next_key != key)
				emit()
			if (next_key != key) {
				key = next_key
				repository = $1
				base = $2
				version = $3
				hash = $4
				packages = $5
				first_package = $5
			} else {
				if ($3 != version || $4 != hash) {
					printf "Conflicting recipe identity for %s/%s\n",
						repository, base >"/dev/stderr"
					exit 1
				}
				packages = packages "," $5
			}
		}
		END { emit() }
	' "$rows"
} >"$temporary/package-recipes.lock.tsv"

if [[ "$mode" == "write" ]]; then
	install -m0644 "$temporary/package-recipes.lock.tsv" "$output"
	printf 'Updated %s\n' "$output"
else
	cmp -- "$temporary/package-recipes.lock.tsv" "$output" || {
		printf 'Package recipe lock drift detected.\n' >&2
		exit 1
	}
	printf 'Package recipe lock matches snapshot BUILDINFO metadata.\n'
fi
