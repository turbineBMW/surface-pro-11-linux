#!/bin/bash

# SPDX-License-Identifier: MIT

set -euo pipefail

expected_dmi="Microsoft Surface Pro, 11th Edition"
destination_root="/var/lib/sp11-sensors/root"
apply=0
hexagonrpcd=""
libhexagonrpc=""
libssc=""
sensor_root=""

usage() {
	cat <<EOF
Usage: sudo $0 --hexagonrpcd FILE --libhexagonrpc FILE --libssc FILE \
  --sensor-root DIRECTORY [--apply]

Without --apply, validate the hardware, binaries, and private sensor root
without changing the system.
EOF
}

while (($#)); do
	case "$1" in
		--hexagonrpcd) hexagonrpcd="$2"; shift 2 ;;
		--libhexagonrpc) libhexagonrpc="$2"; shift 2 ;;
		--libssc) libssc="$2"; shift 2 ;;
		--sensor-root) sensor_root="$2"; shift 2 ;;
		--apply) apply=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done

[[ -n "$hexagonrpcd" && -n "$libhexagonrpc" &&
   -n "$libssc" && -n "$sensor_root" ]] || {
	usage >&2
	exit 2
}

for command_name in cp find install readelf realpath systemctl; do
	command -v "$command_name" >/dev/null || {
		printf 'Missing required command: %s\n' "$command_name" >&2
		exit 1
	}
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
hexagonrpcd="$(realpath -- "$hexagonrpcd")"
libhexagonrpc="$(realpath -- "$libhexagonrpc")"
libssc="$(realpath -- "$libssc")"
sensor_root="$(realpath -- "$sensor_root")"

[[ "$(uname -m)" == "aarch64" ]] || {
	printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2
	exit 1
}

dmi="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
[[ "$dmi" == "$expected_dmi" ]] || {
	printf 'Unsupported hardware: %s\n' "$dmi" >&2
	exit 1
}

[[ -x "$hexagonrpcd" ]] || {
	printf 'Missing executable hexagonrpcd: %s\n' "$hexagonrpcd" >&2
	exit 1
}
[[ -f "$libssc" ]] || {
	printf 'Missing libssc shared library: %s\n' "$libssc" >&2
	exit 1
}
[[ -f "$libhexagonrpc" ]] || {
	printf 'Missing libhexagonrpc shared library: %s\n' "$libhexagonrpc" >&2
	exit 1
}
readelf -h "$hexagonrpcd" | grep -Fq 'Machine:                           AArch64' || {
	printf 'hexagonrpcd is not an AArch64 ELF binary.\n' >&2
	exit 1
}
readelf -d "$libssc" | grep -Fq 'Library soname: [libssc.so.2]' || {
	printf 'Expected a libssc.so.2 shared library.\n' >&2
	exit 1
}
readelf -d "$libhexagonrpc" |
	grep -Fq 'Library soname: [libhexagonrpc.so.0.4]' || {
	printf 'Expected a libhexagonrpc.so.0.4 shared library.\n' >&2
	exit 1
}

required_private=(
	"sensors/config/json.lst"
	"sensors/config/8380_crd_tcs3430_0.json"
	"sensors/config/sns_surface_color.json"
	"sensors/sns_reg.conf"
	"socinfo/hw_platform"
	"socinfo/platform_subtype"
	"socinfo/platform_subtype_id"
	"socinfo/platform_version"
	"socinfo/revision"
	"socinfo/soc_id"
)
for relative_file in "${required_private[@]}"; do
	[[ -f "$sensor_root/$relative_file" ]] || {
		printf 'Prepared sensor root is missing: %s\n' "$relative_file" >&2
		exit 1
	}
done

printf 'SP11 sensor preflight passed.\n'
printf '  daemon:       %s\n' "$hexagonrpcd"
printf '  daemon lib:   %s\n' "$libhexagonrpc"
printf '  libssc:       %s\n' "$libssc"
printf '  private root: %s\n' "$sensor_root"
printf '  destination:  %s\n' "$destination_root"

