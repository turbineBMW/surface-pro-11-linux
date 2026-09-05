#!/bin/bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
patch="$repo_root/kernel/sp11-sanitized2.patch"
bundle="$repo_root/kernel/sp11-sanitized2.bundle"
camera_patch="$repo_root/kernel/sp11-camera-review.patch"
camera_bundle="$repo_root/kernel/sp11-camera-review.bundle"
touch_patch="$repo_root/kernel/sp11-touch-spi-autoload.patch"
touch_bundle="$repo_root/kernel/sp11-touch-spi-autoload.bundle"
resume_patch="$repo_root/kernel/sp11-tablet-mode-resume-resync.patch"
resume_bundle="$repo_root/kernel/sp11-tablet-mode-resume-resync.bundle"
charge_patch="$repo_root/kernel/sp11-charge-limit-reliability.patch"
charge_bundle="$repo_root/kernel/sp11-charge-limit-reliability.bundle"
switch_patch="$repo_root/kernel/sp11-camera-switch-fix.patch"
switch_bundle="$repo_root/kernel/sp11-camera-switch-fix.bundle"
ddc_patch="$repo_root/kernel/sp11-dp-ddc-fix.patch"
ddc_bundle="$repo_root/kernel/sp11-dp-ddc-fix.bundle"
review20_patch="$repo_root/kernel/sp11-suspend-review20.patch"
review20_bundle="$repo_root/kernel/sp11-suspend-review20.bundle"
runtime_idle_guard="$repo_root/rootfs/usr/local/libexec/sp11-runtime-idle-suspend-guard"
runtime_idle_dropin="$repo_root/rootfs/etc/systemd/system/systemd-suspend.service.d/10-sp11-runtime-idle-guard.conf"
videocc_initramfs_dropin="$repo_root/rootfs/etc/mkinitcpio.conf.d/90-sp11-videocc.conf"

expected_patch="218ee1ec59a29887aab919fcd37c7d8a21f7ca421ea3757476ddbab76bf07914"
expected_bundle="cd782a17f4c6645d63d51c057bc9115ac0b7167966a6ce8c663c6e351b79d3e7"
expected_config="a4ed1fbc62e2d3251394c09410778173766cae309b7e3434388239644bb51788"
expected_symvers="b58de2ebd5ca9649b0e7299e4b5b7e3965f70e06506b88c1ec3d5046ce2e9387"
expected_buildinfo="eb14f58615a7dbd6abf0ac825abf64f45f4435092dc6e5dadf9b1d44b112583b"
expected_camera_config="5f0f096db561a65653ed710cd79f8aa8a97d0bad7608fdd06edd51f98212622f"
expected_tip="2ace98eb6ef18cbd48074eed9f5b585d19ce398b"
expected_camera_patch="a6d6f31fd9b3eea7e5b4243ec30300e1bc43718253fd2a2b77c2bdf4cebc3b6c"
expected_camera_bundle="bacf60dc80463c92da9b62f3f0c5da077c27b67ac6685a28c542b890de5b8e64"
expected_camera_tip="675d89b381d8b730a3f2eff1086875481ee5b515"
expected_touch_patch="3e698738381fdec196600beb6b7b7e9997dd1cfc53e086eee6e6cb3dfbdc6f0e"
expected_touch_bundle="02c18a42b44ddefa2c084f5336df68b3ceac2011779aaa299c07cd0e0970add1"
expected_touch_tip="86fc94c58a89a56c7ceb57b42c6025b2569da56d"
expected_resume_patch="12f36124f5b7a3d69c22dea082042cbea3cf1c1a784358bad41055a3646db8da"
expected_resume_bundle="5c866e0add29dd2c40fa92df73bcbe2d11754d8fed99ab8986aaf8672612d0ab"
expected_resume_tip="940bbc856a120e6f967f9dbaf825d5473bfae664"
expected_charge_patch="39295b72da15d0ee562321f2639def026ded06b3b2321bbb91f6e4ee7ff8fdf6"
expected_charge_bundle="89bee6d67608f2d87f3952e1c72be58affcb02eb2ff2f8f8c1ca0ea2aaf06641"
expected_charge_tip="4d50f4a7a8debb28b5780f80f941f1fcee4036cd"
expected_switch_patch="ce3c865b5722b010c2363ad0df60f52e12c237158efc3e6d41e91210d12c5773"
expected_switch_bundle="65272a9e635aa2856c8b9e5cb01e2b7e155a6762db16ebe3fc044bd102beb8f2"
expected_switch_tip="fd1932d6e2a45e665c062b1b1c810f09db46ab4e"
expected_ddc_patch="6e840cd46a1af78734cbc43878bae6553a0591ca489786045b8a72402b6381b6"
expected_ddc_bundle="0206952408c6c9f55f2804acc8b8153bf6208c9de79cd450973bcdfd601c3073"
expected_ddc_tip="a3e71f7080ee40dccfdd9500b8957a7c143fb6a2"
expected_review20_patch="855eb015df2fa1af281f531e401cb419101ef950738e4d27042f360ebf3d9b04"
expected_review20_bundle="0c078953e0f827a1b3fd126e818debce17fe851452d61f0e8758dd4e4b521385"
expected_review20_tip="18d7951a10dc49e383d16c6af82fc2c07784de3d"
expected_runtime_idle_guard="31af7630b55313ef82cda79c0c1669a3a94cea5ac71e4857cd37fe3b4cb0869a"
expected_runtime_idle_dropin="a2b708ccb9d61669ddfebb6be8bdcc0e54ec0717e697f8f6894f5a64436ce847"
expected_videocc_initramfs_dropin="274f034664f810d666194af6682f652537323444ca61b70d0f70768c34bb27cb"

