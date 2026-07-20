#!/bin/bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
patch="$repo_root/kernel/sp11-sanitized2.patch"
bundle="$repo_root/kernel/sp11-sanitized2.bundle"
camera_patch="$repo_root/kernel/sp11-camera-review.patch"
camera_bundle="$repo_root/kernel/sp11-camera-review.bundle"

expected_patch="218ee1ec59a29887aab919fcd37c7d8a21f7ca421ea3757476ddbab76bf07914"
expected_bundle="cd782a17f4c6645d63d51c057bc9115ac0b7167966a6ce8c663c6e351b79d3e7"
expected_config="8834ac6021bc4d50034b55c0960938070541387c0984aed4cc6797601ecce7f1"
expected_symvers="b58de2ebd5ca9649b0e7299e4b5b7e3965f70e06506b88c1ec3d5046ce2e9387"
expected_buildinfo="c23d4a57de6e5fd892f46feaa13ee433dee11f11c96ab8c3107c827beb9d3e77"
expected_camera_config="1e0c1b580140a88d46549071c10ab5a06b216d35f32eb49d7c77366534d989e7"
expected_tip="2ace98eb6ef18cbd48074eed9f5b585d19ce398b"
expected_camera_patch="a6d6f31fd9b3eea7e5b4243ec30300e1bc43718253fd2a2b77c2bdf4cebc3b6c"
expected_camera_bundle="bacf60dc80463c92da9b62f3f0c5da077c27b67ac6685a28c542b890de5b8e64"
expected_camera_tip="675d89b381d8b730a3f2eff1086875481ee5b515"

for command_name in git reuse rg sha256sum; do
	command -v "$command_name" >/dev/null || {
		printf 'Missing audit command: %s\n' "$command_name" >&2
		exit 1
	}
done

[[ -f "$repo_root/BINARY-RELEASE-HOLD.md" ]] || {
	printf 'Binary/ISO release hold disappeared before the gates were closed.\n' >&2
	exit 1
}

[[ ! -e "$repo_root/LEGAL-REVIEW-HOLD.md" ]] || {
	printf 'Obsolete repository-wide publication hold is still present.\n' >&2
	exit 1
}

for withdrawn in \
	"$repo_root/kernel/sp11-practical8.patch" \
	"$repo_root/kernel/sp11-practical8.bundle" \
	"$repo_root/kernel/sp11-practical8-sanitized.patch" \
	"$repo_root/kernel/sp11-practical8-sanitized.bundle"; do
	[[ ! -e "$withdrawn" ]] || {
		printf 'Withdrawn artifact is present: %s\n' "$withdrawn" >&2
		exit 1
	}
done

if git -C "$repo_root" ls-files | rg -n \
	'(^|/)(work|release)/|(^|/)(Image-[^/]*|[^/]*\.dtb|[^/]*\.ko|[^/]*\.zst|[^/]*\.iso|[^/]*\.img|[^/]*\.cab|[^/]*\.sys|[^/]*\.dll|[^/]*\.exe)$'; then
	printf 'Tracked binary, payload, firmware-package, or work artifact found.\n' >&2
	exit 1
fi

[[ "$(sha256sum "$patch" | awk '{print $1}')" == "$expected_patch" ]]
[[ "$(sha256sum "$bundle" | awk '{print $1}')" == "$expected_bundle" ]]
[[ "$(sha256sum "$repo_root/kernel/config" | awk '{print $1}')" == "$expected_config" ]]
[[ "$(sha256sum "$repo_root/kernel/Module.symvers" | awk '{print $1}')" == "$expected_symvers" ]]
[[ "$(sha256sum "$repo_root/kernel/BUILDINFO" | awk '{print $1}')" == "$expected_buildinfo" ]]
[[ "$(sha256sum "$repo_root/kernel/camera-review.config.fragment" | awk '{print $1}')" == "$expected_camera_config" ]]
[[ "$(git bundle list-heads "$bundle" | awk '{print $1}')" == "$expected_tip" ]]
[[ "$(sha256sum "$camera_patch" | awk '{print $1}')" == "$expected_camera_patch" ]]
[[ "$(sha256sum "$camera_bundle" | awk '{print $1}')" == "$expected_camera_bundle" ]]
[[ "$(git bundle list-heads "$camera_bundle" | awk '{print $1}')" == "$expected_camera_tip" ]]
[[ "$(rg -c '^From [0-9a-f]{40} Mon Sep 17 00:00:00 2001$' "$camera_patch")" -eq 13 ]]

if rg -n '^diff --git a/(drivers/media|drivers/phy/qualcomm/.*cphy|arch/arm64/boot/dts/qcom/.*camera)' "$patch"; then
	printf 'Camera-related path found in sanitized kernel patch.\n' >&2
	exit 1
fi

if rg -n -i 'camx|qccammipicsi|imx681-tables|vd55g0-win|cphy-win-tables|camnoc-win-tables' "$patch"; then
	printf 'Withdrawn camera material marker found in sanitized kernel patch.\n' >&2
	exit 1
fi

if rg -n -i 'SPI_HID_DESCRIPTOR_ONLY|descriptor.only|82da5e19' "$patch"; then
	printf 'Removed touch/QSPI diagnostic material found in sanitized kernel patch.\n' >&2
	exit 1
fi

if rg -n -i 'qccammipicsi|cphy-win-tables|camnoc-win-tables|vd55g0-win|com\.surface\.sensormodule|/home/|WillzDenali' "$camera_patch"; then
	printf 'Withdrawn, private, or host-specific material found in camera patch.\n' >&2
	exit 1
fi

[[ "$(git bundle list-heads "$bundle" | wc -l)" -eq 1 ]]
[[ "$(git bundle list-heads "$camera_bundle" | wc -l)" -eq 1 ]]

(
	cd -- "$repo_root"
	reuse lint
	git diff --check
	bash -n scripts/*.sh rootfs/usr/local/libexec/sp11-bluetooth-address \
		rootfs/usr/lib/systemd/system-sleep/*.sh
	if command -v shellcheck >/dev/null; then
		shellcheck scripts/*.sh rootfs/usr/local/libexec/sp11-bluetooth-address \
			rootfs/usr/lib/systemd/system-sleep/*.sh
	fi
)

printf 'Static source-publication audit passed; the binary/ISO hold and unchecked binary gates remain active.\n'
