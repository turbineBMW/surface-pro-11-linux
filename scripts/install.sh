#!/bin/bash

set -euo pipefail

release="7.1.3-sp11-sanitized2"
entry_id="sp11-alpha"
expected_dmi="Microsoft Surface Pro, 11th Edition"
expected_compatible="microsoft,denali"
expected_image="d95b1cbba0e017f2430e65ce6ca5e3e276ef3d0dbcab7f68e999db2dd4143152"
expected_dtb="3de1d2e6b0d40fef35866ef6e024cb5164f30f1e44f0c0d0051cc7cf9a384ede"
expected_iptsd="45ce0fcabdda04a9fcf3ce30f7f0c64ba7098fd2351127ef0e54cf0ac0b3f083"
expected_checker="54fcdaef90b0bd4239df670865cf8b258c3ae6e3988e42b0b9a3b58aaa4b08f5"
expected_ppd="9e1d72935f2b916de1c44950e425948e60c7bdf83c69bede2a079e7a79a82252"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
rootfs="$repo_root/rootfs"
payload=""
apply=0
unsafe_hardware=0

usage() {
	cat <<EOF
Usage: sudo $0 --payload DIRECTORY [--apply] [--unsafe-hardware]

Without --apply, perform a read-only preflight.
EOF
}

if [[ -e "$repo_root/BINARY-RELEASE-HOLD.md" ]]; then
	printf 'Refusing installation: no reviewed binary payload is published.\n' >&2
	printf 'See %s/BINARY-RELEASE-HOLD.md and docs/INSTALL.md.\n' "$repo_root" >&2
	exit 1
fi

while (($#)); do
	case "$1" in
		--payload) payload="$2"; shift 2 ;;
		--apply) apply=1; shift ;;
		--unsafe-hardware) unsafe_hardware=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done

[[ $EUID -eq 0 ]] || { printf 'Run with sudo/root.\n' >&2; exit 1; }
[[ -n "$payload" ]] || { usage >&2; exit 2; }
payload="$(cd -- "$payload" && pwd -P)"

required_commands=(awk btmgmt depmod find findmnt fuser grub-mkconfig install \
	mkinitcpio python3 sha256sum systemctl systemd-escape tar udevadm zstd)
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

root_uuid="$(findmnt -no UUID -T / | head -n1)"
boot_uuid="$(findmnt -no UUID -T /boot | head -n1)"
boot_mount="$(findmnt -no TARGET -T /boot | head -n1)"
[[ "$root_uuid" =~ ^[0-9A-Fa-f-]+$ && "$boot_uuid" =~ ^[0-9A-Fa-f-]+$ ]] || {
	printf 'Could not safely determine root/boot filesystem UUIDs.\n' >&2
	exit 1
}
if [[ "$boot_mount" == "/" ]]; then
	grub_boot_dir="/boot/sp11-alpha"
elif [[ "$boot_mount" == "/boot" ]]; then
	grub_boot_dir="/sp11-alpha"
else
	printf 'Unsupported /boot mount target: %s\n' "$boot_mount" >&2
	exit 1
fi

module_dir="/usr/lib/modules/$release"
boot_dir="/boot/sp11-alpha"
if [[ -e "$module_dir" || -e "$boot_dir" ]]; then
	printf 'Refusing collision with an existing alpha kernel:\n' >&2
	[[ -e "$module_dir" ]] && printf '  %s\n' "$module_dir" >&2
	[[ -e "$boot_dir" ]] && printf '  %s\n' "$boot_dir" >&2
	exit 1
fi

printf '\nSP11 sanitized candidate preflight passed.\n'
printf 'DMI:        %s\n' "$dmi"
printf 'Kernel:     %s\n' "$release"
printf 'Root UUID:  %s\n' "$root_uuid"
printf 'Boot UUID:  %s\n' "$boot_uuid"
printf 'GRUB path:  %s\n' "$grub_boot_dir"
printf 'Payload:    %s\n' "$payload"
printf 'Persistent GRUB default will not be changed.\n'

if [[ $apply -ne 1 ]]; then
	printf '\nPreflight only. Re-run with --apply after reviewing this output.\n'
	exit 0
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
state_dir="/var/lib/sp11-alpha"
backup_dir="$state_dir/backups/$timestamp"
backup_root="$backup_dir/root"
created_files="$backup_dir/created-files.list"
mkdir -p -- "$backup_root"
: >"$created_files"

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

mkdir -p -- "$module_dir" "$boot_dir"
printf '%s\n' "$module_dir" >"$backup_dir/created-trees.list"
printf '%s\n' "$boot_dir" >>"$backup_dir/created-trees.list"
tar --zstd -xf "$payload/modules-$release.tar.zst" -C /usr/lib/modules
install -m0644 "$payload/Image-$release" "$boot_dir/Image-$release"
install -m0644 "$payload/x1e80100-microsoft-denali-oled.dtb" \
	"$boot_dir/x1e80100-microsoft-denali-oled.dtb"

while IFS= read -r -d '' source_file; do
	relative_file="${source_file#"$rootfs"}"
	install_tracked "$source_file" "$relative_file"
done < <(find "$rootfs" -type f -print0 | LC_ALL=C sort -z)

install_tracked "$payload/sp11-iptsd" /usr/local/libexec/sp11-iptsd
install_tracked "$payload/sp11-iptsd-check-device" \
	/usr/local/libexec/sp11-iptsd-check-device
install_tracked "$payload/power-profiles-daemon-sp11" \
	/usr/local/libexec/power-profiles-daemon-sp11

sleep_link="/usr/lib/systemd/system-sleep/sp11-power-profile-cpufreq"
backup_destination "$sleep_link"
rm -f -- "$sleep_link"
ln -s /usr/local/libexec/sp11-power-profile-cpufreq "$sleep_link"

depmod "$release"
mkinitcpio -k "$release" -g "$boot_dir/initramfs-$release.img"

grub_fragment="/etc/grub.d/09_sp11_alpha"
backup_destination "$grub_fragment"
grub_temporary="$(mktemp)"
cat >"$grub_temporary" <<EOF
#!/bin/sh
exec tail -n +3 \$0

menuentry 'Surface Pro 11 Linux sanitized candidate ($release)' --class arch --class gnu-linux --class gnu --class os --id '$entry_id' {
    load_video
    set gfxpayload=keep
    insmod part_gpt
    insmod ext2
    search --no-floppy --fs-uuid --set=root $boot_uuid
    echo 'Loading Surface Pro 11 sanitized candidate ...'
    linux $grub_boot_dir/Image-$release root=UUID=$root_uuid rw clk_ignore_unused pd_ignore_unused loglevel=7 systemd.tpm2_wait=false efi_pstore.pstore_disable=0 mem_sleep_default=s2idle cpufreq.default_governor=schedutil
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
systemctl enable sp11-noidle.service
systemctl enable sp11-power-profile-cpufreq.service

cat >"$backup_dir/install-info" <<EOF
release=$release
entry_id=$entry_id
installed_at=$timestamp
root_uuid=$root_uuid
boot_uuid=$boot_uuid
EOF
ln -sfn "$backup_dir" "$state_dir/latest"

printf '\nInstallation complete. Existing GRUB default was not changed.\n'
printf 'Test once with: grub-reboot %s && reboot\n' "$entry_id"
printf 'Backup/rollback state: %s\n' "$backup_dir"
