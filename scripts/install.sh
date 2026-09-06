#!/bin/bash

set -euo pipefail

release="7.2.0-sp11-73beta1"
entry_id="sp11-beta-port73"
expected_dmi="Microsoft Surface Pro, 11th Edition"
expected_compatible="microsoft,denali"
expected_image="a2118d41b4edb8f6b11c050d9ca2c6208e30da1472f4f198959f0f0b44fb8bde"
expected_dtb="54a14d4f6841740e9a911affc58e2b17f097fb900d38472fd0386be311b6cead"
expected_iptsd="45ce0fcabdda04a9fcf3ce30f7f0c64ba7098fd2351127ef0e54cf0ac0b3f083"
expected_checker="54fcdaef90b0bd4239df670865cf8b258c3ae6e3988e42b0b9a3b58aaa4b08f5"
expected_ppd="9e1d72935f2b916de1c44950e425948e60c7bdf83c69bede2a079e7a79a82252"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
rootfs="$repo_root/rootfs"
payload=""
apply=0
unsafe_hardware=0
held_local_test=0
held_confirmation=""
reuse_compatible_modules=0
repair=0
arm_one_shot=0
managed_services=(
	power-profiles-daemon.service
	sp11-bluetooth-address.service
	sp11-cpufreq-boost.service
	sp11-power-profile-cpufreq.service
	sp11-charge-limit.service
)

usage() {
	cat <<EOF
Usage: sudo $0 --payload DIRECTORY [options]

Without --apply, perform a read-only preflight.

Options:
  --held-local-test, --confirm-held-local-install $entry_id
      Accepted for compatibility with older instructions (no longer required).
  --reuse-compatible-modules
      Reuse an existing $release module tree only after every payload module
      has the exact expected size and SHA-256. Extra host modules are reported.
  --repair
      Back up and replace an existing beta boot directory/GRUB fragment.
  --arm-one-shot
      Arm $entry_id for the next boot only after a successful install.
  --unsafe-hardware
      Override the exact DMI/device-tree hardware gate.
EOF
}

while (($#)); do
	case "$1" in
	--payload) payload="$2"; shift 2 ;;
	--apply) apply=1; shift ;;
	--held-local-test) held_local_test=1; shift ;;
	--confirm-held-local-install)
		held_confirmation="$2"
		shift 2
		;;
	--reuse-compatible-modules) reuse_compatible_modules=1; shift ;;
	--repair) repair=1; shift ;;
	--arm-one-shot) arm_one_shot=1; shift ;;
	--unsafe-hardware) unsafe_hardware=1; shift ;;
	-h|--help) usage; exit 0 ;;
	*) usage >&2; exit 2 ;;
	esac
done

[[ $EUID -eq 0 ]] || { printf 'Run with sudo/root.\n' >&2; exit 1; }
[[ -n "$payload" ]] || { usage >&2; exit 2; }
payload="$(cd -- "$payload" && pwd -P)"

# The former binary-release hold is lifted for the beta; --held-local-test and
# --confirm-held-local-install are still accepted so older instructions work.
hold_active=0
if [[ $arm_one_shot -eq 1 && $apply -ne 1 ]]; then
	printf '--arm-one-shot is valid only with --apply.\n' >&2
	exit 2
fi
if [[ -n "$held_confirmation" && $apply -ne 1 ]]; then
	printf '--confirm-held-local-install is valid only with --apply.\n' >&2
	exit 2
fi

required_commands=(awk btmgmt cmp depmod df efibootmgr find findmnt fuser \
	grep grub-editenv grub-mkconfig grub-reboot install lsinitcpio lsblk \
	mkinitcpio mountpoint python3 readlink sha256sum stat systemctl \
	systemd-escape tar taskset udevadm zstd)
for command_name in "${required_commands[@]}"; do
	command -v "$command_name" >/dev/null || {
		printf 'Missing required command: %s\n' "$command_name" >&2
		exit 1
	}
done

[[ "$(uname -m)" == "aarch64" ]] || {
	printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2
	exit 1
}
dmi="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
compatible="$(tr '\0' '\n' </proc/device-tree/compatible 2>/dev/null || true)"
if [[ "$dmi" != "$expected_dmi" ]] || ! grep -Fxq "$expected_compatible" <<<"$compatible"; then
	if [[ $unsafe_hardware -ne 1 ]]; then
		printf 'Hardware mismatch. DMI=%q; expected compatible=%s\n' \
			"$dmi" "$expected_compatible" >&2
		exit 1
	fi
	printf 'WARNING: unsafe hardware override accepted.\n' >&2
