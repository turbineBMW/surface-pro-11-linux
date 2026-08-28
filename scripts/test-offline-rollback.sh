#!/bin/bash

# Exercise rollback.sh offline apply semantics inside a disposable mount
# namespace. No host installation path is writable in the test sandbox.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
rollback_script="$script_dir/rollback.sh"
test_root="$(mktemp -d /tmp/sp11-offline-rollback-test.XXXXXX)"
cleanup() {
	rm -rf -- "$test_root"
}
trap cleanup EXIT

model="$test_root/model"
fakebin="$test_root/fakebin"
state="$model/var/lib/sp11-beta/backups/20260729T000000Z"
mkdir -p \
	"$fakebin" \
	"$model/boot/grub" \
	"$model/boot/sp11-beta" \
	"$model/efi/EFI/Microsoft/Boot" \
	"$model/etc/grub.d" \
	"$model/run" \
	"$state/root/etc"

printf 'candidate\n' >"$model/etc/candidate.conf"
printf 'modified\n' >"$model/etc/original.conf"
ln -s wrong-target "$model/etc/original-link"
printf 'candidate boot\n' >"$model/boot/sp11-beta/Image-test"
printf 'candidate grub\n' >"$model/boot/grub/grub.cfg"
printf 'windows-loader\n' \
	>"$model/efi/EFI/Microsoft/Boot/bootmgfw.efi"

printf 'original\n' >"$state/root/etc/original.conf"
ln -s original.conf "$state/root/etc/original-link"
printf '/etc/candidate.conf\n' >"$state/created-files.list"
printf '/boot/sp11-beta\n' >"$state/created-trees.list"
printf 'complete\n' >"$state/transaction-status"
windows_sha="$(
	sha256sum "$model/efi/EFI/Microsoft/Boot/bootmgfw.efi" |
		awk '{print $1}'
)"
cat >"$state/install-info" <<EOF
release=7.1.3-sp11-suspend-review20
entry_id=sp11-beta-review20
installed_at=20260729T000000Z
root_uuid=test
boot_uuid=test
efi_source=/dev/test
windows_loader_sha256=$windows_sha
module_state=reuse-compatible
boot_state=fresh
EOF
cat >"$state/systemd-enable-state-before.tsv" <<'EOF'
unit	state
power-profiles-daemon.service	enabled
sp11-bluetooth-address.service	disabled
sp11-noidle.service	disabled
sp11-power-profile-cpufreq.service	disabled
sp11-charge-limit.service	enabled
EOF
cat >"$state/state-symlinks.tsv" <<'EOF'
path	target
root/etc/original-link	original.conf
EOF
(
	cd -- "$state"
	mapfile -d '' state_files < <(
		find . -type f ! -name STATE-SHA256SUMS -print0 |
			LC_ALL=C sort -z
	)
	sha256sum "${state_files[@]}" >STATE-SHA256SUMS
)
ln -s /var/lib/sp11-beta/backups/20260729T000000Z \
	"$model/var/lib/sp11-beta/latest"
printf 'sp11-beta-review20' \
	>"$model/run/sp11-live-offline-rollback-authorized"

cat >"$fakebin/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>/var/test-systemctl.log
EOF
cat >"$fakebin/depmod" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$fakebin/grub-mkconfig" <<'EOF'
#!/bin/bash
[[ "$1" == "-o" && "$2" == "/boot/grub/grub.cfg" ]]
printf '%s\n' \
	"menuentry 'Windows Boot Manager' {" \
	"    chainloader /EFI/Microsoft/Boot/bootmgfw.efi" \
	"}" >"$2"
EOF
cat >"$fakebin/grub-editenv" <<'EOF'
#!/bin/bash
if [[ "${2:-}" == "list" ]]; then
	printf 'next_entry=sp11-beta-review20\n'
fi
exit 0
EOF
cp -- "$rollback_script" "$fakebin/rollback.sh"
chmod 0755 "$fakebin"/*

bwrap \
	--die-with-parent \
	--unshare-all \
	--tmpfs / \
	--ro-bind /usr /usr \
	--symlink usr/bin /bin \
	--symlink usr/lib /lib \
	--symlink usr/lib64 /lib64 \
	--symlink usr/sbin /sbin \
	--dir /mnt \
	--dir /sys \
	--dir /tmp \
	--dev-bind /dev /dev \
	--proc /proc \
	--bind "$model/boot" /boot \
	--bind "$model/efi" /efi \
	--bind "$model/etc" /etc \
	--bind "$model/run" /run \
	--bind "$model/var" /var \
	--ro-bind "$fakebin" /mnt \
	--setenv PATH /mnt:/usr/bin:/usr/sbin \
	--setenv SP11_LIVE_OFFLINE_ROLLBACK sp11-beta-review20 \
	/mnt/rollback.sh \
		--state /var/lib/sp11-beta/latest \
		--offline-target \
		--apply

[[ ! -e "$model/etc/candidate.conf" ]]
[[ ! -e "$model/boot/sp11-beta" ]]
grep -Fxq original "$model/etc/original.conf"
[[ -L "$model/etc/original-link" &&
	"$(readlink "$model/etc/original-link")" == "original.conf" ]]
grep -Fq 'chainloader /EFI/Microsoft/Boot/bootmgfw.efi' \
	"$model/boot/grub/grub.cfg"
[[ "$(sha256sum "$model/efi/EFI/Microsoft/Boot/bootmgfw.efi" |
	awk '{print $1}')" == "$windows_sha" ]]
grep -Fq 'enable power-profiles-daemon.service' \
	"$model/var/test-systemctl.log"
grep -Fq 'enable sp11-charge-limit.service' \
	"$model/var/test-systemctl.log"
grep -Fq 'disable sp11-bluetooth-address.service' \
	"$model/var/test-systemctl.log"
(
	cd -- "$state"
	sha256sum -c STATE-SHA256SUMS >/dev/null
)

printf 'PASS disposable offline rollback model\n'
