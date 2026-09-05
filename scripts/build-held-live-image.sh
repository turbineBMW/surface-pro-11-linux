#!/bin/bash

# Build the held ARM64 UEFI GNOME live, installation-preflight, and offline
# rollback image from frozen, signed inputs. The output is always local
# engineering material while BINARY-RELEASE-HOLD.md exists.

set -euo pipefail

release="7.2.0-sp11-73beta1"
volume_id="SP11BETA"
source_date_epoch=1788637836
expected_snapshot_manifest="60a1d33fd546985a9a73ce286fb34b1cbd9fb153436f6639a12fa55901e3cf14"
expected_image="a2118d41b4edb8f6b11c050d9ca2c6208e30da1472f4f198959f0f0b44fb8bde"
expected_dtb="54a14d4f6841740e9a911affc58e2b17f097fb900d38472fd0386be311b6cead"
expected_iptsd="45ce0fcabdda04a9fcf3ce30f7f0c64ba7098fd2351127ef0e54cf0ac0b3f083"
expected_checker="54fcdaef90b0bd4239df670865cf8b258c3ae6e3988e42b0b9a3b58aaa4b08f5"
expected_ppd="9e1d72935f2b916de1c44950e425948e60c7bdf83c69bede2a079e7a79a82252"
expected_wallpaper="1fdc98d786badbf332460460da51496c3674cbead0d501f0e98708c4bb0bb5ac"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
package_snapshot="$repo_root/work/package-snapshot-rnote-20260729"
firmware_cache="$repo_root/work/firmware-package-cache-20260622"
payload="$repo_root/work/payload-port73-20260905"
output_dir="$repo_root/work/live-image-port73-20260905"
local_staging=0
local_proprietary_firmware_root=""
audio_topology=""
wallpaper=""
installed_rootfs_artifact=""

usage() {
	cat <<EOF
Usage: sudo $0 --local-staging [options]

Options:
  --package-snapshot DIRECTORY
  --firmware-cache DIRECTORY
  --payload DIRECTORY
  --output DIRECTORY
  --local-proprietary-firmware-root DIRECTORY
  --audio-topology FILE
  --wallpaper FILE
  --installed-rootfs-artifact DIRECTORY

The output must be a new directory below work/. The script never installs to
the host, writes firmware variables, or partitions disks. It embeds a held
installer kit, a live install wrapper restricted to read-only target preflight,
and a separately confirmed offline rollback wrapper.
The local proprietary firmware option imports only the five exact
owner-supplied files from firmware/external-required.tsv and permanently
marks the result non-redistributable. Build the redistributable audio topology
with scripts/build-audio-topology.sh and pass its exact output with
--audio-topology. The wallpaper is owner-supplied local engineering artwork;
its exact expected SHA-256 is enforced, but the image is not added to the
public source tree.
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
	--output)
		output_dir="$2"
		shift 2
		;;
	--local-proprietary-firmware-root)
		local_proprietary_firmware_root="$2"
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
	--installed-rootfs-artifact)
		installed_rootfs_artifact="$2"
		shift 2
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

[[ "$local_staging" -eq 1 ]] || {
	printf 'Live-image construction requires explicit --local-staging.\n' >&2
	exit 1
}
[[ "$EUID" -eq 0 ]] || {
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
output_dir="$(realpath -m -- "$output_dir")"
if [[ -n "$local_proprietary_firmware_root" ]]; then
	local_proprietary_firmware_root="$(
		realpath -e -- "$local_proprietary_firmware_root"
	)"
	[[ -d "$local_proprietary_firmware_root/usr/lib/firmware" ]] || {
		printf 'Local firmware root lacks usr/lib/firmware: %s\n' \
			"$local_proprietary_firmware_root" >&2
		exit 1
	}