fi

required_payload=(
	"Image-$release"
	x1e80100-microsoft-denali-oled.dtb
	"modules-$release.tar.zst"
	MODULES.tsv
	sp11-iptsd
	sp11-iptsd-check-device
	power-profiles-daemon-sp11
	SHA256SUMS
)
for payload_file in "${required_payload[@]}"; do
	[[ -f "$payload/$payload_file" ]] || {
		printf 'Missing payload file: %s\n' "$payload_file" >&2
		exit 1
	}
done
(
	cd -- "$payload"
	sha256sum -c SHA256SUMS
)

check_exact_hash() {
	local source_file="$1"
	local expected_hash="$2"
	local actual_hash
	actual_hash="$(sha256sum "$source_file" | awk '{print $1}')"
	[[ "$actual_hash" == "$expected_hash" ]] || {
		printf 'Hash mismatch: %s\n' "$source_file" >&2
		exit 1
	}
}
check_exact_hash "$payload/Image-$release" "$expected_image"
check_exact_hash "$payload/x1e80100-microsoft-denali-oled.dtb" "$expected_dtb"
check_exact_hash "$payload/sp11-iptsd" "$expected_iptsd"
check_exact_hash "$payload/sp11-iptsd-check-device" "$expected_checker"
check_exact_hash "$payload/power-profiles-daemon-sp11" "$expected_ppd"

awk -F '\t' '
	NR == 1 {
		if ($0 != "path\tbytes\tsha256")
			exit 1
		next
	}
	NF != 3 ||
	$1 !~ /^kernel\/.*\.ko$/ ||
	$1 ~ /(^|\/)\.\.?(\/|$)/ ||
	$2 !~ /^[0-9]+$/ ||
	$3 !~ /^[0-9a-f]{64}$/ {
		exit 1
	}
	{ count++ }
	END { exit count != 3767 }
' "$payload/MODULES.tsv" || {
	printf 'Malformed or incomplete module manifest.\n' >&2
	exit 1
}
archive_module_count="$(
	tar --zstd -tf "$payload/modules-$release.tar.zst" |
		awk -v release="$release" '
			index($0, "/../") || $0 ~ /^\// { exit 2 }
			$0 ~ ("^" release "/kernel/.*\\.ko$") { count++ }
			END { print count + 0 }
		'
)" || {
	printf 'Unsafe module archive member.\n' >&2
	exit 1
}
[[ "$archive_module_count" -eq 3767 ]] || {
	printf 'Module archive contains %s modules, expected 3767.\n' \
		"$archive_module_count" >&2
	exit 1
}

root_uuid="$(findmnt -no UUID -T / | head -n1)"
boot_uuid="$(findmnt -no UUID -T /boot | head -n1)"
boot_mount="$(findmnt -no TARGET -T /boot | head -n1)"
root_source="$(findmnt -no SOURCE -T / | head -n1)"
boot_source="$(findmnt -no SOURCE -T /boot | head -n1)"
[[ "$root_uuid" =~ ^[0-9A-Fa-f-]+$ && "$boot_uuid" =~ ^[0-9A-Fa-f-]+$ ]] || {
	printf 'Could not safely determine root/boot filesystem UUIDs.\n' >&2
	exit 1
}
[[ -n "$root_source" && -n "$boot_source" ]] || {
	printf 'Could not safely determine root/boot block devices.\n' >&2
	exit 1
}
if [[ "$boot_mount" == "/" ]]; then
	grub_boot_dir="/boot/sp11-beta"
elif [[ "$boot_mount" == "/boot" ]]; then
	grub_boot_dir="/sp11-beta"
else
	printf 'Unsupported /boot mount target: %s\n' "$boot_mount" >&2
	exit 1
fi

