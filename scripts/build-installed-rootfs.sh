#!/bin/bash

# Build a dedicated installed-system root artifact directly from frozen signed
# packages and exact SP11 inputs. The live root is never used as a source.

set -euo pipefail

release="7.2.0-sp11-73beta1"
source_date_epoch=1788637836
expected_snapshot_manifest="60a1d33fd546985a9a73ce286fb34b1cbd9fb153436f6639a12fa55901e3cf14"
expected_image="a2118d41b4edb8f6b11c050d9ca2c6208e30da1472f4f198959f0f0b44fb8bde"
expected_dtb="54a14d4f6841740e9a911affc58e2b17f097fb900d38472fd0386be311b6cead"
expected_iptsd="45ce0fcabdda04a9fcf3ce30f7f0c64ba7098fd2351127ef0e54cf0ac0b3f083"
expected_checker="54fcdaef90b0bd4239df670865cf8b258c3ae6e3988e42b0b9a3b58aaa4b08f5"
expected_ppd="9e1d72935f2b916de1c44950e425948e60c7bdf83c69bede2a079e7a79a82252"
expected_topology="89b731f3f98fc2b84699bca39a56e390925a44a26d5aea80382cf617e00c08d8"
expected_wallpaper="1fdc98d786badbf332460460da51496c3674cbead0d501f0e98708c4bb0bb5ac"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
package_snapshot="$repo_root/work/package-snapshot-rnote-20260729"
firmware_cache="$repo_root/work/firmware-package-cache-20260622"
payload="$repo_root/work/payload-port73-20260905"
audio_topology="$repo_root/work/audio-topology-public-test-20260729/X1E80100-Microsoft-Surface-Pro-11-tplg.bin"
wallpaper=""
output_dir="$repo_root/work/installed-rootfs-port73-20260905"
local_staging=0

usage() {
	cat <<EOF
Usage: sudo $0 --local-staging [options]

Options:
  --package-snapshot DIRECTORY
  --firmware-cache DIRECTORY
  --payload DIRECTORY
  --audio-topology FILE
  --wallpaper FILE
  --output DIRECTORY

The output must be a new work/installed-rootfs-* directory. The builder reads
only frozen packages, the public project overlay, and exact SP11 payloads. It
never copies a live root, partitions a disk, writes EFI state, creates a user,
or imports owner-supplied proprietary firmware. The wallpaper is a required,
hash-pinned local artwork input and is not added to the public source tree.
EOF
}

while (($#)); do
	case "$1" in
	--local-staging)
		local_staging=1
		shift
		;;
	--package-snapshot)
		package_snapshot="$2"
		shift 2
		;;
	--firmware-cache)
		firmware_cache="$2"
		shift 2
		;;
	--payload)
		payload="$2"
		shift 2
		;;
	--audio-topology)
		audio_topology="$2"
		shift 2
		;;
	--wallpaper)
		wallpaper="$2"
		shift 2
		;;
	--output)
		output_dir="$2"
		shift 2
		;;
	-h|--help)
		usage
		exit 0
		;;
	*)
		usage >&2
		exit 2
		;;
	esac
done

[[ "$local_staging" -eq 1 ]] || {
	printf 'Installed-root construction requires --local-staging.\n' >&2
	exit 1
}
[[ $EUID -eq 0 ]] || {
	printf 'Run with sudo/root; only a new work/ tree is modified.\n' >&2
	exit 1
}
[[ "$(uname -m)" == "aarch64" ]] || {
	printf 'Native aarch64 is required.\n' >&2
	exit 1
}

package_snapshot="$(realpath -e -- "$package_snapshot")"
firmware_cache="$(realpath -e -- "$firmware_cache")"
payload="$(realpath -e -- "$payload")"
audio_topology="$(realpath -e -- "$audio_topology")"
[[ -n "$wallpaper" ]] || {
	printf 'The exact owner-supplied installed wallpaper is required.\n' >&2
	exit 1
}
wallpaper="$(realpath -e -- "$wallpaper")"
[[ -f "$wallpaper" && ! -L "$wallpaper" &&
	"$(stat -c '%s' "$wallpaper")" == "4789340" &&
	"$(sha256sum "$wallpaper" | awk '{print $1}')" == \
	"$expected_wallpaper" ]] || {
	printf 'Wallpaper identity mismatch: %s\n' "$wallpaper" >&2
	exit 1
}
output_dir="$(realpath -m -- "$output_dir")"
case "$output_dir" in
"$repo_root/work"/installed-rootfs-*) ;;
*)
	printf 'Refusing output outside %s/work/installed-rootfs-*: %s\n' \
		"$repo_root" "$output_dir" >&2
	exit 1
	;;
