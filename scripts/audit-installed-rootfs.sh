#!/bin/bash

# Audit a newly built held installed-system artifact. This never extracts to or
# modifies the running host.

set -euo pipefail

release="7.1.3-sp11-suspend-review20"
source_date_epoch=1785076525
expected_wallpaper="1fdc98d786badbf332460460da51496c3674cbead0d501f0e98708c4bb0bb5ac"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
artifact_dir="${1:-}"

[[ $EUID -eq 0 ]] || {
	printf 'Run with sudo/root so every staged metadata file can be audited.\n' \
		>&2
	exit 1
}
[[ -n "$artifact_dir" ]] || {
	printf 'Usage: %s ARTIFACT_DIRECTORY\n' "$0" >&2
	exit 2
}
artifact_dir="$(realpath -e -- "$artifact_dir")"
case "$artifact_dir" in
"$repo_root/work"/installed-rootfs-*) ;;
*)
	printf 'Refusing artifact outside the installed-rootfs work namespace.\n' >&2
	exit 1
	;;
esac

rootfs="$artifact_dir/rootfs"
archive="$artifact_dir/sp11-installed-rootfs.tar.zst"
audit_tmp="$(mktemp -d /tmp/sp11-installed-root-audit.XXXXXX)"
trap 'find "$audit_tmp" -depth -delete' EXIT
for required in \
	"$rootfs" \
	"$archive" \
	"$artifact_dir/ARTIFACTS.tsv" \
	"$artifact_dir/ROOTFS-FILES.tsv" \
	"$artifact_dir/BOOT-PAYLOAD.tsv" \
	"$artifact_dir/LOCAL-STAGING-NOT-FOR-RELEASE"; do
	[[ -e "$required" && ! -L "$required" ]] || {
		printf 'Missing or unsafe artifact member: %s\n' "$required" >&2
		exit 1
	}
done

wallpaper="$rootfs/usr/share/backgrounds/sp11/tux-surface.png"
[[ -f "$wallpaper" && ! -L "$wallpaper" &&
	"$(stat -c '%s' "$wallpaper")" == "4789340" &&
	"$(sha256sum "$wallpaper" | awk '{print $1}')" == \
	"$expected_wallpaper" ]] || {
	printf 'Installed wallpaper is missing or has the wrong identity.\n' >&2
	exit 1
}
grep -Fqx "picture-uri='file:///usr/share/backgrounds/sp11/tux-surface.png'" \
	"$rootfs/etc/dconf/db/local.d/00-sp11-installed" || {
	printf 'Installed wallpaper is not configured as the GNOME default.\n' >&2
	exit 1
}
grep -Fqx "accent-color='orange'" \
	"$rootfs/etc/dconf/db/local.d/00-sp11-installed" || {
	printf 'Installed GNOME orange accent default is missing.\n' >&2
	exit 1
}
grep -Fqx 'MODULES+=(autofs4)' \
	"$rootfs/etc/mkinitcpio.conf.d/91-sp11-autofs.conf" || {
	printf 'Installed initramfs does not include the autofs4 compatibility module.\n' >&2
	exit 1
}

awk -F '\t' '
	NR == 1 {
		if ($0 != "artifact\tsha256\tbytes")
			bad = 1
		next
	}
	NF != 3 || $2 !~ /^[0-9a-f]{64}$/ || $3 !~ /^[0-9]+$/ {
		bad = 1
	}
	END { exit bad || NR != 6 }
' "$artifact_dir/ARTIFACTS.tsv" || {
	printf 'Malformed installed-root artifact table.\n' >&2
	exit 1
}
while IFS=$'\t' read -r artifact expected_sha expected_bytes; do
	[[ "$artifact" != "artifact" ]] || continue
	case "$artifact" in
	sp11-installed-rootfs.tar.zst|ROOTFS-FILES.tsv|BOOT-PAYLOAD.tsv)
		artifact_path="$artifact_dir/$artifact"
		;;
	"Image-$release"|x1e80100-microsoft-denali-oled.dtb)
		artifact_path="$artifact_dir/boot/$artifact"
		;;
	*)
		printf 'Unexpected installed-root artifact member: %s\n' \
			"$artifact" >&2
		exit 1
		;;
	esac
	[[ -f "$artifact_path" && ! -L "$artifact_path" &&
		"$(stat -c '%s' "$artifact_path")" == "$expected_bytes" &&
		"$(sha256sum "$artifact_path" | awk '{print $1}')" == \
			"$expected_sha" ]] || {
		printf 'Installed-root artifact member mismatch: %s\n' \
			"$artifact" >&2
		exit 1
	}
done <"$artifact_dir/ARTIFACTS.tsv"