module_dir="/usr/lib/modules/$release"
boot_dir="/boot/sp11-beta"
grub_fragment="/etc/grub.d/09_sp11_beta"
module_state="fresh"
installed_module_count=0
extra_module_count=0
if [[ -e "$module_dir" || -L "$module_dir" ]]; then
	[[ -d "$module_dir" && ! -L "$module_dir" ]] || {
		printf 'Unsafe existing module-tree type: %s\n' "$module_dir" >&2
		exit 1
	}
	[[ $reuse_compatible_modules -eq 1 ]] || {
		printf 'Existing module tree requires --reuse-compatible-modules: %s\n' \
			"$module_dir" >&2
		exit 1
	}
	printf 'Verifying all 3,767 payload modules in the existing tree ...\n'
	verified_modules=0
	relocated_modules=0
	while IFS=$'\t' read -r module_path expected_size expected_sha; do
		[[ "$module_path" != "path" ]] || continue
		installed_module="$module_dir/$module_path"
		if [[ ! -f "$installed_module" &&
			"$module_path" == \
			"kernel/drivers/clk/qcom/videocc-sm8550.ko" ]]; then
			relocated_module="$module_dir/updates/diagnostic/videocc-sm8550.ko"
			if [[ -f "$relocated_module" && ! -L "$relocated_module" ]]; then
				installed_module="$relocated_module"
				((relocated_modules += 1))
			fi
		fi
		[[ -f "$installed_module" && ! -L "$installed_module" ]] || {
			printf 'Compatible-module reuse is missing: %s\n' \
				"$installed_module" >&2
			exit 1
		}
		[[ "$(stat -c '%s' "$installed_module")" == "$expected_size" &&
			"$(sha256sum "$installed_module" | awk '{print $1}')" == \
			"$expected_sha" ]] || {
			printf 'Compatible-module reuse mismatch: %s\n' \
				"$installed_module" >&2
			exit 1
		}
		((verified_modules += 1))
	done <"$payload/MODULES.tsv"
	[[ "$verified_modules" -eq 3767 ]]
	installed_module_count="$(
		find "$module_dir" -type f -name '*.ko' -printf . | wc -c
	)"
	extra_module_count=$((installed_module_count - verified_modules))
	[[ "$extra_module_count" -ge 0 ]]
	module_state="reuse-compatible"
fi

boot_state="fresh"
if [[ -e "$boot_dir" || -L "$boot_dir" ||
	-e "$grub_fragment" || -L "$grub_fragment" ]]; then
	[[ $repair -eq 1 ]] || {
		printf 'Existing beta boot state requires --repair:\n' >&2
		[[ -e "$boot_dir" || -L "$boot_dir" ]] &&
			printf '  %s\n' "$boot_dir" >&2
		[[ -e "$grub_fragment" || -L "$grub_fragment" ]] &&
			printf '  %s\n' "$grub_fragment" >&2
		exit 1
	}
	[[ ! -L "$boot_dir" && ! -L "$grub_fragment" ]] || {
		printf 'Refusing repair through a symlinked boot target.\n' >&2
		exit 1
	}
	boot_state="repair"
fi

windows_loader="/efi/EFI/Microsoft/Boot/bootmgfw.efi"
[[ -f "$windows_loader" && ! -L "$windows_loader" ]] || {
	printf 'Windows Boot Manager is missing from the EFI System Partition.\n' >&2
	exit 1
}
read -r efi_mount efi_fstype efi_source < <(
	findmnt -rn -R /efi -t vfat -o TARGET,FSTYPE,SOURCE |
		tail -n1
)
[[ "$efi_mount" == "/efi" && "$efi_fstype" == "vfat" &&
	-n "$efi_source" ]] || {
	printf 'The EFI System Partition must be mounted at /efi as vfat.\n' >&2
	exit 1
}
windows_loader_sha="$(sha256sum "$windows_loader" | awk '{print $1}')"
efiboot_output="$(efibootmgr -v)"
grep -Fq 'Windows Boot Manager' <<<"$efiboot_output" || {
	printf 'Windows Boot Manager EFI entry is missing.\n' >&2
	exit 1
}
grep -RqsF 'chainloader /EFI/Microsoft/Boot/bootmgfw.efi' /etc/grub.d || {
	printf 'The preserved GRUB Windows chainloader fragment is missing.\n' >&2
	exit 1
}
grub_cfg="/boot/grub/grub.cfg"
grub_env="/boot/grub/grubenv"
[[ -f "$grub_cfg" && ! -L "$grub_cfg" &&
	-f "$grub_env" && ! -L "$grub_env" ]] || {
	printf 'The installed GRUB configuration/environment is incomplete.\n' >&2
	exit 1
}
next_entry="$(
	grub-editenv "$grub_env" list |
		sed -n 's/^next_entry=//p' |
		head -n1
)"
[[ -z "$next_entry" ]] || {
	printf 'Refusing while GRUB already has a pending one-shot entry: %s\n' \
		"$next_entry" >&2
	exit 1
}
known_good_entries="$(
	grep -c '^menuentry ' "$grub_cfg" || true
)"
[[ "$known_good_entries" -ge 2 ]] || {
	printf 'Fewer than two preserved GRUB menu entries were found.\n' >&2
	exit 1
}
root_free_bytes="$(df -B1 --output=avail / | awk 'NR == 2 { print $1 }')"
boot_free_bytes="$(df -B1 --output=avail /boot | awk 'NR == 2 { print $1 }')"
[[ "$root_free_bytes" -ge 536870912 &&
	"$boot_free_bytes" -ge 134217728 ]] || {
	printf 'Insufficient free space: root=%s boot=%s bytes.\n' \
		"$root_free_bytes" "$boot_free_bytes" >&2
	exit 1
}