esac
[[ ! -e "$output_dir" ]] || {
	printf 'Refusing to replace existing output: %s\n' "$output_dir" >&2
	exit 1
}

for required_command in \
	awk bsdtar chroot cmp depmod find install journalctl pacman pacman-key \
	python3 realpath rsync sha256sum stat systemctl systemd-sysusers \
	systemd-tmpfiles tar touch zstd; do
	command -v "$required_command" >/dev/null || {
		printf 'Missing required command: %s\n' "$required_command" >&2
		exit 1
	}
done

"$script_dir/audit-package-lock.sh" \
	--frozen-snapshot "$package_snapshot"
"$script_dir/audit-firmware-manifest.sh"
[[ "$(sha256sum "$package_snapshot/PACKAGE-SNAPSHOT.tsv" |
	awk '{print $1}')" == "$expected_snapshot_manifest" ]] || {
	printf 'Unexpected package snapshot identity.\n' >&2
	exit 1
}
cmp -- "$repo_root/iso/packages.lock.tsv" \
	"$package_snapshot/packages.lock.tsv"
cmp -- "$repo_root/iso/repositories.lock.tsv" \
	"$package_snapshot/repositories.lock.tsv"
[[ -f "$audio_topology" && ! -L "$audio_topology" &&
	"$(stat -c '%s' "$audio_topology")" == "11320" &&
	"$(sha256sum "$audio_topology" | awk '{print $1}')" == \
	"$expected_topology" ]] || {
	printf 'Audio topology identity mismatch.\n' >&2
	exit 1
}

for required_payload in \
	"Image-$release" \
	x1e80100-microsoft-denali-oled.dtb \
	"modules-$release.tar.zst" \
	MODULES.tsv \
	sp11-iptsd \
	sp11-iptsd-check-device \
	power-profiles-daemon-sp11 \
	SHA256SUMS; do
	[[ -f "$payload/$required_payload" && ! -L "$payload/$required_payload" ]] ||
		{
			printf 'Missing or unsafe payload input: %s\n' \
				"$required_payload" >&2
			exit 1
		}
done
(
	cd -- "$payload"
	sha256sum -c SHA256SUMS
)
[[ "$(sha256sum "$payload/Image-$release" | awk '{print $1}')" == \
	"$expected_image" ]]
