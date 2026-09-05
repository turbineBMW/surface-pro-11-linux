#!/bin/bash

# Verify an installed SP11 beta transaction before or after its one-shot boot.

set -euo pipefail

release="7.2.0-sp11-73beta1"
entry_id="sp11-beta-port73"
expected_image="a2118d41b4edb8f6b11c050d9ca2c6208e30da1472f4f198959f0f0b44fb8bde"
expected_dtb="54a14d4f6841740e9a911affc58e2b17f097fb900d38472fd0386be311b6cead"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
payload="$repo_root/payload"
state_path="/var/lib/sp11-beta/latest"
expect_one_shot=0
failures=0

usage() {
	cat <<EOF
Usage: sudo $0 [--payload DIRECTORY] [--state DIRECTORY] [--expect-one-shot]
EOF
}

while (($#)); do
	case "$1" in
	--payload) payload="$2"; shift 2 ;;
	--state) state_path="$2"; shift 2 ;;
	--expect-one-shot) expect_one_shot=1; shift ;;
	-h|--help) usage; exit 0 ;;
	*) usage >&2; exit 2 ;;
	esac
done

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*" >&2; failures=$((failures + 1)); }

[[ $EUID -eq 0 ]] || { printf 'Run with sudo/root.\n' >&2; exit 1; }
payload="$(realpath -e -- "$payload")"
state_path="$(readlink -f -- "$state_path")"
case "$state_path" in
/var/lib/sp11-beta/backups/*) ;;
*)
	printf 'Unsafe installation state path: %s\n' "$state_path" >&2
	exit 1
	;;
esac

if [[ -f "$state_path/transaction-status" &&
	"$(cat "$state_path/transaction-status")" == "complete" ]]; then
	pass "complete installation transaction"
else
	fail "complete installation transaction"
fi
if [[ -f "$state_path/STATE-SHA256SUMS" ]] &&
	(cd -- "$state_path" && sha256sum -c STATE-SHA256SUMS >/dev/null); then
	pass "rollback-state integrity"
else
	fail "rollback-state integrity"
fi
symlink_failures=0
symlink_count=0
if [[ -f "$state_path/state-symlinks.tsv" ]]; then
	while IFS=$'\t' read -r state_link state_target; do
		if [[ "$state_link" == "path" && "$state_target" == "target" ]]; then
			continue
		fi
		((symlink_count += 1))
		saved_link="$state_path/$state_link"
		if [[ "$state_link" != root/* ||
			"$state_link" == *"/../"* ||
			! -L "$saved_link" ||
			"$(readlink -- "$saved_link" 2>/dev/null || true)" != \
			"$state_target" ]]; then
			((symlink_failures += 1))
		fi
	done <"$state_path/state-symlinks.tsv"
	actual_symlink_count="$(
		find "$state_path/root" -type l -printf . 2>/dev/null | wc -c
	)"
	if [[ "$symlink_failures" -eq 0 &&
		"$symlink_count" -eq "$actual_symlink_count" ]]; then
		pass "rollback-state symlink identities"
	else
		fail "rollback-state symlinks: recorded=$symlink_count actual=$actual_symlink_count failures=$symlink_failures"
	fi
else
	fail "rollback-state symlink manifest"
fi
if [[ -f "$state_path/systemd-enable-state-before.tsv" ]] &&
	awk -F '\t' '
		NR == 1 {
			if ($0 != "unit\tstate")
				exit 1
			next
		}
		$1 !~ /^(power-profiles-daemon|sp11-bluetooth-address|sp11-cpufreq-boost|sp11-power-profile-cpufreq|sp11-charge-limit)\.service$/ ||
		$2 !~ /^(enabled|enabled-runtime|disabled|static|indirect|masked|masked-runtime|linked|linked-runtime|alias|generated|transient|not-found)$/ ||
		seen[$1]++ {
			exit 1
		}
		{ count++ }
		END { exit count != 5 }
	' "$state_path/systemd-enable-state-before.tsv"; then
	pass "rollback service-enablement baseline"
else
	fail "rollback service-enablement baseline"
fi

image="/boot/sp11-beta/Image-$release"
dtb="/boot/sp11-beta/x1e80100-microsoft-denali-oled.dtb"
if [[ -f "$image" &&
	"$(sha256sum "$image" | awk '{print $1}')" == "$expected_image" ]]; then
	pass "installed kernel Image identity"
else
	fail "installed kernel Image identity"
fi
if [[ -f "$dtb" &&
	"$(sha256sum "$dtb" | awk '{print $1}')" == "$expected_dtb" ]]; then
	pass "installed OLED DTB identity"
else
	fail "installed OLED DTB identity"
fi

manifest="$payload/MODULES.tsv"
if [[ -f "$manifest" ]]; then
	module_failures=0
	module_count=0
	relocated_modules=0
	while IFS=$'\t' read -r module_path expected_size expected_sha; do
		[[ "$module_path" != "path" ]] || continue
		module="/usr/lib/modules/$release/$module_path"
		((module_count += 1))
		if [[ ! -f "$module" &&
			"$module_path" == \
			"kernel/drivers/clk/qcom/videocc-sm8550.ko" ]]; then
			relocated_module="/usr/lib/modules/$release/updates/diagnostic/videocc-sm8550.ko"
			if [[ -f "$relocated_module" && ! -L "$relocated_module" ]]; then
				module="$relocated_module"
				((relocated_modules += 1))
			fi
		fi
		if [[ ! -f "$module" || -L "$module" ||
			"$(stat -c '%s' "$module" 2>/dev/null || true)" != \
			"$expected_size" ||
			"$(sha256sum "$module" 2>/dev/null | awk '{print $1}')" != \
			"$expected_sha" ]]; then
			((module_failures += 1))
		fi
	done <"$manifest"
	if [[ "$module_count" -eq 3767 && "$module_failures" -eq 0 ]]; then
		if [[ "$relocated_modules" -eq 1 ]]; then
			pass "all 3,767 installed module identities (exact VideoCC promotion relocation accepted)"
		else
			pass "all 3,767 installed module identities"
		fi
	else
		fail "installed modules: count=$module_count failures=$module_failures"
	fi
else
	fail "payload module manifest"
fi

initramfs="/boot/sp11-beta/initramfs-$release.img"
if [[ -f "$initramfs" ]] &&
	lsinitcpio "$initramfs" |
		grep -Eq '(^|/)videocc-sm8550\.ko(\.(gz|xz|zst))?$'; then
	pass "installed initramfs contains X1E VideoCC"
else
	fail "installed initramfs contains X1E VideoCC"
fi

grub_fragment="/etc/grub.d/09_sp11_beta"
if [[ -f "$grub_fragment" ]] &&
	grep -Fq -- "--id '$entry_id'" "$grub_fragment" &&
	grep -Fq "cpufreq.default_governor=schedutil" "$grub_fragment"; then
	pass "isolated beta GRUB fragment"
else
	fail "isolated beta GRUB fragment"
fi
if grep -Fq "chainloader /EFI/Microsoft/Boot/bootmgfw.efi" \
	/boot/grub/grub.cfg; then
	pass "Windows chainloader preserved in generated GRUB configuration"
else
	fail "Windows chainloader preserved in generated GRUB configuration"
fi

windows_loader="/efi/EFI/Microsoft/Boot/bootmgfw.efi"
expected_windows_sha="$(
	sed -n 's/^windows_loader_sha256=//p' "$state_path/install-info" 2>/dev/null
)"
if [[ "$expected_windows_sha" =~ ^[0-9a-f]{64}$ &&
	-f "$windows_loader" &&
	"$(sha256sum "$windows_loader" | awk '{print $1}')" == \
	"$expected_windows_sha" ]]; then
	pass "Windows Boot Manager file identity preserved"
else
	fail "Windows Boot Manager file identity preserved"
fi
if efibootmgr -v | grep -Fq "Windows Boot Manager"; then
	pass "Windows Boot Manager EFI entry preserved"
else
	fail "Windows Boot Manager EFI entry preserved"
fi

next_entry="$(
	grub-editenv /boot/grub/grubenv list |
		sed -n 's/^next_entry=//p' |
		head -n1
)"
if [[ $expect_one_shot -eq 1 ]]; then
	if [[ "$next_entry" == "$entry_id" ]]; then
		pass "one-shot beta boot armed"
	else
		fail "one-shot beta boot armed"
	fi
elif [[ -z "$next_entry" ]]; then
	pass "no unexpected pending one-shot boot"
else
	fail "unexpected pending one-shot boot: $next_entry"
fi

if [[ $failures -ne 0 ]]; then
	printf '\nInstalled-state verification failed: %s gate(s).\n' \
		"$failures" >&2
	exit 1
fi
printf '\nInstalled-state verification passed.\n'