printf '\nSP11 beta candidate preflight passed.\n'
printf 'DMI:        %s\n' "$dmi"
printf 'Kernel:     %s\n' "$release"
printf 'Root:       %s (UUID %s)\n' "$root_source" "$root_uuid"
printf 'Boot:       %s (UUID %s)\n' "$boot_source" "$boot_uuid"
printf 'EFI:        %s (%s)\n' "$efi_source" "$efi_fstype"
printf 'Windows:    present, SHA-256 %s\n' "$windows_loader_sha"
printf 'GRUB:       %s preserved entries, no pending one-shot\n' \
	"$known_good_entries"
printf 'GRUB path:  %s\n' "$grub_boot_dir"
printf 'Modules:    %s' "$module_state"
if [[ "$module_state" == "reuse-compatible" ]]; then
	printf ' (%s expected + %s extra host modules)' \
		"$verified_modules" "$extra_module_count"
	if [[ "$relocated_modules" -eq 1 ]]; then
		printf ', exact VideoCC promotion relocation accepted'
	fi
fi
printf '\n'
printf 'Boot state: %s\n' "$boot_state"
printf 'Payload:    %s\n' "$payload"
if [[ $hold_active -eq 1 ]]; then
	printf 'Release:    HELD LOCAL ENGINEERING TEST ONLY\n'
fi
printf 'Persistent GRUB default will not be changed.\n'

if [[ $apply -ne 1 ]]; then
	printf '\nPreflight only. Re-run with --apply after reviewing this output.\n'
	exit 0
fi

for writable_target in / /boot; do
	mount_options="$(findmnt -no OPTIONS -T "$writable_target" | head -n1)"
	case ",$mount_options," in
	*,rw,*) ;;
	*)
		printf 'Apply requires a writable target: %s\n' "$writable_target" >&2
		exit 1
		;;
	esac
done

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
state_dir="/var/lib/sp11-beta"
backup_dir="$state_dir/backups/$timestamp"
backup_root="$backup_dir/root"
created_files="$backup_dir/created-files.list"
mkdir -p -- "$backup_root"
: >"$created_files"
printf 'incomplete\n' >"$backup_dir/transaction-status"
transaction_complete=0
transaction_notice() {
	if [[ $transaction_complete -ne 1 ]]; then
		printf '\nINSTALL TRANSACTION INCOMPLETE.\n' >&2
		printf 'Do not reboot until this state is reviewed: %s\n' \
			"$backup_dir" >&2
	fi
}
trap transaction_notice EXIT

printf '%s\n' "$efiboot_output" >"$backup_dir/efibootmgr-before.txt"
grub-editenv "$grub_env" list >"$backup_dir/grubenv-before.txt"
sha256sum "$grub_cfg" "$windows_loader" \
	>"$backup_dir/boot-identities-before.sha256"
find /etc/grub.d -maxdepth 1 -type f -print0 |
	LC_ALL=C sort -z |
	xargs -0 sha256sum >"$backup_dir/grub-fragments-before.sha256"
{
	printf 'unit\tstate\n'
	for managed_service in "${managed_services[@]}"; do
		service_state="$(
			systemctl is-enabled "$managed_service" 2>/dev/null || true
		)"
		[[ "$service_state" =~ ^(enabled|enabled-runtime|disabled|static|\
indirect|masked|masked-runtime|linked|linked-runtime|alias|generated|\
transient|not-found)$ ]] || {
			printf 'Unsafe service enablement state for %s: %q\n' \
				"$managed_service" "$service_state" >&2
			exit 1
		}
		printf '%s\t%s\n' "$managed_service" "$service_state"
	done
} >"$backup_dir/systemd-enable-state-before.tsv"

