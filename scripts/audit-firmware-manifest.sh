#!/bin/bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
firmware_dir="$repo_root/firmware"
allowlist="$firmware_dir/allowlist.tsv"
derived="$firmware_dir/derived.tsv"
denylist="$firmware_dir/denylist.tsv"
external_required="$firmware_dir/external-required.tsv"
package_lock="$firmware_dir/packages.lock.tsv"

command -v rg >/dev/null || {
	printf 'Missing audit command: rg\n' >&2
	exit 1
}

for required_file in \
	"$firmware_dir/README.md" \
	"$allowlist" \
	"$derived" \
	"$denylist" \
	"$external_required" \
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

awk -F '\t' '
	NR == 1 {
		if ($0 != "path\tsource_path\trecord_name\tbytes\tsha256\tlicense_material\tpurpose")
			exit 1
		next
	}
	NF != 7 { exit 1 }
	$1 ~ /^\// || $1 ~ /(^|\/)\.\.(\/|$)/ { exit 1 }
	$2 ~ /^\// || $2 ~ /(^|\/)\.\.(\/|$)/ { exit 1 }
	$4 !~ /^[0-9]+$/ { exit 1 }
	$5 !~ /^[0-9a-f]{64}$/ { exit 1 }
	$3 == "" || $6 == "" || $7 == "" { exit 1 }
	{ count++ }
	END { exit count != 1 }
' "$derived" || {
	printf 'Malformed derived firmware manifest.\n' >&2
	exit 1
}
awk -F '\t' '
	NR == 2 &&
	$1 == "ath12k/WCN7850/hw2.0/board.bin" &&
	$2 == "ath12k/WCN7850/hw2.0/board-2.bin" &&
	$3 == "bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=3378,qmi-chip-id=2,qmi-board-id=255" &&
	$4 == "88872" &&
	$5 == "0ef5f6f3cb124f33c6de52371819ccd7c13763ceb86d476a178fd56e4cdc26a3" {
		found = 1
	}
	END { exit !found }
' "$derived" || {
	printf 'Qualified SP11 board derivation is absent or changed.\n' >&2
	exit 1
}
while IFS=$'\t' read -r path source_path _record _bytes output_sha _rest; do
	[[ "$path" != "path" ]] || continue
	awk -F '\t' -v source_path="$source_path" \
		'NR > 1 && $1 == source_path { found = 1 }
		END { exit !found }' "$allowlist" || {
		printf 'Derived firmware source is not allowlisted: %s\n' \
			"$source_path" >&2
		exit 1
	}
	if awk -F '\t' -v path="$path" -v output_sha="$output_sha" '
		NR > 1 && $1 == path && $2 == output_sha { found = 1 }
		END { exit !found }
	' "$denylist"; then
		printf 'Accepted derived firmware remains denied: %s\n' "$path" >&2
		exit 1
	fi
	if awk -F '\t' -v path="$path" '
		NR > 1 && $1 == path { found = 1 }
		END { exit !found }
	' "$external_required"; then
		printf 'Derived firmware remains an external prerequisite: %s\n' \
			"$path" >&2
		exit 1
	fi
done <"$derived"

for denied_path in \
	ath12k/WCN7850/hw2.0/board.bin \
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
		if ($0 != "path\tbytes\tsha256\tcandidate_names\tpurpose")
			exit 1
		next
	}
	NF != 5 { exit 1 }
	$1 ~ /^\// || $1 ~ /(^|\/)\.\.(\/|$)/ { exit 1 }
	$2 !~ /^[0-9]+$/ { exit 1 }
	$3 !~ /^[0-9a-f]{64}$/ { exit 1 }
	$4 == "" || $5 == "" { exit 1 }
' "$external_required" || {
	printf 'Malformed external firmware manifest.\n' >&2
	exit 1
}
[[ "$(awk 'NR > 1 { count++ } END { print count + 0 }' \
		"$external_required")" -eq 5 ]] || {
	printf 'Unexpected external firmware count.\n' >&2
	exit 1
}
if ! LC_ALL=C sort -c -t $'\t' -k1,1 <(sed '1d' "$external_required"); then
	printf 'External firmware manifest must be sorted by path.\n' >&2
	exit 1
fi
while IFS=$'\t' read -r path _bytes expected_sha _rest; do
	[[ "$path" != "path" ]] || continue
	awk -F '\t' -v path="$path" -v expected_sha="$expected_sha" '
		NR > 1 && $1 == path && $2 == expected_sha { found = 1 }
		END { exit !found }
	' "$denylist" || {
		printf 'External firmware is absent from the denylist: %s\n' \
			"$path" >&2
		exit 1
	}
done <"$external_required"
rejected_board_shas=(
	"b24438910ff0383d299798a997d3ef3484be624ac013aec2ce7939ec32900c4f"
	"571c97ae80c80268f2f34203a7c4857e6ffb9f7dd1421a619b68bf843a2135e5"
	"c07cef280f8aa23d34aabd6b6e81ae7c7b3bc31c8a137e32e51bc6be0eb322f0"
)
for rejected_board_sha in "${rejected_board_shas[@]}"; do
	awk -F '\t' -v expected_sha="$rejected_board_sha" '
		NR > 1 &&
		$1 == "ath12k/WCN7850/hw2.0/board.bin" &&
		$2 == expected_sha &&
		$3 ~ /rejected.*-110/ { found = 1 }
		END { exit !found }
	' "$denylist" || {
		printf 'Rejected board data is absent from the denylist: %s\n' \
			"$rejected_board_sha" >&2
		exit 1
	}
	for firmware_consumer in \
		"$repo_root/scripts/sp11-collect-firmware.ps1" \
		"$repo_root/scripts/sp11-firmware.py" \
		"$repo_root/iso/mkinitcpio/hooks/sp11live"; do
		if grep -Fq "$rejected_board_sha" "$firmware_consumer"; then
			printf 'Rejected board data remains accepted by consumer: %s\n' \
				"$firmware_consumer" >&2
			exit 1
		fi
	done
done
if awk -F '\t' '
	NR > 1 && $1 == "qcom/x1e80100/X1E80100-Microsoft-Surface-Pro-11-tplg.bin" {
		found = 1
	}
	END { exit !found }
' "$denylist"; then
	printf 'Redistributable audio topology remains incorrectly denied.\n' >&2
	exit 1
fi

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
