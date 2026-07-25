#!/bin/sh

set -eu

script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
repo_root="$(CDPATH='' cd -- "$script_dir/../.." && pwd -P)"
helper="$repo_root/rootfs/usr/local/libexec/sp11-charge-limit"
temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

sysfs="$temporary/sysfs"
config="$temporary/charge-limit.conf"
mkdir -p "$sysfs"
printf '0\n' >"$sysfs/charge_control_start_threshold"
printf '0\n' >"$sysfs/charge_control_end_threshold"
printf 'START_THRESHOLD=75\nEND_THRESHOLD=80\n' >"$config"

SP11_CHARGE_LIMIT_SYSFS="$sysfs" \
SP11_CHARGE_LIMIT_CONFIG="$config" \
SP11_CHARGE_LIMIT_ATTEMPTS=1 \
	"$helper" apply

[ "$(cat "$sysfs/charge_control_start_threshold")" = 75 ]
[ "$(cat "$sysfs/charge_control_end_threshold")" = 80 ]

printf 'START_THRESHOLD=80\nEND_THRESHOLD=80\n' >"$config"
if SP11_CHARGE_LIMIT_SYSFS="$sysfs" \
   SP11_CHARGE_LIMIT_CONFIG="$config" \
   SP11_CHARGE_LIMIT_ATTEMPTS=1 \
	"$helper" apply >/dev/null 2>&1; then
	echo "invalid equal thresholds were accepted" >&2
	exit 1
fi

printf 'START_THRESHOLD=75\nEND_THRESHOLD=101\n' >"$config"
if SP11_CHARGE_LIMIT_SYSFS="$sysfs" \
   SP11_CHARGE_LIMIT_CONFIG="$config" \
   SP11_CHARGE_LIMIT_ATTEMPTS=1 \
	"$helper" apply >/dev/null 2>&1; then
	echo "out-of-range end threshold was accepted" >&2
	exit 1
fi

missing="$temporary/missing"
printf 'START_THRESHOLD=75\nEND_THRESHOLD=80\n' >"$config"
if SP11_CHARGE_LIMIT_SYSFS="$missing" \
   SP11_CHARGE_LIMIT_CONFIG="$config" \
   SP11_CHARGE_LIMIT_ATTEMPTS=1 \
	"$helper" apply >/dev/null 2>&1; then
	echo "missing sysfs attributes were accepted" >&2
	exit 1
fi

echo "sp11-charge-limit tests: PASS"