backup_destination() {
	local destination="$1"
	if [[ -e "$destination" || -L "$destination" ]]; then
		mkdir -p -- "$backup_root$(dirname -- "$destination")"
		cp -a -- "$destination" "$backup_root$destination"
	else
		printf '%s\n' "$destination" >>"$created_files"
	fi
}

install_tracked() {
	local source_file="$1"
	local destination="$2"
	local source_mode
	source_mode="$(stat -c '%a' "$source_file")"
	backup_destination "$destination"
	install -D -m "$source_mode" "$source_file" "$destination"
}

if [[ "$module_state" == "fresh" ]]; then
	mkdir -p -- "$module_dir"
	printf '%s\n' "$module_dir" >"$backup_dir/created-trees.list"
	tar --zstd -xf "$payload/modules-$release.tar.zst" -C /usr/lib/modules
else
	: >"$backup_dir/created-trees.list"
	printf '%s\n' "$module_dir" >"$backup_dir/reused-trees.list"
fi
if [[ "$boot_state" == "repair" ]] &&
	[[ -e "$boot_dir" || -L "$boot_dir" ]]; then
	backup_destination "$boot_dir"
else
	mkdir -p -- "$boot_dir"
	printf '%s\n' "$boot_dir" >>"$backup_dir/created-trees.list"
fi
install -m0644 "$payload/Image-$release" "$boot_dir/Image-$release"
install -m0644 "$payload/x1e80100-microsoft-denali-oled.dtb" \
	"$boot_dir/x1e80100-microsoft-denali-oled.dtb"

while IFS= read -r -d '' source_file; do
	relative_file="${source_file#"$rootfs"}"
	install_tracked "$source_file" "$relative_file"
done < <(find "$rootfs" -type f -print0 | LC_ALL=C sort -z)

while IFS=$'\t' read -r relative_link entry_type target; do
	[[ "$relative_link" != "path" && "$entry_type" == "symlink" ]] ||
		continue
	source_link="$rootfs/usr/share/alsa/ucm2/$relative_link"
	destination_link="/usr/share/alsa/ucm2/$relative_link"
	[[ -L "$source_link" && "$(readlink "$source_link")" == "$target" ]] || {
		printf 'UCM selector symlink identity mismatch: %s\n' \
			"$relative_link" >&2
		exit 1
	}
	backup_destination "$destination_link"
	rm -f -- "$destination_link"
	install -d -m0755 "$(dirname -- "$destination_link")"
	ln -s -- "$target" "$destination_link"
done <"$repo_root/iso/audio-ucm.tsv"

install_tracked "$payload/sp11-iptsd" /usr/local/libexec/sp11-iptsd
install_tracked "$payload/sp11-iptsd-check-device" \
	/usr/local/libexec/sp11-iptsd-check-device
install_tracked "$payload/power-profiles-daemon-sp11" \
	/usr/local/libexec/power-profiles-daemon-sp11

sleep_link="/usr/lib/systemd/system-sleep/sp11-power-profile-cpufreq"
backup_destination "$sleep_link"
rm -f -- "$sleep_link"
ln -s /usr/local/libexec/sp11-power-profile-cpufreq "$sleep_link"

if [[ "$module_state" == "fresh" ]]; then
	depmod "$release"
fi
mkinitcpio -k "$release" -g "$boot_dir/initramfs-$release.img"
if ! lsinitcpio "$boot_dir/initramfs-$release.img" |
	grep -Eq '(^|/)videocc-sm8550\.ko(\.(gz|xz|zst))?$'; then
	printf 'Generated initramfs is missing the required X1E VideoCC module.\n' >&2
	exit 1
fi

backup_destination "$grub_fragment"
grub_temporary="$(mktemp)"
cat >"$grub_temporary" <<EOF
#!/bin/sh
exec tail -n +3 \$0

