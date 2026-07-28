#!/bin/bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
iso_dir="$repo_root/iso"
mode=""

usage() {
	cat <<EOF
Usage: $0 --write | --check

Resolve iso/packages-{live,build}.aarch64.tsv against an empty pacman local
database. --write updates the checked-in locks; --check reports any drift.
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
	*)
		usage >&2
		exit 2
		;;
	esac
done

[[ -n "$mode" ]] || {
	usage >&2
	exit 2
}
[[ "$(uname -m)" == "aarch64" ]] || {
	printf 'Package lock generation requires native aarch64.\n' >&2
	exit 1
}

for command_name in awk bsdtar cmp cp install pacman sha256sum sort; do
	command -v "$command_name" >/dev/null || {
		printf 'Missing required command: %s\n' "$command_name" >&2
		exit 1
	}
done

temporary="$(mktemp -d /tmp/sp11-package-lock.XXXXXX)"
trap 'rm -rf -- "$temporary"' EXIT
mkdir -p -- "$temporary/db/sync" "$temporary/cache" "$temporary/root"

repos=(core extra alarm aur)
for repo in "${repos[@]}"; do
	source_db="/var/lib/pacman/sync/$repo.db"
	[[ -f "$source_db" ]] || {
		printf 'Missing synchronized repository database: %s\n' "$source_db" >&2
		exit 1
	}
	cp -- "$source_db" "$temporary/db/sync/$repo.db"
done

read_profile() {
	local profile="$1"
	awk -F '\t' '
		NR == 1 && $1 == "package" { next }
		/^[[:space:]]*#/ || NF == 0 { next }
		$1 !~ /^[a-z0-9@._+:-]+$/ {
			printf "Invalid package name on line %d: %s\n", NR, $1 >"/dev/stderr"
			exit 1
		}
		{ print $1 }
	' "$profile"
}

mapfile -t live_packages < <(read_profile "$iso_dir/packages-live.aarch64.tsv")
mapfile -t build_packages < <(read_profile "$iso_dir/packages-build.aarch64.tsv")

resolve_profile() {
	local output="$1"
	shift
	pacman \
		--root "$temporary/root" \
		--dbpath "$temporary/db" \
		--cachedir "$temporary/cache" \
		--logfile /dev/null \
		--config /etc/pacman.conf \
		--noconfirm \
		-Sp \
		--print-format '%r|%n|%v|%a|%f|%h' \
		"$@" |
		LC_ALL=C sort -t '|' -k2,2 -u >"$output"
}

resolve_profile "$temporary/live.resolved" "${live_packages[@]}"
resolve_profile "$temporary/build.resolved" "${build_packages[@]}"

: >"$temporary/package-metadata.map"
for repo in "${repos[@]}"; do
	bsdtar -xOf "$temporary/db/sync/$repo.db" --include '*/desc' |
		awk -v repo="$repo" '
			BEGIN { marker = "" }
			/^%[A-Z0-9]+%$/ { marker = $0; next }
			marker == "%NAME%" {
				name = $0
				marker = ""
				next
			}
			marker == "%BASE%" {
				base = $0
				marker = ""
				next
			}
			marker == "%CSIZE%" {
				compressed = $0
				marker = ""
				next
			}
			marker == "%ISIZE%" {
				installed = $0
				marker = ""
				next
			}
			marker == "%MD5SUM%" {
				marker = ""
				print repo "|" name "|" base "|" compressed "|" installed
				next
			}
		' >>"$temporary/package-metadata.map"
done
LC_ALL=C sort -t '|' -k1,1 -k2,2 -u \
	"$temporary/package-metadata.map" -o "$temporary/package-metadata.map"

awk -F '|' '
	ARGIND == 1 { live[$2] = $0; next }
	ARGIND == 2 { build[$2] = $0; next }
	END {
		for (name in live) {
			scope = (name in build) ? "live+build" : "live"
			print live[name] "|" scope
		}
		for (name in build) {
			if (!(name in live))
				print build[name] "|build"
		}
	}
' "$temporary/live.resolved" "$temporary/build.resolved" |
	LC_ALL=C sort -t '|' -k2,2 >"$temporary/merged.resolved"

{
	printf 'scope\trepository\tpackage\tpkgbase\tversion\tarchitecture\tfilename\tsha256\tcompressed_bytes\tinstalled_bytes\tbinary_url\tpackage_page\tsource_files\n'
	while IFS='|' read -r repo package version architecture filename hash scope; do
		metadata="$(
			awk -F '|' -v repo="$repo" -v package="$package" \
				'$1 == repo && $2 == package {
					print $3 "|" $4 "|" $5
					exit
				}' \
				"$temporary/package-metadata.map"
		)"
		[[ -n "$metadata" ]] || {
			printf 'Could not resolve metadata for %s/%s\n' \
				"$repo" "$package" >&2
			exit 1
		}
		IFS='|' read -r pkgbase compressed installed <<<"$metadata"
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$scope" \
			"$repo" \
			"$package" \
			"$pkgbase" \
			"$version" \
			"$architecture" \
			"$filename" \
			"$hash" \
			"$compressed" \
			"$installed" \
			"https://mirror.archlinuxarm.org/aarch64/$repo/$filename" \
			"https://archlinuxarm.org/packages/aarch64/$package" \
			"https://archlinuxarm.org/packages/aarch64/$package/files"
	done <"$temporary/merged.resolved"
} >"$temporary/packages.lock.tsv"

{
	printf 'repository\tdatabase\tsha256\n'
	for repo in "${repos[@]}"; do
		printf '%s\t%s.db\t%s\n' \
			"$repo" \
			"$repo" \
			"$(sha256sum "$temporary/db/sync/$repo.db" | awk '{print $1}')"
	done
} >"$temporary/repositories.lock.tsv"

if [[ "$mode" == "write" ]]; then
	install -m0644 "$temporary/packages.lock.tsv" "$iso_dir/packages.lock.tsv"
	install -m0644 "$temporary/repositories.lock.tsv" \
		"$iso_dir/repositories.lock.tsv"
	printf 'Updated %s/packages.lock.tsv\n' "$iso_dir"
	printf 'Updated %s/repositories.lock.tsv\n' "$iso_dir"
else
	cmp -- "$temporary/packages.lock.tsv" "$iso_dir/packages.lock.tsv" || {
		printf 'Package lock drift detected. Review before running --write.\n' >&2
		exit 1
	}
	cmp -- "$temporary/repositories.lock.tsv" \
		"$iso_dir/repositories.lock.tsv" || {
		printf 'Repository database drift detected. Review before --write.\n' >&2
		exit 1
	}
	printf 'Package and repository locks match synchronized databases.\n'
fi
