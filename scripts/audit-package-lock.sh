#!/bin/bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
iso_dir="$repo_root/iso"
allow_missing_recipes=0
frozen_snapshot=""

command -v rg >/dev/null || {
	printf 'Missing audit command: rg\n' >&2
	exit 1
}

usage() {
	printf 'Usage: %s [--allow-missing-recipes] [--frozen-snapshot DIRECTORY]\n' \
		"$0"
}

while (($#)); do
	case "$1" in
	--allow-missing-recipes)
		allow_missing_recipes=1
		shift
		;;
	--frozen-snapshot)
		frozen_snapshot="${2:-}"
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

if [[ -n "$frozen_snapshot" ]]; then
	frozen_snapshot="$(realpath -e -- "$frozen_snapshot")"
	for frozen_lock in packages.lock.tsv repositories.lock.tsv; do
		[[ -f "$frozen_snapshot/$frozen_lock" &&
			! -L "$frozen_snapshot/$frozen_lock" ]] || {
			printf 'Frozen snapshot lacks safe %s: %s\n' \
				"$frozen_lock" "$frozen_snapshot" >&2
			exit 1
		}
		cmp -- "$iso_dir/$frozen_lock" \
			"$frozen_snapshot/$frozen_lock" || {
			printf 'Frozen snapshot lock mismatch: %s\n' \
				"$frozen_lock" >&2
			exit 1
		}
	done
fi

required_files=(
	"$iso_dir/README.md"
	"$iso_dir/packages-live.aarch64.tsv"
	"$iso_dir/packages-build.aarch64.tsv"
	"$iso_dir/packages.lock.tsv"
	"$iso_dir/package-recipes.lock.tsv"
	"$iso_dir/repositories.lock.tsv"
)
for required_file in "${required_files[@]}"; do
	[[ -f "$required_file" && ! -L "$required_file" ]] || {
		printf 'Missing or unsafe package-manifest file: %s\n' "$required_file" >&2
		exit 1
	}
done

for profile in \
	"$iso_dir/packages-live.aarch64.tsv" \
	"$iso_dir/packages-build.aarch64.tsv"; do
	duplicates="$(
		awk -F '\t' 'NR > 1 && NF { print $1 }' "$profile" |
			LC_ALL=C sort |
			uniq -d
	)"
	[[ -z "$duplicates" ]] || {
		printf 'Duplicate direct packages in %s:\n%s\n' "$profile" "$duplicates" >&2
		exit 1
	}
done

forbidden='^(linux|linux-aarch64|linux-firmware.*|firmware-.*|v4l2loopback.*|howdy|quickshell|niri|docker.*|base-devel|gcc|clang|cmake|meson|ninja)$'
if awk -F '\t' 'NR > 1 { print $3 }' "$iso_dir/packages.lock.tsv" |
	rg -n "$forbidden"; then
	printf 'Forbidden package present in package lock.\n' >&2
	exit 1
fi

if awk -F '\t' 'NR > 1 { print $2 }' "$iso_dir/packages.lock.tsv" |
	rg -n '^(aur)$'; then
	printf 'Foreign/AUR repository content present in package lock.\n' >&2
	exit 1
fi

awk -F '\t' '
	NR == 1 {
		if ($0 != "scope\trepository\tpackage\tpkgbase\tversion\tarchitecture\tfilename\tsha256\tcompressed_bytes\tinstalled_bytes\tbinary_url\tpackage_page\tsource_files")
			exit 1
		next
	}
	NF != 13 { exit 1 }
	$1 !~ /^(live|build|live\+build)$/ { exit 1 }
	$2 !~ /^(core|extra|alarm)$/ { exit 1 }
	$6 !~ /^(aarch64|any)$/ { exit 1 }
	$8 !~ /^[0-9a-f]{64}$/ { exit 1 }
	$9 !~ /^[0-9]+$/ { exit 1 }
	$10 !~ /^[0-9]+$/ { exit 1 }
	$11 !~ /^https:\/\/mirror\.archlinuxarm\.org\/aarch64\// { exit 1 }
	$12 !~ /^https:\/\/archlinuxarm\.org\/packages\/aarch64\// { exit 1 }
	$13 !~ /\/files$/ { exit 1 }