menuentry 'Surface Pro 11 Linux beta candidate ($release)' --class arch --class gnu-linux --class gnu --class os --id '$entry_id' {
    load_video
    set gfxpayload=keep
    insmod part_gpt
    insmod ext2
    search --no-floppy --fs-uuid --set=root $boot_uuid
    echo 'Loading Surface Pro 11 beta candidate ...'
    linux $grub_boot_dir/Image-$release root=UUID=$root_uuid rw loglevel=7 systemd.tpm2_wait=false efi_pstore.pstore_disable=0 mem_sleep_default=deep cpufreq.default_governor=schedutil quiet splash
    devicetree $grub_boot_dir/x1e80100-microsoft-denali-oled.dtb
    echo 'Loading initial ramdisk ...'
    initrd $grub_boot_dir/initramfs-$release.img
}
EOF
install -m0755 "$grub_temporary" "$grub_fragment"
rm -f -- "$grub_temporary"
grub-mkconfig -o /boot/grub/grub.cfg

systemctl daemon-reload
udevadm control --reload
systemctl enable power-profiles-daemon.service
systemctl enable sp11-bluetooth-address.service
systemctl enable sp11-cpufreq-boost.service
systemctl enable sp11-power-profile-cpufreq.service
systemctl enable sp11-charge-limit.service

[[ "$(sha256sum "$windows_loader" | awk '{print $1}')" == \
	"$windows_loader_sha" ]] || {
	printf 'Windows Boot Manager changed during installation.\n' >&2
	exit 1
}
efibootmgr -v | grep -Fq 'Windows Boot Manager' || {
	printf 'Windows Boot Manager EFI entry disappeared during installation.\n' >&2
	exit 1
}
grep -Fq -- "--id '$entry_id'" "$grub_fragment"
grep -Fq "chainloader /EFI/Microsoft/Boot/bootmgfw.efi" "$grub_cfg"
[[ "$(sha256sum "$boot_dir/Image-$release" | awk '{print $1}')" == \
	"$expected_image" ]]
[[ "$(sha256sum "$boot_dir/x1e80100-microsoft-denali-oled.dtb" |
	awk '{print $1}')" == "$expected_dtb" ]]

cat >"$backup_dir/install-info" <<EOF
release=$release
entry_id=$entry_id
installed_at=$timestamp
root_uuid=$root_uuid
boot_uuid=$boot_uuid
efi_source=$efi_source
windows_loader_sha256=$windows_loader_sha
module_state=$module_state
boot_state=$boot_state
EOF
if [[ $arm_one_shot -eq 1 ]]; then
	grub-reboot "$entry_id"
	armed_entry="$(
		grub-editenv "$grub_env" list |
			sed -n 's/^next_entry=//p' |
			head -n1
	)"
	[[ "$armed_entry" == "$entry_id" ]] || {
		printf 'Failed to verify the one-shot GRUB entry.\n' >&2
		exit 1
	}
fi

printf 'complete\n' >"$backup_dir/transaction-status"
{
	printf 'path\ttarget\n'
	while IFS= read -r -d '' state_link; do
		link_path="${state_link#"$backup_dir/"}"
		link_target="$(readlink -- "$state_link")"
		[[ "$link_path" != *$'\t'* && "$link_path" != *$'\n'* &&
			"$link_target" != *$'\t'* && "$link_target" != *$'\n'* ]] || {
			printf 'Unsafe rollback-state symlink identity: %s\n' \
				"$state_link" >&2
			exit 1
		}
		printf '%s\t%s\n' "$link_path" "$link_target"
	done < <(
		find "$backup_dir" -type l -print0 |
			LC_ALL=C sort -z
	)
} >"$backup_dir/state-symlinks.tsv"
(
	cd -- "$backup_dir"
	mapfile -d '' state_files < <(
		find . -type f ! -name STATE-SHA256SUMS -print0 |
			LC_ALL=C sort -z
	)
	sha256sum "${state_files[@]}" >STATE-SHA256SUMS
)
ln -sfn "$backup_dir" "$state_dir/latest"

transaction_complete=1
trap - EXIT
printf '\nInstallation complete. Existing GRUB default was not changed.\n'
if [[ $arm_one_shot -eq 1 ]]; then
	printf 'One-shot next boot armed: %s\n' "$entry_id"
else
	printf 'One-shot boot is not armed. Use: grub-reboot %s\n' "$entry_id"
fi
printf 'Backup/rollback state: %s\n' "$backup_dir"
