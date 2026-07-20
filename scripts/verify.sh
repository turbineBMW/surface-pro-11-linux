#!/bin/bash

set -euo pipefail

release="7.1.3-sp11-sanitized2"
boot_dir="${SP11_BOOT_DIR:-/boot/sp11-alpha}"
expected_image="d95b1cbba0e017f2430e65ce6ca5e3e276ef3d0dbcab7f68e999db2dd4143152"
expected_dtb="3de1d2e6b0d40fef35866ef6e024cb5164f30f1e44f0c0d0051cc7cf9a384ede"
failures=0

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*" >&2; failures=$((failures + 1)); }

[[ $EUID -eq 0 ]] || { printf 'Run with sudo/root.\n' >&2; exit 1; }

if [[ "$(uname -r)" == "$release" ]]; then pass "exact kernel release"; else fail "wrong kernel: $(uname -r)"; fi
if [[ "$(cat /proc/sys/kernel/tainted)" == 0 ]]; then pass "kernel untainted"; else fail "kernel tainted"; fi
if [[ "$(systemctl --failed --no-legend | wc -l)" == 0 ]]; then pass "zero failed units"; else fail "failed systemd units"; fi
if [[ "$(find /sys/fs/pstore -mindepth 1 -maxdepth 1 -type f | wc -l)" == 0 ]]; then pass "pstore empty"; else fail "pstore contains crash evidence"; fi

image="$boot_dir/Image-$release"
dtb="$boot_dir/x1e80100-microsoft-denali-oled.dtb"
if [[ -f "$image" && "$(sha256sum "$image" | awk '{print $1}')" == "$expected_image" ]]; then pass "kernel Image hash"; else fail "kernel Image hash"; fi
if [[ -f "$dtb" && "$(sha256sum "$dtb" | awk '{print $1}')" == "$expected_dtb" ]]; then pass "OLED DTB hash"; else fail "OLED DTB hash"; fi

for unit_name in power-profiles-daemon.service sp11-power-profile-cpufreq.service \
	sp11-noidle.service bluetooth.service; do
	if [[ "$(systemctl is-active "$unit_name" 2>/dev/null || true)" == active ]]; then
		pass "$unit_name active"
	else
		fail "$unit_name inactive"
	fi
done

profile="$(powerprofilesctl get 2>/dev/null || true)"
kernel_profile="$(cat /sys/class/platform-profile/platform-profile-0/profile 2>/dev/null || true)"
if [[ -n "$profile" && -n "$kernel_profile" ]]; then pass "profile daemon=$profile kernel=$kernel_profile"; else fail "platform profile unavailable"; fi

policy_count=0
for policy_dir in /sys/devices/system/cpu/cpufreq/policy*; do
	[[ -d "$policy_dir" ]] || continue
	policy_count=$((policy_count + 1))
	printf 'INFO  %s min=%s max=%s current=%s governor=%s\n' \
		"$(basename "$policy_dir")" \
		"$(cat "$policy_dir/scaling_min_freq")" \
		"$(cat "$policy_dir/scaling_max_freq")" \
		"$(cat "$policy_dir/scaling_cur_freq")" \
		"$(cat "$policy_dir/scaling_governor")"
done
if [[ $policy_count -eq 3 ]]; then pass "three SCMI cpufreq policies"; else fail "expected 3 cpufreq policies, found $policy_count"; fi

disabled_idle=0
for idle_control in /sys/devices/system/cpu/cpu*/cpuidle/state1/disable; do
	[[ -e "$idle_control" ]] || continue
	[[ "$(cat "$idle_control")" == 1 ]] && disabled_idle=$((disabled_idle + 1))
done
if [[ $disabled_idle -eq 12 ]]; then pass "state1 disabled on 12 CPUs"; else fail "state1 disabled on $disabled_idle CPUs"; fi

iptsd_units="$(systemctl list-units 'sp11-iptsd@*.service' --state=active --no-legend | wc -l)"
if [[ $iptsd_units -ge 1 ]]; then pass "iptsd active"; else fail "iptsd inactive"; fi

printf 'INFO  suspend success=%s fail=%s\n' \
	"$(cat /sys/power/suspend_stats/success)" \
	"$(cat /sys/power/suspend_stats/fail)"
printf 'INFO  Bluetooth connected devices=%s\n' "$(bluetoothctl devices Connected | wc -l)"

if [[ $failures -ne 0 ]]; then
	printf '\nVerification failed: %s gate(s).\n' "$failures" >&2
	exit 1
fi
printf '\nAutomated verification passed. Manually test touch, pen, audio, Bluetooth, and suspend.\n'