expected_archive_sha="$(
	awk -F '\t' \
		'$1 == "sp11-installed-rootfs.tar.zst" { print $2 }' \
		"$artifact_dir/ARTIFACTS.tsv"
)"
[[ "$expected_archive_sha" =~ ^[0-9a-f]{64}$ &&
	"$(sha256sum "$archive" | awk '{print $1}')" == \
	"$expected_archive_sha" ]] || {
	printf 'Installed-rootfs archive identity mismatch.\n' >&2
	exit 1
}
zstd -q -t -- "$archive"
tar --zstd -tf "$archive" |
	awk '
		/^\// || /(^|\/)\.\.(\/|$)/ { bad = 1 }
		END { exit bad }
	' || {
	printf 'Unsafe installed-rootfs archive path.\n' >&2
	exit 1
}

awk -F '\t' '
	NR == 1 {
		if ($0 != "path\tbytes\tsha256")
			bad = 1
		next
	}
	NF != 3 || $1 !~ /^boot\/[^/]+$/ ||
		$2 !~ /^[0-9]+$/ || $3 !~ /^[0-9a-f]{64}$/ {
		bad = 1
	}
	END { exit bad || NR != 3 }
' "$artifact_dir/BOOT-PAYLOAD.tsv" || {
	printf 'Malformed installed-root boot manifest.\n' >&2
	exit 1
}
while IFS=$'\t' read -r path expected_bytes expected_sha; do
	[[ "$path" != "path" ]] || continue
	boot_path="$artifact_dir/$path"
	[[ -f "$boot_path" && ! -L "$boot_path" &&
		"$(stat -c '%s' "$boot_path")" == "$expected_bytes" &&
		"$(sha256sum "$boot_path" | awk '{print $1}')" == \
			"$expected_sha" ]] || {
		printf 'Installed-root boot payload mismatch: %s\n' "$path" >&2
		exit 1
	}
done <"$artifact_dir/BOOT-PAYLOAD.tsv"

verification_manifest="$audit_tmp/ROOTFS-FILES.tsv"
"$script_dir/manifest-installed-rootfs.py" \
	"$rootfs" "$verification_manifest"
cmp -- "$artifact_dir/ROOTFS-FILES.tsv" "$verification_manifest" || {
	printf 'Installed-root tree differs from its complete manifest.\n' >&2
	exit 1
}

for forbidden in \
	home/live \
	opt/sp11-beta-installer \
	usr/share/doc/sp11-beta/docs-FRESH-INSTALLER-DESIGN.md \
	etc/sp11-live-release \
	etc/sudoers.d/10-sp11-live \
	etc/systemd/system/sp11-live-session.service \
	etc/systemd/system/getty@tty1.service.d/autologin.conf; do
	[[ ! -e "$rootfs/$forbidden" && ! -L "$rootfs/$forbidden" ]] || {
		printf 'Live-only state leaked into installed root: /%s\n' \
			"$forbidden" >&2
		exit 1
	}
done
[[ ! -e "$rootfs/etc/gdm/custom.conf" ]] || {
	! grep -Eq 'AutomaticLogin|[[:space:]]live([[:space:]]|$)' \
		"$rootfs/etc/gdm/custom.conf"
} || {
	printf 'GDM autologin leaked into the installed root.\n' >&2
	exit 1
}
[[ ! -s "$rootfs/etc/machine-id" ]] || {
	printf 'Installed-root machine-id must be empty.\n' >&2
	exit 1
}
[[ ! -e "$rootfs/etc/fstab" ]] || {
	printf 'Installed-root artifact must not contain a target-specific fstab.\n' >&2
	exit 1
}
[[ -f "$rootfs/etc/sp11-installed-root-release" ]] || {
	printf 'Installed-root release identity is missing.\n' >&2
	exit 1
}
grep -Fxq 'SP11_FRESH_ROOTFS=1' \
	"$rootfs/etc/sp11-installed-root-release"
grep -Fxq 'SP11_EXTERNAL_FIRMWARE_REQUIRED=1' \
	"$rootfs/etc/sp11-installed-root-release"
grep -Fxq 'SP11_HOST_ID_PROVISIONING_REQUIRED=1' \
	"$rootfs/etc/sp11-installed-root-release"

for generated_state in \
	etc/nvme/hostid \
	etc/nvme/hostnqn \
	etc/ca-certificates/extracted/java-cacerts.jks \
	var/cache/ldconfig/aux-cache; do
	[[ ! -e "$rootfs/$generated_state" &&
		! -L "$rootfs/$generated_state" ]] || {
		printf 'Target-generated state leaked into installed root: /%s\n' \
			"$generated_state" >&2
		exit 1
	}
done
if find "$rootfs/var/cache/fontconfig" \
	-mindepth 1 -maxdepth 1 -type f \
	! -name CACHEDIR.TAG -print -quit 2>/dev/null | grep -q .; then
	printf 'Generated fontconfig cache leaked into installed root.\n' >&2
	exit 1
fi

