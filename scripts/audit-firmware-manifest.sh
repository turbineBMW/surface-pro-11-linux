#!/bin/bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
firmware_dir="$repo_root/firmware"
allowlist="$firmware_dir/allowlist.tsv"
denylist="$firmware_dir/denylist.tsv"
package_lock="$firmware_dir/packages.lock.tsv"

for required_file in \
	"$firmware_dir/README.md" \
	"$allowlist" \
	"$denylist" \
	"$package_lock"; do
	[[ -f "$required_file" && ! -L "$required_file" ]] || {
		printf 'Missing or unsafe firmware manifest file: %s\n' \
			"$required_file" >&2
		exit 1
	}
done

awk -F '\t' '
	NR == 1 {
		if ($0 != "path\tsource_package\tsource_version\tsize\tsha256\tlicense_material\tpurpose")
			exit 1
		next
	}
	NF != 7 { exit 1 }
	$1 ~ /^\// || $1 ~ /(^|\/)\.\.(\/|$)/ { exit 1 }
	$2 !~ /^(linux-firmware-atheros|linux-firmware-qcom|wireless-regdb)$/ {
		exit 1
	}
	$4 !~ /^[0-9]+$/ { exit 1 }
	$5 !~ /^[0-9a-f]{64}$/ { exit 1 }
	$1 ~ /microsoft|Denali|board\.bin$/ { exit 1 }
' "$allowlist" || {
	printf 'Malformed or unsafe firmware allowlist.\n' >&2
	exit 1
}

allow_duplicates="$(awk -F '\t' 'NR > 1 { print $1 }' "$allowlist" |
	LC_ALL=C sort | uniq -d)"
[[ -z "$allow_duplicates" ]] || {
	printf 'Duplicate firmware allowlist paths:\n%s\n' "$allow_duplicates" >&2
	exit 1
}

if ! LC_ALL=C sort -c -t $'\t' -k1,1 <(sed '1d' "$allowlist"); then
	printf 'Firmware allowlist must be sorted by path.\n' >&2
	exit 1
fi

for denied_path in \
	ath12k/WCN7850/hw2.0/board.bin \
	qcom/x1e80100/X1E80100-Microsoft-Surface-Pro-11-tplg.bin \
	qcom/x1e80100/microsoft/Denali/qcadsp8380.mbn \
	qcom/x1e80100/microsoft/Denali/qccdsp8380.mbn; do
	awk -F '\t' -v denied_path="$denied_path" \
		'NR > 1 && $1 == denied_path { found = 1 }
		END { exit !found }' "$denylist" || {
		printf 'Required denylist path is absent: %s\n' "$denied_path" >&2
		exit 1
	}
done

awk -F '\t' '
	NR == 1 {
		if ($0 != "repository\tpackage\tpkgbase\tversion\tarchitecture\tfilename\tpackage_sha256\tpkgbuild_sha256\tupstream_source\tupstream_identity")
			exit 1
		next
	}
	NF != 10 { exit 1 }
	$1 != "core" || $5 != "any" { exit 1 }
	$7 !~ /^[0-9a-f]{64}$/ || $8 !~ /^[0-9a-f]{64}$/ { exit 1 }
' "$package_lock" || {
	printf 'Malformed firmware package lock.\n' >&2
	exit 1
}

while IFS=$'\t' read -r path source_package source_version _unused; do
	[[ "$path" != "path" ]] || continue
	awk -F '\t' -v package="$source_package" -v version="$source_version" \
		'NR > 1 && $2 == package && $4 == version { found = 1 }
		END { exit !found }' "$package_lock" || {
		printf 'Firmware source package is not locked: %s %s\n' \
			"$source_package" "$source_version" >&2
		exit 1
	}
done <"$allowlist"

if git -C "$repo_root" ls-files firmware |
	rg -n '\.(bin|mbn|fw|elf|tlv|p7s|zst|xz)$|(^|/)regulatory\.db$'; then
	printf 'Tracked firmware/blob file found below firmware/.\n' >&2
	exit 1
fi

printf 'Firmware manifest audit passed: %s allowlisted files, %s denied paths/patterns.\n' \
	"$(awk 'NR > 1 { count++ } END { print count + 0 }' "$allowlist")" \
	"$(awk 'NR > 1 { count++ } END { print count + 0 }' "$denylist")"