if [[ $apply -ne 1 ]]; then
	printf 'Preflight only. Re-run as root with --apply to install.\n'
	exit 0
fi

[[ $EUID -eq 0 ]] || {
	printf 'Run with sudo/root when using --apply.\n' >&2
	exit 1
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
state_dir="/var/lib/sp11-sensor-install"
backup_dir="$state_dir/backups/$timestamp"
staged_root="$(mktemp -d /var/lib/sp11-sensors.new.XXXXXX)"
trap 'rm -rf -- "$staged_root"' EXIT

mkdir -p -- "$backup_dir"
for existing in \
	/usr/local/libexec/sp11-hexagonrpcd \
	/usr/local/lib/sp11/libhexagonrpc.so.0.4 \
	/usr/local/lib/sp11/libssc.so.2 \
	/etc/systemd/system/sp11-sensors.service \
	/etc/systemd/system/iio-sensor-proxy.service \
	/etc/systemd/system/iio-sensor-proxy.service.d/10-sp11-sensors.conf \
	"$destination_root"; do
	if [[ -e "$existing" || -L "$existing" ]]; then
		mkdir -p -- "$backup_dir$(dirname -- "$existing")"
		cp -a -- "$existing" "$backup_dir$existing"
	fi
done

install -d -m0755 "$staged_root/sensors/persist/registry"
cp -aL -- "$sensor_root/sensors/config" "$staged_root/sensors/config"
install -m0644 "$sensor_root/sensors/sns_reg.conf" \
	"$staged_root/sensors/sns_reg.conf"
cp -aL -- "$sensor_root/socinfo" "$staged_root/socinfo"

if [[ -d "$sensor_root/sensors/persist/registry" ]]; then
	cp -aL -- "$sensor_root/sensors/persist/registry/." \
		"$staged_root/sensors/persist/registry/"
elif [[ -d "$sensor_root/sensors/registry" ]]; then
	cp -aL -- "$sensor_root/sensors/registry/." \
		"$staged_root/sensors/persist/registry/"
fi
for metadata in sns_reg_version parsed_file_list.csv; do
	if [[ -f "$sensor_root/sensors/persist/$metadata" ]]; then
		install -m0644 "$sensor_root/sensors/persist/$metadata" \
			"$staged_root/sensors/persist/$metadata"
	fi
done

find "$staged_root" -type d -exec chmod 0755 {} +
find "$staged_root" -type f -exec chmod 0644 {} +
chown -R root:root "$staged_root"

install -D -m0755 "$hexagonrpcd" /usr/local/libexec/sp11-hexagonrpcd
install -D -m0755 "$libhexagonrpc" \
	/usr/local/lib/sp11/libhexagonrpc.so.0.4
install -D -m0755 "$libssc" /usr/local/lib/sp11/libssc.so.2
install -D -m0644 "$repo_root/rootfs/etc/systemd/system/sp11-sensors.service" \
	/etc/systemd/system/sp11-sensors.service
install -D -m0644 \
	"$repo_root/rootfs/etc/systemd/system/iio-sensor-proxy.service.d/10-sp11-sensors.conf" \
	/etc/systemd/system/iio-sensor-proxy.service.d/10-sp11-sensors.conf

rm -rf -- "$destination_root"
mkdir -p -- "$(dirname -- "$destination_root")"
mv -- "$staged_root" "$destination_root"
trap - EXIT

systemctl unmask iio-sensor-proxy.service
systemctl daemon-reload
systemctl enable sp11-sensors.service
systemctl restart sp11-sensors.service
systemctl restart iio-sensor-proxy.service

cat >"$backup_dir/install-info" <<EOF
installed_at=$timestamp
hexagonrpcd=$hexagonrpcd
libhexagonrpc=$libhexagonrpc
libssc=$libssc
sensor_root=$sensor_root
EOF
ln -sfn "$backup_dir" "$state_dir/latest"

printf 'SP11 sensor stack installed.\n'
printf 'Backup: %s\n' "$backup_dir"
printf 'A full reboot is required for cold-path validation.\n'