' "$iso_dir/packages.lock.tsv" || {
	printf 'Malformed package lock.\n' >&2
	exit 1
}

awk -F '\t' '
	NR == 1 {
		if ($0 != "repository\tdatabase\tsha256")
			exit 1
		next
	}
	NF != 3 { exit 1 }
	$1 !~ /^(core|extra|alarm|aur)$/ { exit 1 }
	$2 != $1 ".db" { exit 1 }
	$3 !~ /^[0-9a-f]{64}$/ { exit 1 }
' "$iso_dir/repositories.lock.tsv" || {
	printf 'Malformed repository lock.\n' >&2
	exit 1
}

awk -F '\t' '
	NR == 1 {
		if ($0 != "repository\tpkgbase\tversion\tpkgbuild_sha256\tpackages\tsource_files")
			exit 1
		next
	}
	NF != 6 { exit 1 }
	$1 !~ /^(core|extra|alarm)$/ { exit 1 }
	$4 !~ /^[0-9a-f]{64}$/ { exit 1 }
	$6 !~ /^https:\/\/archlinuxarm\.org\/packages\/aarch64\/.*\/files$/ {
		exit 1
	}
' "$iso_dir/package-recipes.lock.tsv" || {
	printf 'Malformed package recipe lock.\n' >&2
	exit 1
}

missing_recipes="$(
	awk -F '\t' 'NR > 1 { print $2 "\t" $4 "\t" $5 }' \
		"$iso_dir/packages.lock.tsv" |
		LC_ALL=C sort -u |
		comm -23 - <(
			awk -F '\t' 'NR > 1 { print $1 "\t" $2 "\t" $3 }' \
				"$iso_dir/package-recipes.lock.tsv" |
				LC_ALL=C sort -u
		)
)"
if [[ -n "$missing_recipes" ]]; then
	if [[ "$allow_missing_recipes" -eq 1 ]]; then
		printf 'Recipe identity refresh required after caching:\n%s\n' \
			"$missing_recipes" >&2
	else
		printf 'Package lock entries lack an exact recipe identity:\n%s\n' \
			"$missing_recipes" >&2
		exit 1
	fi
fi

if [[ -n "$frozen_snapshot" ]]; then
	printf 'Using exact frozen package/repository locks from: %s\n' \
		"$frozen_snapshot"
else
	"$script_dir/generate-package-lock.sh" --check
fi

package_count="$(awk 'NR > 1 { count++ } END { print count + 0 }' \
	"$iso_dir/packages.lock.tsv")"
live_count="$(awk -F '\t' \
	'NR > 1 && ($1 == "live" || $1 == "live+build") { count++ }
	END { print count + 0 }' "$iso_dir/packages.lock.tsv")"
build_count="$(awk -F '\t' \
	'NR > 1 && ($1 == "build" || $1 == "live+build") { count++ }
	END { print count + 0 }' "$iso_dir/packages.lock.tsv")"
live_compressed="$(awk -F '\t' \
	'NR > 1 && ($1 == "live" || $1 == "live+build") { total += $9 }
	END { print total + 0 }' "$iso_dir/packages.lock.tsv")"
recipe_count="$(awk 'NR > 1 { count++ } END { print count + 0 }' \
	"$iso_dir/package-recipes.lock.tsv")"
live_installed="$(awk -F '\t' \
	'NR > 1 && ($1 == "live" || $1 == "live+build") { total += $10 }
	END { print total + 0 }' "$iso_dir/packages.lock.tsv")"

printf 'Package lock audit passed: %s unique, %s live, %s build packages.\n' \
	"$package_count" "$live_count" "$build_count"
printf 'Repository package sizes: %s compressed bytes, %s installed bytes (live closure).\n' \
	"$live_compressed" "$live_installed"
printf 'Exact package recipes: %s distinct pkgbase identities.\n' "$recipe_count"