package_descriptions=("$rootfs"/var/lib/pacman/local/*/desc)
[[ "${#package_descriptions[@]}" -eq 663 ]] || {
	printf 'Unexpected installed package database count: %s\n' \
		"${#package_descriptions[@]}" >&2
	exit 1
}
for description in "${package_descriptions[@]}"; do
	awk -v expected="$source_date_epoch" '
		$0 == "%INSTALLDATE%" {
			count += 1
			if ((getline value) <= 0 || value != expected)
				bad = 1
		}
		END { exit bad || count != 1 }
	' "$description" || {
		printf 'Non-deterministic package INSTALLDATE: %s\n' \
			"${description#"$rootfs/"}" >&2
		exit 1
	}
done

awk -F: '
	$1 == "root" {
		found = 1
		if ($2 !~ /^!/)
			bad = 1
	}
	END { exit bad || !found }
' "$rootfs/etc/shadow" || {
	printf 'Root account is not locked.\n' >&2
	exit 1
}
if find "$rootfs/home" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
	printf 'Installed-root artifact contains a pre-created home directory.\n' >&2
	exit 1
fi

for enabled_unit in \
	gdm.service \
	NetworkManager.service \
	bluetooth.service \
	systemd-resolved.service \
	power-profiles-daemon.service \
	sp11-bluetooth-address.service \
	sp11-noidle.service \
	sp11-power-profile-cpufreq.service \
	sp11-charge-limit.service; do
	[[ "$(systemctl --root="$rootfs" is-enabled "$enabled_unit")" == \
		"enabled" ]] || {
		printf 'Required installed unit is not enabled: %s\n' \
			"$enabled_unit" >&2
		exit 1
	}
done
[[ "$(systemctl --root="$rootfs" is-enabled iio-sensor-proxy.service)" == \
	"masked" ]] || {
	printf 'Unsafe unconfigured unit is not masked: %s\n' \
		'iio-sensor-proxy.service' >&2
	exit 1
}
[[ "$(systemctl --root="$rootfs" is-enabled sp11-sensors.service)" == \
	"disabled" ]] || {
	printf 'Unconfigured installed unit is not disabled: %s\n' \
		'sp11-sensors.service' >&2
	exit 1
}
[[ "$(systemctl --root="$rootfs" is-enabled sp11-ir-bridge.service)" == \
	"static" ]] || {
	printf 'IR bridge unit is unexpectedly installable/enabled: %s\n' \
		'sp11-ir-bridge.service' >&2
	exit 1
}

module_count="$(
	find "$rootfs/usr/lib/modules/$release" -type f -name '*.ko' -printf . |
		wc -c
)"
[[ "$module_count" -eq 3759 ]] || {
	printf 'Unexpected installed-root module count: %s\n' "$module_count" >&2
	exit 1
}
for required_binary in \
	usr/local/libexec/sp11-iptsd \
	usr/local/libexec/sp11-iptsd-check-device \
	usr/local/libexec/power-profiles-daemon-sp11; do
	[[ -x "$rootfs/$required_binary" ]] || {
		printf 'Missing installed-root executable: /%s\n' \
			"$required_binary" >&2
		exit 1
	}
done

actual_firmware="$audit_tmp/firmware-actual"
expected_firmware="$audit_tmp/firmware-expected"
find "$rootfs/usr/lib/firmware" -type f -printf '%P\n' |
	LC_ALL=C sort >"$actual_firmware"
{
	awk -F '\t' 'NR > 1 { print $1 }' \
		"$repo_root/firmware/allowlist.tsv"
	awk -F '\t' 'NR > 1 { print $1 }' \
		"$repo_root/firmware/derived.tsv"
	printf '%s\n' \
		qcom/x1e80100/X1E80100-Microsoft-Surface-Pro-11-tplg.bin
} | LC_ALL=C sort >"$expected_firmware"
cmp -- "$expected_firmware" "$actual_firmware" || {
	printf 'Installed-root firmware differs from the public-base manifests.\n' >&2
	exit 1
}
while IFS=$'\t' read -r external_path _rest; do
	[[ "$external_path" != "path" ]] || continue
	[[ ! -e "$rootfs/usr/lib/firmware/$external_path" ]] || {
		printf 'Owner firmware leaked into installed-root artifact: %s\n' \
			"$external_path" >&2
		exit 1
	}
done <"$repo_root/firmware/external-required.tsv"

[[ ! -s "$rootfs/var/log/pacman.log" ]] || {
	printf 'Installed-root pacman log was not sanitized.\n' >&2
	exit 1
}
if find "$rootfs/var/cache/pacman/pkg" "$rootfs/tmp" "$rootfs/var/tmp" \
	-mindepth 1 -print -quit | grep -q .; then
	printf 'Installed-root cache or temporary state is not empty.\n' >&2
	exit 1
fi

printf 'Installed-system root artifact audit passed.\n'
printf 'Archive SHA-256: %s\n' "$expected_archive_sha"
printf 'Rootfs entries: %s\n' \
	"$(( $(wc -l <"$artifact_dir/ROOTFS-FILES.tsv") - 1 ))"