fi
[[ -n "$audio_topology" ]] || {
	printf 'The exact redistributable audio topology is required.\n' >&2
	exit 1
}
audio_topology="$(realpath -e -- "$audio_topology")"
[[ -f "$audio_topology" && ! -L "$audio_topology" &&
	"$(stat -c '%s' "$audio_topology")" == "11320" &&
	"$(sha256sum "$audio_topology" | awk '{print $1}')" == \
	"89b731f3f98fc2b84699bca39a56e390925a44a26d5aea80382cf617e00c08d8" ]] || {
	printf 'Audio topology identity mismatch: %s\n' "$audio_topology" >&2
	exit 1
}
[[ -n "$wallpaper" ]] || {
	printf 'The exact owner-supplied live wallpaper is required.\n' >&2
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
[[ -n "$installed_rootfs_artifact" ]] || {
	printf 'The exact held installed-system root artifact is required.\n' >&2
	exit 1
}
installed_rootfs_artifact="$(realpath -e -- "$installed_rootfs_artifact")"
[[ -d "$installed_rootfs_artifact" && ! -L "$installed_rootfs_artifact" ]] || {
	printf 'Installed-rootfs artifact is missing or unsafe: %s\n' \
		"$installed_rootfs_artifact" >&2
	exit 1
}
"$script_dir/audit-installed-rootfs.sh" "$installed_rootfs_artifact"
case "$output_dir" in
"$repo_root/work"/*) ;;
*)
	printf 'Refusing output outside %s/work: %s\n' \
		"$repo_root" "$output_dir" >&2
	exit 1
	;;
esac
[[ ! -e "$output_dir" ]] || {
	printf 'Refusing to replace existing output: %s\n' "$output_dir" >&2
	exit 1
}

for command_name in \
	awk bsdtar chroot cmp depmod find getent grub-mkstandalone \
	file install journalctl mkfs.fat mkinitcpio pacman pacman-key realpath rsync \
	readlink sha256sum stat systemctl tar touch truncate python3; do
	command -v "$command_name" >/dev/null || {
		printf 'Missing required command: %s\n' "$command_name" >&2
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

for required_payload in \
	"Image-$release" \
	x1e80100-microsoft-denali-oled.dtb \
	"modules-$release.tar.zst" \
	MODULES.tsv \
	sp11-iptsd \
	sp11-iptsd-check-device \
	power-profiles-daemon-sp11 \
	SHA256SUMS; do
	[[ -f "$payload/$required_payload" && ! -L "$payload/$required_payload" ]] || {
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

mkdir -p -- "$output_dir"
printf '%s\n' \
	'BINARY/ISO RELEASE HOLD ACTIVE — LOCAL ENGINEERING IMAGE ONLY' \
	>"$output_dir/LOCAL-STAGING-NOT-FOR-RELEASE"

rootfs="$output_dir/rootfs"
iso_tree="$output_dir/iso-tree"
tool_root="$output_dir/tool-root"
firmware_extract="$output_dir/firmware-extract"
hook_root="$output_dir/initcpio-hooks"
pacman_hook_dir="$output_dir/empty-pacman-hooks"
mkdir -p -- \
	"$rootfs/var/lib/pacman" \
	"$rootfs/var/cache/pacman/pkg" \
	"$rootfs/var/log" \
	"$iso_tree/boot/grub" \
	"$iso_tree/sp11" \
	"$tool_root" \
	"$firmware_extract" \
	"$hook_root/install" \
	"$hook_root/hooks" \
	"$pacman_hook_dir"

printf 'Verifying and installing the frozen live package closure ...\n'
package_files=()
while IFS=$'\t' read -r scope _repository package _pkgbase _version \
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
	printf 'Unexpected live package count: %s\n' "${#package_files[@]}" >&2
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

printf 'Applying the explicit live-only SP11 overlay ...\n'
while IFS=$'\t' read -r source_relative destination; do
	[[ "$source_relative" != "source" ]] || continue
	source_file="$repo_root/$source_relative"
	[[ -f "$source_file" && ! -L "$source_file" ]] || {
		printf 'Missing live overlay source: %s\n' "$source_relative" >&2
		exit 1
	}
	source_mode="$(stat -c '%a' "$source_file")"
	install -D -m "$source_mode" "$source_file" \
		"$rootfs$destination"
done <"$repo_root/iso/live-rootfs-files.tsv"
rsync -a --chown=0:0 "$repo_root/iso/rootfs/" "$rootfs/"
chmod 0440 "$rootfs/etc/sudoers.d/10-sp11-live"

printf 'Installing deterministic GNOME live-session defaults ...\n'
install -D -m0644 "$wallpaper" \
	"$rootfs/usr/share/backgrounds/sp11/tux-surface.png"
install -D -m0644 "$repo_root/iso/desktop/dconf-profile-user" \
	"$rootfs/etc/dconf/profile/user"
install -D -m0644 "$repo_root/iso/desktop/00-sp11-live" \
	"$rootfs/etc/dconf/db/local.d/00-sp11-live"
chroot "$rootfs" /usr/bin/dconf update
file "$rootfs/usr/share/backgrounds/sp11/tux-surface.png" |
	grep -Fq 'PNG image data, 2880 x 1920, 8-bit/color RGB'
printf '%s  %s\n' "$expected_wallpaper" \
	'usr/share/backgrounds/sp11/tux-surface.png' \
	>"$output_dir/LOCAL-WALLPAPER-IMPORT"

printf 'Installing the exact project SP11 ALSA UCM routing ...\n'
audio_ucm_count=0
while IFS=$'\t' read -r path entry_type identity; do
	[[ "$path" != "path" ]] || continue
	source_file="$repo_root/rootfs/usr/share/alsa/ucm2/$path"
	destination="$rootfs/usr/share/alsa/ucm2/$path"
	case "$entry_type" in
	file)
		[[ "$identity" =~ ^[0-9a-f]{64}$ &&
			-f "$source_file" && ! -L "$source_file" &&
			"$(sha256sum "$source_file" | awk '{print $1}')" == \
			"$identity" ]] || {
			printf 'Project UCM file identity mismatch: %s\n' "$path" >&2
			exit 1
		}
		install -D -m0644 "$source_file" "$destination"
		;;
	symlink)
		[[ -L "$source_file" &&
			"$(readlink "$source_file")" == "$identity" ]] || {
			printf 'Project UCM symlink identity mismatch: %s\n' \
				"$path" >&2
			exit 1
		}
		install -d -m0755 "$(dirname -- "$destination")"
		rm -f -- "$destination"
		ln -s -- "$identity" "$destination"
		;;
	*)
		printf 'Unknown project UCM manifest type for %s: %s\n' \
			"$path" "$entry_type" >&2
		exit 1
		;;
	esac
	((audio_ucm_count += 1))
done <"$repo_root/iso/audio-ucm.tsv"
[[ "$audio_ucm_count" -eq 4 ]] || {
	printf 'Unexpected project UCM entry count: %s\n' \
		"$audio_ucm_count" >&2
	exit 1
}

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

printf 'Selecting only allowlisted firmware from verified packages ...\n'
while IFS=$'\t' read -r repository package _pkgbase _version \
	_architecture filename expected_sha _pkgbuild _source _identity; do
	[[ "$repository" != "repository" ]] || continue
	package_file="$firmware_cache/$filename"
	signature="$package_file.sig"
	[[ -f "$package_file" && -f "$signature" ]] || {
		printf 'Missing firmware package or signature: %s\n' "$filename" >&2
		exit 1
	}
	[[ "$(sha256sum "$package_file" | awk '{print $1}')" == \
		"$expected_sha" ]] || {
		printf 'Firmware package hash mismatch: %s\n' "$filename" >&2
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
	[[ -f "$source_file" && ! -L "$source_file" ]] || {
		printf 'Allowlisted firmware missing from package: %s\n' "$path" >&2
		exit 1
	}
	[[ "$(stat -c '%s' "$source_file")" == "$size" &&
		"$(sha256sum "$source_file" | awk '{print $1}')" == \
		"$expected_sha" ]] || {
		printf 'Allowlisted firmware identity mismatch: %s\n' "$path" >&2
		exit 1
	}
	install -D -m0644 "$source_file" "$rootfs/usr/lib/firmware/$path"
done <"$repo_root/firmware/allowlist.tsv"

printf 'Extracting exact derived firmware records ...\n'
derived_firmware_count=0
while IFS=$'\t' read -r path source_path record_name size expected_sha \
	_license _purpose; do
	[[ "$path" != "path" ]] || continue
	source_file="$rootfs/usr/lib/firmware/$source_path"
	derived_file="$firmware_extract/derived/$path"
	[[ -f "$source_file" && ! -L "$source_file" ]] || {
		printf 'Derived firmware source is missing or unsafe: %s\n' \
			"$source_path" >&2
		exit 1
	}
	python3 "$repo_root/scripts/extract-ath12k-board.py" \
		"$source_file" \
		"$record_name" \
		"$derived_file" \
		--expected-bytes "$size" \
		--expected-sha256 "$expected_sha"
	install -D -m0644 "$derived_file" "$rootfs/usr/lib/firmware/$path"
	((derived_firmware_count += 1))
done <"$repo_root/firmware/derived.tsv"
[[ "$derived_firmware_count" -eq 1 ]] || {
	printf 'Unexpected derived firmware count: %s\n' \
		"$derived_firmware_count" >&2
	exit 1
}

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

if [[ -n "$local_proprietary_firmware_root" ]]; then
	printf 'Importing exact local-only SP11 firmware hashes ...\n'
	local_firmware_count=0
	while IFS=$'\t' read -r path expected_size expected_sha \
		_candidate_names _purpose; do
		[[ "$path" != "path" ]] || continue
		source_file="$local_proprietary_firmware_root/usr/lib/firmware/$path"
		[[ -f "$source_file" && ! -L "$source_file" ]] || {
			printf 'Local firmware input is missing or unsafe: %s\n' \
				"$path" >&2
			exit 1
		}
		[[ "$(stat -c '%s' "$source_file")" == "$expected_size" &&
			"$(sha256sum "$source_file" | awk '{print $1}')" == \
			"$expected_sha" ]] || {
			printf 'Local firmware identity mismatch: %s\n' "$path" >&2
			exit 1
		}
		install -D -m0644 "$source_file" \
			"$rootfs/usr/lib/firmware/$path"
		((local_firmware_count += 1))
	done <"$repo_root/firmware/external-required.tsv"
	[[ "$local_firmware_count" -eq 5 ]] || {
		printf 'Unexpected local firmware count: %s\n' \
			"$local_firmware_count" >&2
		exit 1
	}
	{
		printf '%s\n' \
			'LOCAL PROPRIETARY FIRMWARE IMPORT — NEVER REDISTRIBUTE'
		awk -F '\t' \
			'NR > 1 { print $1 "\t" $3 }' \
			"$repo_root/firmware/external-required.tsv"
	} >"$output_dir/LOCAL-PROPRIETARY-FIRMWARE-IMPORT"
	install -D -m0644 \
		"$output_dir/LOCAL-PROPRIETARY-FIRMWARE-IMPORT" \
		"$rootfs/etc/sp11-local-proprietary-firmware"
fi

actual_firmware="$output_dir/actual-firmware-paths.txt"
expected_firmware="$output_dir/expected-firmware-paths.txt"
find "$rootfs/usr/lib/firmware" -type f \
	-printf '%P\n' | LC_ALL=C sort >"$actual_firmware"
{
	awk -F '\t' 'NR > 1 { print $1 }' \
		"$repo_root/firmware/allowlist.tsv"
	awk -F '\t' 'NR > 1 { print $1 }' \
		"$repo_root/firmware/derived.tsv"
	printf '%s\n' \
		qcom/x1e80100/X1E80100-Microsoft-Surface-Pro-11-tplg.bin
	if [[ -n "$local_proprietary_firmware_root" ]]; then
		awk -F '\t' 'NR > 1 { print $1 }' \
			"$repo_root/firmware/external-required.tsv"
	fi
} | LC_ALL=C sort >"$expected_firmware"
cmp -- "$expected_firmware" "$actual_firmware" || {
	printf 'Live root firmware does not match the selected manifests.\n' >&2
	exit 1
}

printf 'Creating the non-persistent live user and service policy ...\n'
systemd-sysusers --root="$rootfs"
chroot "$rootfs" /usr/bin/useradd \
	--create-home \
	--uid 1000 \
	--groups wheel,audio,video,render,input,storage \
	--shell /bin/bash \
	live
chroot "$rootfs" /usr/bin/passwd --delete live
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
	sp11-boot-trace.service \
	sp11-firmware-import.service \
	sp11-live-session.service \
	sp11-cpufreq-boost.service \
	sp11-power-profile-cpufreq.service; do
	systemctl --root="$rootfs" enable "$unit"
done
for unit in \
	iio-sensor-proxy.service \
	sp11-sensors.service \
	sp11-ir-bridge.service; do
	systemctl --root="$rootfs" mask "$unit"
done

rm -f -- "$rootfs/etc/machine-id"
touch -d "@$source_date_epoch" "$rootfs/etc/machine-id"
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
	docs/BETA-ISO-ROADMAP.md \
	firmware/README.md; do
	install -m0644 "$repo_root/$document" \
		"$rootfs/usr/share/doc/sp11-beta/${document//\//-}"
done
install -D -m0755 "$repo_root/scripts/sp11-firmware.py" \
	"$rootfs/usr/local/bin/sp11-firmware"
install -D -m0755 "$repo_root/scripts/validate-external-firmware.py" \
	"$rootfs/usr/local/libexec/sp11-validate-external-firmware"
install -D -m0644 "$repo_root/firmware/external-required.tsv" \
	"$rootfs/usr/share/sp11/external-required.tsv"
install -D -m0644 "$repo_root/firmware/derived.tsv" \
	"$rootfs/usr/share/sp11/derived-firmware.tsv"
install -D -m0644 "$repo_root/scripts/sp11-collect-firmware.ps1" \
	"$iso_tree/sp11-tools/sp11-collect-firmware.ps1"
install -D -m0644 "$repo_root/scripts/RUN-IN-WINDOWS.cmd" \
	"$iso_tree/sp11-tools/RUN-IN-WINDOWS.cmd"
install -D -m0644 "$repo_root/scripts/sp11-firmware.py" \
	"$iso_tree/sp11-tools/sp11-firmware.py"

printf 'Embedding the held installation-preflight kit ...\n'
installer_root="$rootfs/opt/sp11-beta-installer"
install -d -m0755 \
	"$installer_root/scripts" \
	"$installer_root/docs" \
	"$installer_root/iso" \
	"$installer_root/payload" \
	"$installer_root/rootfs"
for installer_script in \
	install.sh \
	rollback.sh \
	verify.sh \
	verify-install.sh \
	capture-install-baseline.sh; do
	install -m0755 "$repo_root/scripts/$installer_script" \
		"$installer_root/scripts/$installer_script"
done
rsync -a "$repo_root/rootfs/" "$installer_root/rootfs/"
install -m0644 "$repo_root/iso/audio-ucm.tsv" \
	"$installer_root/iso/audio-ucm.tsv"
install -m0644 "$repo_root/RELEASE-STATUS.md" \
	"$installer_root/RELEASE-STATUS.md"
install -m0644 "$repo_root/docs/INSTALL.md" \
	"$installer_root/docs/INSTALL.md"
install -m0644 "$repo_root/docs/ROLLBACK.md" \
	"$installer_root/docs/ROLLBACK.md"
for payload_file in \
	BUILDINFO \
	"Image-$release" \
	LOCAL-STAGING-NOT-FOR-RELEASE \
	MODULES.tsv \
	"modules-$release.tar.zst" \
	power-profiles-daemon-sp11 \
	SHA256SUMS \
	sp11-iptsd \
	sp11-iptsd-check-device \
	x1e80100-microsoft-denali-oled.dtb; do
	install -m0644 "$payload/$payload_file" \
		"$installer_root/payload/$payload_file"
done
chmod 0755 \
	"$installer_root/payload/power-profiles-daemon-sp11" \
	"$installer_root/payload/sp11-iptsd" \
	"$installer_root/payload/sp11-iptsd-check-device"
install -D -m0755 "$repo_root/scripts/sp11-install-live-preflight.sh" \
	"$rootfs/usr/local/bin/sp11-install-preflight"
install -D -m0755 "$repo_root/scripts/sp11-rollback-live.sh" \
	"$rootfs/usr/local/bin/sp11-rollback-live"
install -D -m0755 "$repo_root/scripts/capture-install-baseline.sh" \
	"$rootfs/usr/local/bin/sp11-capture-install-baseline"

printf 'Embedding the identity-bound fresh-machine installer ...\n'
fresh_root="$rootfs/usr/local/libexec/sp11-fresh-installer"
install -d -m0755 "$fresh_root/scripts" \
	"$fresh_root/firmware" \
	"$rootfs/opt/sp11-fresh-installer/artifact"
for fresh_script in \
	sp11-install-plan.py \
	sp11-install-executor.py \
	manifest-installed-rootfs.py; do
	install -m0755 "$repo_root/scripts/$fresh_script" \
		"$fresh_root/scripts/$fresh_script"
done
install -m0644 "$repo_root/firmware/external-required.tsv" \
	"$fresh_root/firmware/external-required.tsv"
for artifact_file in \
	ARTIFACTS.tsv \
	BOOT-PAYLOAD.tsv \
	ROOTFS-FILES.tsv \
	sp11-installed-rootfs.tar.zst; do
	install -m0644 "$installed_rootfs_artifact/$artifact_file" \
		"$rootfs/opt/sp11-fresh-installer/artifact/$artifact_file"
done
install -d -m0755 "$rootfs/opt/sp11-fresh-installer/artifact/boot"
install -m0644 "$installed_rootfs_artifact/boot/Image-$release" \
	"$rootfs/opt/sp11-fresh-installer/artifact/boot/Image-$release"
install -m0644 \
	"$installed_rootfs_artifact/boot/x1e80100-microsoft-denali-oled.dtb" \
	"$rootfs/opt/sp11-fresh-installer/artifact/boot/x1e80100-microsoft-denali-oled.dtb"
install -D -m0755 "$repo_root/scripts/sp11-installer-ui.py" \
	"$rootfs/usr/local/bin/sp11-installer-ui"
install -D -m0644 \
	"$repo_root/iso/installer-ui-staging/usr/share/applications/sp11-installer-preview.desktop" \
	"$rootfs/usr/share/applications/sp11-installer.desktop"
installer_manifest="$output_dir/INSTALLER-FILES.tsv"
{
	printf 'path\tbytes\tsha256\n'
	while IFS= read -r -d '' installer_file; do
		printf '%s\t%s\t%s\n' \
			"${installer_file#"$installer_root/"}" \
			"$(stat -c '%s' "$installer_file")" \
			"$(sha256sum "$installer_file" | awk '{print $1}')"
	done < <(
		find "$installer_root" -type f -print0 |
			LC_ALL=C sort -z
	)
} >"$installer_manifest"
install -m0644 "$installer_manifest" \
	"$installer_root/INSTALLER-FILES.tsv"
{
	printf 'SP11_HELD_LIVE=1\n'
	printf 'SP11_KERNEL_RELEASE=%s\n' "$release"
	printf 'SP11_PACKAGE_LOCK_SHA256=%s\n' \
		"$(sha256sum "$repo_root/iso/packages.lock.tsv" | awk '{print $1}')"
	printf 'SP11_FIRMWARE_ALLOWLIST_SHA256=%s\n' \
		"$(sha256sum "$repo_root/firmware/allowlist.tsv" | awk '{print $1}')"
	printf 'SP11_FIRMWARE_DERIVED_SHA256=%s\n' \
		"$(sha256sum "$repo_root/firmware/derived.tsv" | awk '{print $1}')"
	printf 'SP11_AUDIO_TOPOLOGY_SHA256=%s\n' \
		"$(sha256sum "$audio_topology" | awk '{print $1}')"
	printf 'SP11_AUDIO_UCM_MANIFEST_SHA256=%s\n' \
		"$(sha256sum "$repo_root/iso/audio-ucm.tsv" | awk '{print $1}')"
	printf 'SP11_WALLPAPER_SHA256=%s\n' "$expected_wallpaper"
	printf 'SP11_GNOME_ACCENT=orange\n'
	printf 'SP11_RNOTE_VERSION=0.14.2-2\n'
	printf 'SP11_INSTALL_PREFLIGHT=1\n'
	printf 'SP11_OFFLINE_ROLLBACK=1\n'
	printf 'SP11_FRESH_INSTALLER=1\n'
	printf 'SP11_FIRMWARE_GRUB_NEWC=1\n'
	printf 'SP11_INSTALLED_ROOTFS_SHA256=%s\n' \
		"$(awk -F '\t' '$1 == "sp11-installed-rootfs.tar.zst" { print $2 }' \
			"$installed_rootfs_artifact/ARTIFACTS.tsv")"
	printf 'SP11_INSTALLER_MANIFEST_SHA256=%s\n' \
		"$(sha256sum "$installer_manifest" |
			awk '{print $1}')"
	if [[ -n "$local_proprietary_firmware_root" ]]; then
		printf 'SP11_LOCAL_PROPRIETARY_FIRMWARE=1\n'
		printf 'SP11_FIRMWARE_DENYLIST_SHA256=%s\n' \
			"$(sha256sum "$repo_root/firmware/denylist.tsv" |
				awk '{print $1}')"
		printf 'SP11_EXTERNAL_FIRMWARE_MANIFEST_SHA256=%s\n' \
			"$(sha256sum "$repo_root/firmware/external-required.tsv" |
				awk '{print $1}')"
	fi
} >"$rootfs/etc/sp11-live-release"

find "$rootfs/var/cache/pacman/pkg" -mindepth 1 -delete
find "$rootfs/tmp" "$rootfs/var/tmp" -mindepth 1 -delete
: >"$rootfs/var/log/pacman.log"
find "$rootfs" -xdev -exec touch -h -d "@$source_date_epoch" {} +

printf 'Building the dedicated live initramfs ...\n'
for install_hook in /usr/lib/initcpio/install/*; do
	ln -s "$install_hook" "$hook_root/install/$(basename "$install_hook")"
done
for runtime_hook in /usr/lib/initcpio/hooks/*; do
	ln -s "$runtime_hook" "$hook_root/hooks/$(basename "$runtime_hook")"
done
install -m0755 "$repo_root/iso/mkinitcpio/install/sp11live" \
	"$hook_root/install/sp11live"
install -m0755 "$repo_root/iso/mkinitcpio/hooks/sp11live" \
	"$hook_root/hooks/sp11live"
SP11_INITRAMFS_STAGED_ROOT="$rootfs" mkinitcpio \
	-r "$rootfs" \
	-D "$hook_root" \
	-c "$repo_root/iso/mkinitcpio.conf" \
	-k "$release" \
	-g "$iso_tree/sp11/initramfs-$release-live.img"
chmod 0644 "$iso_tree/sp11/initramfs-$release-live.img"

install -m0644 "$payload/Image-$release" \
	"$iso_tree/sp11/Image-$release"
install -m0644 "$payload/x1e80100-microsoft-denali-oled.dtb" \
	"$iso_tree/sp11/x1e80100-microsoft-denali-oled.dtb"
install -m0644 "$repo_root/iso/grub.cfg" \
	"$iso_tree/boot/grub/grub.cfg"

printf 'Extracting the frozen image-construction tools ...\n'
for tool_package in squashfs-tools libburn libisofs libisoburn mtools; do
	tool_filename="$(
		awk -F '\t' -v package="$tool_package" \
			'NR > 1 && $3 == package { print $7; exit }' \
			"$repo_root/iso/packages.lock.tsv"
	)"
	[[ -n "$tool_filename" ]] || {
		printf 'Build tool is not locked: %s\n' "$tool_package" >&2
		exit 1
	}
	bsdtar -xf "$package_snapshot/packages/$tool_filename" -C "$tool_root"
done
mksquashfs="$tool_root/usr/bin/mksquashfs"
xorriso="$tool_root/usr/bin/xorriso"
mcopy="$tool_root/usr/bin/mcopy"
mmd="$tool_root/usr/bin/mmd"
for tool_binary in "$mksquashfs" "$xorriso" "$mcopy" "$mmd"; do
	[[ -x "$tool_binary" ]] || {
		printf 'Missing extracted build tool: %s\n' "$tool_binary" >&2
		exit 1
	}
done

printf 'Compressing the live root filesystem ...\n'
"$mksquashfs" "$rootfs" "$iso_tree/sp11/rootfs.sfs" \
	-noappend \
	-comp xz \
	-b 1M \
	-mkfs-time "$source_date_epoch"
(
	cd -- "$iso_tree/sp11"
	sha256sum rootfs.sfs >rootfs.sfs.sha256
)

printf 'Building the removable ARM64 UEFI loader ...\n'
grub_efi="$output_dir/BOOTAA64.EFI"
grub-mkstandalone \
	--format=arm64-efi \
	--output="$grub_efi" \
	--locales="" \
	--fonts="" \
	--modules="part_gpt fat iso9660 normal linux fdt search search_label configfile all_video gfxterm echo test" \
	"boot/grub/grub.cfg=$repo_root/iso/grub-embedded.cfg"
install -D -m0644 "$grub_efi" \
	"$iso_tree/EFI/BOOT/BOOTAA64.EFI"

efi_image="$output_dir/sp11-efiboot.img"
truncate -s 64M "$efi_image"
mkfs.fat -F32 -n SP11EFI "$efi_image"
MTOOLS_SKIP_CHECK=1 "$mmd" -i "$efi_image" ::/EFI ::/EFI/BOOT
MTOOLS_SKIP_CHECK=1 "$mcopy" -i "$efi_image" \
	"$grub_efi" ::/EFI/BOOT/BOOTAA64.EFI

firmware_image="$output_dir/sp11-firmware.img"
truncate -s 128M "$firmware_image"
mkfs.fat -F32 -i 53503131 -n SP11FW "$firmware_image"
MTOOLS_SKIP_CHECK=1 "$mcopy" -i "$firmware_image" \
	"$repo_root/iso/START-HERE.txt" \
	"$repo_root/scripts/RUN-IN-WINDOWS.cmd" \
	"$repo_root/scripts/sp11-collect-firmware.ps1" \
	"$repo_root/scripts/sp11-firmware.py" \
	"$repo_root/scripts/sp11-live-firstboot-capture.sh" \
	"$repo_root/docs/GETTING-STARTED.md" \
	"$repo_root/docs/FIRMWARE.md" \
	::/

printf 'Creating the held hybrid ISO ...\n'
iso_output="$output_dir/sp11-beta-port73-aarch64-HELD-local.iso"
LD_LIBRARY_PATH="$tool_root/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
	"$xorriso" -as mkisofs \
	-iso-level 3 \
	-full-iso9660-filenames \
	-rational-rock \
	-volid "$volume_id" \
	-appid "SP11 beta held engineering image" \
	-partition_offset 16 \
	-append_partition 2 0xef "$efi_image" \
	-append_partition 3 0x0c "$firmware_image" \
	-appended_part_as_gpt \
	-e --interval:appended_partition_2:all:: \
	-no-emul-boot \
	-output "$iso_output" \
	"$iso_tree"

{
	printf 'artifact\tsha256\tbytes\n'
	for artifact in \
		"$iso_tree/sp11/rootfs.sfs" \
		"$iso_tree/sp11/initramfs-$release-live.img" \
		"$grub_efi" \
		"$efi_image" \
		"$firmware_image" \
		"$iso_output"; do
		printf '%s\t%s\t%s\n' \
			"$(basename "$artifact")" \
			"$(sha256sum "$artifact" | awk '{print $1}')" \
			"$(stat -c '%s' "$artifact")"
	done
} >"$output_dir/ARTIFACTS.tsv"

printf '%s\n' \
	'HELD: no distribution-package source closure, install qualification, or release authorization.' \
	>"$output_dir/HOLD-REASONS"
if [[ -n "$local_proprietary_firmware_root" ]]; then
	printf '%s\n' \
		'HELD: contains machine-local proprietary firmware; never redistribute.' \
		>>"$output_dir/HOLD-REASONS"
fi
find "$output_dir" -type f -exec touch -d "@$source_date_epoch" {} +

"$script_dir/audit-held-live-image.sh" "$output_dir"

printf '\nHeld live image: %s\n' "$iso_output"
printf 'Artifact manifest: %s\n' "$output_dir/ARTIFACTS.tsv"
sha256sum "$iso_output"