[[ "$(sha256sum "$payload/x1e80100-microsoft-denali-oled.dtb" |
	awk '{print $1}')" == "$expected_dtb" ]]
[[ "$(sha256sum "$payload/sp11-iptsd" | awk '{print $1}')" == \
	"$expected_iptsd" ]]
[[ "$(sha256sum "$payload/sp11-iptsd-check-device" |
	awk '{print $1}')" == "$expected_checker" ]]
[[ "$(sha256sum "$payload/power-profiles-daemon-sp11" |
	awk '{print $1}')" == "$expected_ppd" ]]

mkdir -m 0755 -- "$output_dir"
printf '%s\n' \
	'BINARY/ISO RELEASE HOLD ACTIVE — LOCAL ENGINEERING ARTIFACT ONLY' \
	>"$output_dir/LOCAL-STAGING-NOT-FOR-RELEASE"
rootfs="$output_dir/rootfs"
firmware_extract="$output_dir/firmware-extract"
pacman_hook_dir="$output_dir/empty-pacman-hooks"
mkdir -p -- \
	"$rootfs/var/lib/pacman" \
	"$rootfs/var/cache/pacman/pkg" \
	"$rootfs/var/log" \
	"$firmware_extract" \
	"$pacman_hook_dir"

printf 'Verifying and installing the frozen 663-package GNOME closure ...\n'
package_files=()
while IFS=$'\t' read -r scope _repository _package _pkgbase _version \
	_architecture filename expected_sha _compressed _installed _urls; do
	[[ "$scope" != "scope" ]] || continue
	[[ "$scope" == "live" || "$scope" == "live+build" ]] || continue
	package_file="$package_snapshot/packages/$filename"
	signature="$package_file.sig"
	[[ -f "$package_file" && -f "$signature" ]] || {
		printf 'Missing package or signature: %s\n' "$filename" >&2
		exit 1
	}
	[[ "$(sha256sum "$package_file" | awk '{print $1}')" == \
		"$expected_sha" ]] || {
		printf 'Package hash mismatch: %s\n' "$filename" >&2
		exit 1
	}
	pacman-key --verify "$signature" "$package_file" >/dev/null 2>&1
	package_files+=("$package_file")
done <"$repo_root/iso/packages.lock.tsv"
[[ "${#package_files[@]}" -eq 663 ]] || {
	printf 'Unexpected installed package count: %s\n' \
		"${#package_files[@]}" >&2
	exit 1
}
pacman \
	--disable-sandbox \
	--root "$rootfs" \
	--dbpath "$rootfs/var/lib/pacman" \
	--cachedir "$package_snapshot/packages" \
	--gpgdir /etc/pacman.d/gnupg \
	--logfile "$rootfs/var/log/pacman.log" \
	--config /etc/pacman.conf \
	--hookdir "$pacman_hook_dir" \
	--noconfirm \
	--noprogressbar \
	-U "${package_files[@]}"
systemd-tmpfiles --root="$rootfs" --create
journalctl --root="$rootfs" --update-catalog

printf 'Applying only the installed-system project overlay ...\n'
rsync -a --chown=0:0 --exclude=/README.md \
	"$repo_root/rootfs/" "$rootfs/"
rsync -a --chown=0:0 \
	"$repo_root/iso/installed-rootfs/" "$rootfs/"
install -D -m0644 "$repo_root/iso/desktop/dconf-profile-user" \
	"$rootfs/etc/dconf/profile/user"
install -D -m0644 "$repo_root/iso/desktop/00-sp11-installed" \
	"$rootfs/etc/dconf/db/local.d/00-sp11-installed"
install -D -m0644 "$wallpaper" \
	"$rootfs/usr/share/backgrounds/sp11/tux-surface.png"
chroot "$rootfs" /usr/bin/dconf update

printf 'Installing exact SP11 userspace and module payloads ...\n'
install -D -m0755 "$payload/sp11-iptsd" \
	"$rootfs/usr/local/libexec/sp11-iptsd"
install -D -m0755 "$payload/sp11-iptsd-check-device" \
	"$rootfs/usr/local/libexec/sp11-iptsd-check-device"
install -D -m0755 "$payload/power-profiles-daemon-sp11" \
	"$rootfs/usr/local/libexec/power-profiles-daemon-sp11"
mkdir -p -- "$rootfs/usr/lib/modules"
tar --zstd -xf "$payload/modules-$release.tar.zst" \
	-C "$rootfs/usr/lib/modules"
depmod -b "$rootfs" "$release"

printf 'Selecting only redistributable firmware from verified inputs ...\n'
while IFS=$'\t' read -r _repository package _pkgbase _version \
	_architecture filename expected_sha _pkgbuild _source _identity; do
	[[ "$package" != "package" ]] || continue
	package_file="$firmware_cache/$filename"
	signature="$package_file.sig"
	[[ -f "$package_file" && -f "$signature" &&
		"$(sha256sum "$package_file" | awk '{print $1}')" == \
		"$expected_sha" ]] || {
		printf 'Firmware package identity mismatch: %s\n' "$filename" >&2
		exit 1
	}
	pacman-key --verify "$signature" "$package_file" >/dev/null 2>&1
	mkdir -p -- "$firmware_extract/$package"
	bsdtar -xf "$package_file" -C "$firmware_extract/$package"
done <"$repo_root/firmware/packages.lock.tsv"

while IFS=$'\t' read -r path source_package _source_version size \
	expected_sha _license _purpose; do
	[[ "$path" != "path" ]] || continue
	source_file="$firmware_extract/$source_package/usr/lib/firmware/$path"
	[[ -f "$source_file" && ! -L "$source_file" &&
		"$(stat -c '%s' "$source_file")" == "$size" &&
		"$(sha256sum "$source_file" | awk '{print $1}')" == \
		"$expected_sha" ]] || {
		printf 'Allowlisted firmware identity mismatch: %s\n' "$path" >&2
		exit 1
	}
	install -D -m0644 "$source_file" "$rootfs/usr/lib/firmware/$path"
done <"$repo_root/firmware/allowlist.tsv"

derived_count=0
while IFS=$'\t' read -r path source_path record_name size expected_sha \
	_license _purpose; do
	[[ "$path" != "path" ]] || continue
	source_file="$rootfs/usr/lib/firmware/$source_path"
	derived_file="$firmware_extract/derived/$path"
	python3 "$repo_root/scripts/extract-ath12k-board.py" \
		"$source_file" "$record_name" "$derived_file" \
		--expected-bytes "$size" \
		--expected-sha256 "$expected_sha"
	install -D -m0644 "$derived_file" "$rootfs/usr/lib/firmware/$path"
	((derived_count += 1))
done <"$repo_root/firmware/derived.tsv"
[[ "$derived_count" -eq 1 ]]

license_root="$rootfs/usr/share/licenses/sp11-firmware"
mkdir -p -- "$license_root"
for license_dir in \
	"$firmware_extract/linux-firmware-atheros/usr/share/licenses/linux-firmware-atheros" \
	"$firmware_extract/linux-firmware-qcom/usr/share/licenses/linux-firmware-qcom" \
	"$firmware_extract/linux-firmware-whence/usr/share/licenses/linux-firmware-whence" \
	"$firmware_extract/wireless-regdb/usr/share/licenses/wireless-regdb"; do
	[[ -d "$license_dir" ]] || {
		printf 'Missing firmware license directory: %s\n' "$license_dir" >&2
		exit 1
	}
	cp -a -- "$license_dir" "$license_root/"
done
install -m0644 \
	"$firmware_extract/linux-firmware-atheros/usr/lib/firmware/ath12k/WCN7850/hw2.0/Notice.txt" \
	"$license_root/WCN7850-Notice.txt"
install -D -m0644 "$audio_topology" \
	"$rootfs/usr/lib/firmware/qcom/x1e80100/X1E80100-Microsoft-Surface-Pro-11-tplg.bin"

printf 'Configuring installed-system services without creating a user ...\n'
systemd-sysusers --root="$rootfs"
chroot "$rootfs" /usr/bin/passwd --lock root
ln -sfn /run/systemd/resolve/stub-resolv.conf "$rootfs/etc/resolv.conf"
systemctl --root="$rootfs" set-default graphical.target
for unit in \
	gdm.service \
	NetworkManager.service \
	bluetooth.service \
	systemd-resolved.service \
	power-profiles-daemon.service \
	sp11-bluetooth-address.service \
	sp11-cpufreq-boost.service \
	sp11-power-profile-cpufreq.service \
	sp11-charge-limit.service; do
	systemctl --root="$rootfs" enable "$unit"
done
systemctl --root="$rootfs" mask iio-sensor-proxy.service
systemctl --root="$rootfs" disable sp11-sensors.service

rm -f -- "$rootfs/etc/machine-id" "$rootfs/etc/fstab"
: >"$rootfs/etc/machine-id"
if [[ -e "$rootfs/etc/brlapi.key" ]]; then
	rm -f -- "$rootfs/etc/brlapi.key"
fi
install -d -m0755 "$rootfs/usr/share/doc/sp11-beta"
for document in \
	README.md \
	RELEASE-NOTES.md \
	KNOWN-ISSUES.md \
	RELEASE-STATUS.md \
	docs/GETTING-STARTED.md \
	docs/FIRMWARE.md \
	docs/UNINSTALL.md \
	firmware/README.md; do
	install -m0644 "$repo_root/$document" \
		"$rootfs/usr/share/doc/sp11-beta/${document//\//-}"
done
install -D -m0644 "$repo_root/firmware/external-required.tsv" \
	"$rootfs/usr/share/sp11/external-required.tsv"
install -D -m0644 "$repo_root/firmware/derived.tsv" \
	"$rootfs/usr/share/sp11/derived-firmware.tsv"
{
	printf 'SP11_FRESH_ROOTFS=1\n'
	printf 'SP11_KERNEL_RELEASE=%s\n' "$release"
	printf 'SP11_PACKAGE_LOCK_SHA256=%s\n' \
		"$(sha256sum "$repo_root/iso/packages.lock.tsv" | awk '{print $1}')"
	printf 'SP11_INSTALLED_ROOTFS_LOCK_SHA256=%s\n' \
		"$(sha256sum "$repo_root/iso/installed-rootfs.lock.tsv" |
			awk '{print $1}')"
	printf 'SP11_FIRMWARE_ALLOWLIST_SHA256=%s\n' \
		"$(sha256sum "$repo_root/firmware/allowlist.tsv" | awk '{print $1}')"
	printf 'SP11_FIRMWARE_DERIVED_SHA256=%s\n' \
		"$(sha256sum "$repo_root/firmware/derived.tsv" | awk '{print $1}')"
	printf 'SP11_AUDIO_TOPOLOGY_SHA256=%s\n' "$expected_topology"
	printf 'SP11_AUDIO_UCM_MANIFEST_SHA256=%s\n' \
		"$(sha256sum "$repo_root/iso/audio-ucm.tsv" | awk '{print $1}')"
	printf 'SP11_EXTERNAL_FIRMWARE_REQUIRED=1\n'
	printf 'SP11_ACCOUNT_PROVISIONING_REQUIRED=1\n'
	printf 'SP11_BOOT_PROVISIONING_REQUIRED=1\n'
	printf 'SP11_HOST_ID_PROVISIONING_REQUIRED=1\n'
	printf 'SP11_SECURE_BOOT=disabled\n'
} >"$rootfs/etc/sp11-installed-root-release"

printf 'Removing target-generated identity and cache state ...\n'
rm -f -- \
	"$rootfs/etc/nvme/hostid" \
	"$rootfs/etc/nvme/hostnqn" \
	"$rootfs/etc/ca-certificates/extracted/java-cacerts.jks" \
	"$rootfs/var/cache/ldconfig/aux-cache"
if [[ -d "$rootfs/var/cache/fontconfig" ]]; then
	find "$rootfs/var/cache/fontconfig" \
		-mindepth 1 -maxdepth 1 -type f \
		! -name CACHEDIR.TAG -delete
fi
"$script_dir/normalize-installed-rootfs.py" \
	"$rootfs" \
	--source-date-epoch "$source_date_epoch" \
	--expected-packages 663
find "$rootfs/var/cache/pacman/pkg" -mindepth 1 -delete
find "$rootfs/tmp" "$rootfs/var/tmp" -mindepth 1 -delete
: >"$rootfs/var/log/pacman.log"
find "$rootfs" -xdev -exec touch -h -d "@$source_date_epoch" {} +

printf 'Generating the installed-root file and boot manifests ...\n'
rootfs_manifest="$output_dir/ROOTFS-FILES.tsv"
"$script_dir/manifest-installed-rootfs.py" \
	"$rootfs" "$rootfs_manifest"

install -D -m0644 "$payload/Image-$release" \
	"$output_dir/boot/Image-$release"
install -D -m0644 "$payload/x1e80100-microsoft-denali-oled.dtb" \
	"$output_dir/boot/x1e80100-microsoft-denali-oled.dtb"
{
	printf 'path\tbytes\tsha256\n'
	for boot_file in "$output_dir"/boot/*; do
		printf '%s\t%s\t%s\n' \
			"${boot_file#"$output_dir/"}" \
			"$(stat -c '%s' "$boot_file")" \
			"$(sha256sum "$boot_file" | awk '{print $1}')"
	done
} >"$output_dir/BOOT-PAYLOAD.tsv"

"$script_dir/finalize-installed-rootfs.sh" "$output_dir"
