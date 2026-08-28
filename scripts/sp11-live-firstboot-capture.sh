#!/bin/bash

# Collect bounded diagnostics from the SP11 live image. Nothing is transmitted.

set -u

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
capture_dir=""
timestamp="$(date -u +%Y%m%dT%H%M%S%z)"

if [[ "$(id -u)" -ne 1000 ]]; then
	printf 'Run this script as the live user, not through sudo.\n' >&2
	exit 1
fi

script_source="$(findmnt -rn -T "$script_dir" -o SOURCE 2>/dev/null || true)"
if [[ -n "$script_source" &&
	"$(blkid -s LABEL -o value "$script_source" 2>/dev/null || true)" == \
	"SP11FW" && -w "$script_dir" ]]; then
	capture_dir="$script_dir"
fi

if [[ -z "$capture_dir" ]]; then
	firmware_device="$(readlink -e /dev/disk/by-label/SP11FW 2>/dev/null || true)"
	if [[ -n "$firmware_device" ]]; then
		capture_dir="$(
			findmnt -rn -S "$firmware_device" -o TARGET |
				head -n 1 || true
		)"
		if [[ -z "$capture_dir" ]] && command -v udisksctl >/dev/null; then
			udisksctl mount -b "$firmware_device" >/dev/null 2>&1 || true
			capture_dir="$(
				findmnt -rn -S "$firmware_device" -o TARGET |
					head -n 1 || true
			)"
		fi
	fi
fi

if [[ -z "$capture_dir" || ! -d "$capture_dir" ||
	! -w "$capture_dir" ]]; then
	capture_dir="/home/live"
	printf 'SP11FW is unavailable; saving to the volatile live home: %s\n' \
		"$capture_dir" >&2
fi

[[ -d "$capture_dir" && -w "$capture_dir" ]] || {
	printf 'Capture directory is unavailable or not writable: %s\n' \
		"$capture_dir" >&2
	exit 1
}
output_file="$capture_dir/live-image-firstboot-$timestamp.txt"
touch "$output_file" || exit 1
chmod 0600 "$output_file" 2>/dev/null || true
exec > >(tee "$output_file") 2>&1

section()
{
	printf '\n=== %s ===\n' "$1"
}

section identity
date -Ins
uname -a
cat /proc/cmdline
id
stat -c '%u:%g:%a %n' /home/live
printf 'Capture target: %s\n' "$output_file"

section "external firmware import"
if [[ -f /etc/sp11-external-firmware ]]; then
	cat /etc/sp11-external-firmware
else
	printf '/etc/sp11-external-firmware is absent\n'
fi
if [[ -f /etc/sp11-external-firmware-status ]]; then
	printf '%s\n' 'Import status trail:'
	cat /etc/sp11-external-firmware-status
else
	printf '/etc/sp11-external-firmware-status is absent\n'
fi
sudo journalctl -b -k --no-pager |
	grep -Ei 'SP11FW|owner-supplied firmware|firmware imported|incompatible' ||
	true

section "failed services"
SYSTEMD_COLORS=0 systemctl --no-pager --full --failed || true

section Bluetooth
SYSTEMD_COLORS=0 systemctl --no-pager --full status \
	sp11-bluetooth-address.service bluetooth.service || true
bluetoothctl list || true
bluetoothctl show || true
rfkill list || true

section "network devices"
nmcli --colors no device status || true
ip -brief link || true

section "camera packages and devices"
pacman -Q \
	libcamera \
	libcamera-tools \
	pipewire \
	pipewire-libcamera \
	wireplumber \
	snapshot \
	v4l-utils || true
ls -l /dev/media* /dev/video* /dev/v4l-subdev* || true
v4l2-ctl --list-devices || true

section "libcamera enumeration"
LIBCAMERA_LOG_LEVELS='*:DEBUG' timeout 30s cam -l || true

section PipeWire
wpctl status || true
SYSTEMD_COLORS=0 systemctl --user --no-pager --full status \
	pipewire.service wireplumber.service || true

section "audio devices and UCM"
aplay -l || true
arecord -l || true
alsaucm listcards || true
alsaucm -c hw:0 dump text || true
amixer -c 0 controls || true

section "audio kernel log"
sudo journalctl -b -k --no-pager |
	grep -Ei \
		'alsa|asoc|audio|sound|snd|lpass|q6|adsp|wsa|soundwire|topolog|tplg' ||
	true

section "audio userspace log"
journalctl --user -b --no-pager |
	grep -Ei 'alsa|audio|pipewire|wireplumber|ucm|spa.alsa' ||
	true

section "media topology"
shopt -s nullglob
for media_device in /dev/media*; do
	media-ctl -d "$media_device" -p || true
done
shopt -u nullglob

section "camera kernel log"
sudo journalctl -b -k --no-pager |
	grep -Ei \
		'camss|camera|imx681|ov13858|vd55|cci|csiphy|csid|vfe|media|video' ||
	true

section "camera userspace log"
journalctl --user -b --no-pager |
	grep -Ei 'snapshot|camera|libcamera|pipewire|wireplumber' ||
	true

section "Wi-Fi kernel log"
sudo journalctl -b -k --no-pager |
	grep -Ei 'ath12k|wcn7850|board.data|board-2|qmi failed' ||
	true

section completion
printf 'Capture saved to:\n%s\n' "$output_file"
sync "$output_file"