for command_name in git reuse rg sha256sum; do
	command -v "$command_name" >/dev/null || {
		printf 'Missing audit command: %s\n' "$command_name" >&2
		exit 1
	}
done

[[ -f "$repo_root/RELEASE-STATUS.md" ]] || {
	printf 'RELEASE-STATUS.md is missing.\n' >&2
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
	'(^|/)(work|release)/|(^|/)(Image-[^/]*|[^/]*\.dtb|[^/]*\.ko|[^/]*\.zst|[^/]*\.iso|[^/]*\.img|[^/]*\.cab|[^/]*\.sys|[^/]*\.dll|[^/]*\.exe|[^/]*\.mbn|[^/]*\.fw|[^/]*\.elf|[^/]*\.tlv|[^/]*\.p7s)$'; then
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
[[ "$(sha256sum "$touch_patch" | awk '{print $1}')" == "$expected_touch_patch" ]]
[[ "$(sha256sum "$touch_bundle" | awk '{print $1}')" == "$expected_touch_bundle" ]]
[[ "$(git bundle list-heads "$touch_bundle" | awk '{print $1}')" == "$expected_touch_tip" ]]
[[ "$(sha256sum "$resume_patch" | awk '{print $1}')" == "$expected_resume_patch" ]]
[[ "$(sha256sum "$resume_bundle" | awk '{print $1}')" == "$expected_resume_bundle" ]]
[[ "$(git bundle list-heads "$resume_bundle" | awk '{print $1}')" == "$expected_resume_tip" ]]
[[ "$(rg -c '^From [0-9a-f]{40} Mon Sep 17 00:00:00 2001$' "$resume_patch")" -eq 3 ]]
[[ "$(rg -c '^diff --git ' "$resume_patch")" -eq 3 ]]
[[ "$(sha256sum "$charge_patch" | awk '{print $1}')" == "$expected_charge_patch" ]]
[[ "$(sha256sum "$charge_bundle" | awk '{print $1}')" == "$expected_charge_bundle" ]]
[[ "$(git bundle list-heads "$charge_bundle" | awk '{print $1}')" == "$expected_charge_tip" ]]
[[ "$(sha256sum "$switch_patch" | awk '{print $1}')" == "$expected_switch_patch" ]]
[[ "$(sha256sum "$switch_bundle" | awk '{print $1}')" == "$expected_switch_bundle" ]]
[[ "$(git bundle list-heads "$switch_bundle" | awk '{print $1}')" == "$expected_switch_tip" ]]
[[ "$(rg -c '^diff --git ' "$switch_patch")" -eq 1 ]]
[[ "$(sha256sum "$ddc_patch" | awk '{print $1}')" == "$expected_ddc_patch" ]]
[[ "$(sha256sum "$ddc_bundle" | awk '{print $1}')" == "$expected_ddc_bundle" ]]
[[ "$(git bundle list-heads "$ddc_bundle" | awk '{print $1}')" == "$expected_ddc_tip" ]]
[[ "$(rg -c '^diff --git ' "$ddc_patch")" -eq 4 ]]
[[ "$(sha256sum "$review20_patch" | awk '{print $1}')" == "$expected_review20_patch" ]]
[[ "$(sha256sum "$review20_bundle" | awk '{print $1}')" == "$expected_review20_bundle" ]]
[[ "$(git bundle list-heads "$review20_bundle" | awk '{print $1}')" == "$expected_review20_tip" ]]
[[ "$(rg -c '^From [0-9a-f]{40} Mon Sep 17 00:00:00 2001$' "$review20_patch")" -eq 20 ]]
[[ "$(rg -c '^diff --git ' "$review20_patch")" -eq 25 ]]
[[ "$(sha256sum "$runtime_idle_guard" | awk '{print $1}')" == "$expected_runtime_idle_guard" ]]
[[ "$(sha256sum "$runtime_idle_dropin" | awk '{print $1}')" == "$expected_runtime_idle_dropin" ]]
[[ "$(sha256sum "$videocc_initramfs_dropin" | awk '{print $1}')" == "$expected_videocc_initramfs_dropin" ]]
[[ -x "$runtime_idle_guard" ]]

# The IR bridge fails closed on a kernel-release mismatch, which is a real
# guard: the illuminator's sink mapping and 600 mA ceiling were established
# experimentally, and a device-tree change could alter the current through an
# emitter nobody can see while every runtime check still passes. That guard is
# only useful if the shipped pin tracks the shipped kernel. It silently lapsed
# at review8 and went unnoticed until the bridge refused to start on review10,
# so tie the two together here rather than relying on anyone remembering.
bridge_conf="$repo_root/rootfs/etc/sp11-ir-bridge.conf"
bridge_pin="$(awk -F= '/^SP11_EXPECTED_KERNEL_RELEASE=/{print $2}' "$bridge_conf")"
build_release="$(awk -F'"' '/^release=/{print $2}' "$repo_root/scripts/build-kernel.sh")"
[[ -n "$bridge_pin" && -n "$build_release" ]] || {
	printf 'Could not read the IR bridge pin or the build release.\n' >&2
	exit 1
}
[[ "$bridge_pin" == "$build_release" ]] || {
	printf 'IR bridge pin %s does not match the build release %s.\n' \
		"$bridge_pin" "$build_release" >&2
	exit 1
}

for identity_script in scripts/install.sh scripts/assemble-payload.sh scripts/verify.sh; do
	script_release="$(awk -F'"' '/^release=/{print $2; exit}' \
		"$repo_root/$identity_script")"
	[[ "$script_release" == "$build_release" ]] || {
		printf '%s release %s does not match build release %s.\n' \
			"$identity_script" "$script_release" "$build_release" >&2
		exit 1
	}
done

for identity_script in scripts/install.sh scripts/assemble-payload.sh scripts/verify.sh; do
	rg -qF 'a2118d41b4edb8f6b11c050d9ca2c6208e30da1472f4f198959f0f0b44fb8bde' \
		"$repo_root/$identity_script"
	rg -qF '54a14d4f6841740e9a911affc58e2b17f097fb900d38472fd0386be311b6cead' \
		"$repo_root/$identity_script"
done

rg -qF 'SP11_KERNEL_STAGE' "$repo_root/scripts/assemble-payload.sh"
rg -qF 'LOCAL-STAGING-NOT-FOR-RELEASE' \
	"$repo_root/scripts/assemble-payload.sh"
rg -qF 'expected_module_count=3767' \
	"$repo_root/scripts/assemble-payload.sh"
if rg -q 'SP11_QUALIFIED_BOOT_DIR|-C /usr/lib/modules' \
	"$repo_root/scripts/assemble-payload.sh"; then
	printf 'Payload assembler still depends on live host kernel artifacts.\n' >&2
	exit 1
fi

rg -qF -- '--local-staging' \
	"$repo_root/scripts/build-held-live-image.sh"
rg -qF 'audit-held-live-image.sh' \
	"$repo_root/scripts/build-held-live-image.sh"
rg -qF 'empty-pacman-hooks' \
	"$repo_root/scripts/build-held-live-image.sh"
if rg -q 'modconf' "$repo_root/iso/mkinitcpio.conf"; then
	printf 'Generic host modprobe policy is enabled in the live initramfs.\n' >&2
	exit 1
fi

for source_identity in \
	18d7951a10dc49e383d16c6af82fc2c07784de3d \
	a83bc1232f7096f8b33b50fdbda249cd640de670 \
	5b4994c8a91290481bef87a5bae95391d0ec677f; do
	rg -qF "$source_identity" "$repo_root/scripts/assemble-source.sh"
done
rg -qF 'subprojects/fmt-12.0.0/LICENSE' \
	"$repo_root/scripts/assemble-source.sh"
if rg -q '/home/|turbinebmw|archive-private|lab-private' \
	"$repo_root/scripts/assemble-source.sh"; then
	printf 'Source assembler contains a private host path.\n' >&2
	exit 1
fi

rg -qF 'mem_sleep_default=deep' "$repo_root/scripts/install.sh"
rg -qF 'qcom_ipcc.mask_summary_on_suspend=1' "$repo_root/scripts/install.sh"
rg -qF 'sp11_deep_idle=1' "$repo_root/scripts/install.sh"
if rg -q 'mem_sleep_default=s2idle|clk_ignore_unused|pd_ignore_unused' \
	"$repo_root/scripts/install.sh"; then
	printf 'Obsolete or unqualified kernel command-line option remains in installer.\n' >&2
	exit 1
fi

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

if rg -n -i 'qccammipicsi|cphy-win-tables|camnoc-win-tables|/home/|WillzDenali' "$touch_patch"; then
	printf 'Withdrawn, private, or host-specific material found in touch patch.\n' >&2
	exit 1
fi

if rg -n -i 'qccammipicsi|cphy-win-tables|camnoc-win-tables|/home/|WillzDenali' "$resume_patch"; then
	printf 'Withdrawn, private, or host-specific material found in tablet-mode resume patch.\n' >&2
	exit 1
fi

if rg -n -i 'qccammipicsi|cphy-win-tables|camnoc-win-tables|/home/|WillzDenali' "$charge_patch"; then
	printf 'Withdrawn, private, or host-specific material found in charge-limit patch.\n' >&2
	exit 1
fi

if rg -n -i 'qccammipicsi|cphy-win-tables|camnoc-win-tables|/home/|WillzDenali' "$switch_patch"; then
	printf 'Withdrawn, private, or host-specific material found in camera-switch patch.\n' >&2
	exit 1
fi

if rg -n -i 'qccammipicsi|cphy-win-tables|camnoc-win-tables|/home/|WillzDenali' "$ddc_patch"; then
	printf 'Withdrawn, private, or host-specific material found in DP DDC patch.\n' >&2
	exit 1
fi

if rg -n -i 'qccammipicsi|cphy-win-tables|camnoc-win-tables|vd55g0-win|com\.surface\.sensormodule|/home/|WillzDenali' "$review20_patch"; then
	printf 'Withdrawn, private, or host-specific material found in review20 patch.\n' >&2
	exit 1
fi

[[ "$(git bundle list-heads "$bundle" | wc -l)" -eq 1 ]]
[[ "$(git bundle list-heads "$camera_bundle" | wc -l)" -eq 1 ]]
[[ "$(git bundle list-heads "$touch_bundle" | wc -l)" -eq 1 ]]
[[ "$(git bundle list-heads "$resume_bundle" | wc -l)" -eq 1 ]]
[[ "$(git bundle list-heads "$charge_bundle" | wc -l)" -eq 1 ]]
[[ "$(git bundle list-heads "$switch_bundle" | wc -l)" -eq 1 ]]
[[ "$(git bundle list-heads "$ddc_bundle" | wc -l)" -eq 1 ]]
[[ "$(git bundle list-heads "$review20_bundle" | wc -l)" -eq 1 ]]

(
	cd -- "$repo_root"
	reuse lint
	git diff --check
	PYTHONDONTWRITEBYTECODE=1 \
		python3 userspace/power-profiles-daemon/test_sp11_power_profile_cpufreq.py
	PYTHONDONTWRITEBYTECODE=1 \
		python3 scripts/test-manifest-installed-rootfs.py
	bash -n scripts/*.sh rootfs/usr/local/libexec/sp11-bluetooth-address \
		iso/mkinitcpio/install/sp11live \
		rootfs/usr/lib/systemd/system-sleep/*.sh \
		rootfs/usr/lib/systemd/system-sleep/sp11-charge-limit \
		rootfs/usr/local/libexec/sp11-charge-limit \
		rootfs/usr/local/libexec/sp11-runtime-idle-suspend-guard \
		userspace/power/test-sp11-charge-limit.sh
	bash -n iso/mkinitcpio/hooks/sp11live
	if command -v shellcheck >/dev/null; then
		shellcheck scripts/*.sh iso/mkinitcpio/install/sp11live \
			iso/mkinitcpio/hooks/sp11live \
			rootfs/usr/local/libexec/sp11-bluetooth-address \
			rootfs/usr/lib/systemd/system-sleep/*.sh \
			rootfs/usr/lib/systemd/system-sleep/sp11-charge-limit \
			rootfs/usr/local/libexec/sp11-charge-limit \
			rootfs/usr/local/libexec/sp11-runtime-idle-suspend-guard \
			userspace/power/test-sp11-charge-limit.sh
	fi
	frozen_snapshot="${SP11_PACKAGE_SNAPSHOT:-}"
	for snapshot_candidate in \
		work/package-snapshot-rnote-20260729 \
		work/firmware-v2-rebuild-inputs/package-snapshot-rnote-20260729; do
		[[ -n "$frozen_snapshot" || ! -d "$snapshot_candidate" ]] ||
			frozen_snapshot="$snapshot_candidate"
	done
	if [[ -n "$frozen_snapshot" ]]; then
		scripts/audit-package-lock.sh --frozen-snapshot "$frozen_snapshot"
	else
		# Without a frozen snapshot this compares against the host's current
		# mirrors, which drift as Arch Linux ARM moves; expect a drift report.
		scripts/audit-package-lock.sh
	fi
	scripts/audit-firmware-manifest.sh
	userspace/power/test-sp11-charge-limit.sh
)

printf 'Static source-publication audit passed.\n'
