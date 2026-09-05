#!/bin/bash

# Restore the exact files preserved by install.sh. The default is dry-run.

set -euo pipefail

apply=0
offline_target=0
state_path="/var/lib/sp11-beta/latest"
managed_services=(
	power-profiles-daemon.service
	sp11-bluetooth-address.service
	sp11-noidle.service
	sp11-power-profile-cpufreq.service
	sp11-charge-limit.service
)

usage() {
	printf 'Usage: sudo %s [--state BACKUP_DIRECTORY] [--apply] [--offline-target]\n' "$0"
}

while (($#)); do
	case "$1" in
	--state) state_path="$2"; shift 2 ;;
	--apply) apply=1; shift ;;
	--offline-target) offline_target=1; shift ;;
	-h|--help) usage; exit 0 ;;
	*) usage >&2; exit 2 ;;
	esac
done

[[ $EUID -eq 0 ]] || { printf 'Run with sudo/root.\n' >&2; exit 1; }
if [[ $offline_target -eq 1 ]]; then
	[[ ( "${SP11_LIVE_OFFLINE_ROLLBACK:-}" == "sp11-beta-review20" || "${SP11_LIVE_OFFLINE_ROLLBACK:-}" == "sp11-beta-port73" ) &&
		-f /run/sp11-live-offline-rollback-authorized &&
		( "$(cat /run/sp11-live-offline-rollback-authorized)" == "sp11-beta-review20" ||
		"$(cat /run/sp11-live-offline-rollback-authorized)" == "sp11-beta-port73" ) ]] || {
		printf 'Offline rollback is restricted to the gated live wrapper.\n' >&2
		exit 1
	}
fi
state_path="$(readlink -f -- "$state_path")"
case "$state_path" in
	/var/lib/sp11-beta/backups/*|/var/lib/sp11-alpha/backups/*) ;;
	*)
	printf 'Unsafe rollback state path: %s\n' "$state_path" >&2
	exit 1
		;;
esac
[[ -f "$state_path/install-info" &&
	-f "$state_path/created-files.list" &&
	-f "$state_path/created-trees.list" &&
	-f "$state_path/transaction-status" &&
	-f "$state_path/STATE-SHA256SUMS" ]] || {
	printf 'Incomplete rollback state: %s\n' "$state_path" >&2
	exit 1
}
[[ "$(cat "$state_path/transaction-status")" == "complete" ]] || {
	printf 'Refusing incomplete install transaction: %s\n' "$state_path" >&2
	exit 1
}
(
	cd -- "$state_path"
	sha256sum -c STATE-SHA256SUMS
) || {
	printf 'Rollback-state integrity verification failed.\n' >&2
	exit 1
}
if [[ -f "$state_path/state-symlinks.tsv" ]]; then
	symlink_count=0
	while IFS=$'\t' read -r state_link state_target; do
		if [[ "$state_link" == "path" && "$state_target" == "target" ]]; then
			continue
		fi
		[[ "$state_link" == root/* &&
			"$state_link" != *"/../"* &&
			-n "$state_target" &&
			"$state_target" != *$'\t'* &&
			"$state_target" != *$'\n'* ]] || {
			printf 'Unsafe rollback-state symlink record: %q\n' \
				"$state_link" >&2
			exit 1
		}
		saved_link="$state_path/$state_link"
		[[ -L "$saved_link" &&
			"$(readlink -- "$saved_link")" == "$state_target" ]] || {
			printf 'Rollback-state symlink identity failed: %s\n' \
				"$state_link" >&2
			exit 1
		}
		((symlink_count += 1))
	done <"$state_path/state-symlinks.tsv"
	printf 'Verified %s rollback-state symlink identities.\n' \
		"$symlink_count"
fi
if [[ -f "$state_path/systemd-enable-state-before.tsv" ]]; then
	service_state_count=0
	while IFS=$'\t' read -r managed_service service_state; do
		if [[ "$managed_service" == "unit" &&
			"$service_state" == "state" ]]; then
			continue
		fi
		case "$managed_service" in
		power-profiles-daemon.service|\
		sp11-bluetooth-address.service|\
		sp11-noidle.service|\
		sp11-power-profile-cpufreq.service|\
		sp11-charge-limit.service) ;;
		*)
			printf 'Unsafe rollback service record: %q\n' \
				"$managed_service" >&2
			exit 1
			;;
		esac
		[[ "$service_state" =~ ^(enabled|enabled-runtime|disabled|static|\
indirect|masked|masked-runtime|linked|linked-runtime|alias|generated|\
transient|not-found)$ ]] || {
			printf 'Unsafe rollback service state: %q\n' \
				"$service_state" >&2
			exit 1
		}
		((service_state_count += 1))
	done <"$state_path/systemd-enable-state-before.tsv"
	[[ "$service_state_count" -eq "${#managed_services[@]}" ]] || {
		printf 'Incomplete rollback service-state manifest.\n' >&2
		exit 1
	}
fi

while IFS= read -r created_file; do
	[[ "$created_file" == /* && "$created_file" != "/" &&
		"$created_file" != *"/../"* ]] || {
		printf 'Unsafe recorded file: %s\n' "$created_file" >&2
		exit 1
	}
done <"$state_path/created-files.list"
while IFS= read -r created_tree; do
	case "$created_tree" in
	/boot/sp11-beta|/usr/lib/modules/7.1.3-sp11-suspend-review20|/usr/lib/modules/7.2.0-sp11-73beta1) ;;
	"") ;;
	*)
		printf 'Unsafe recorded tree: %s\n' "$created_tree" >&2
		exit 1
		;;
	esac
done <"$state_path/created-trees.list"

running_integration=0
case "$(uname -r)" in
7.1.3-sp11-touch-practical8|7.1.3-sp11-sanitized1|7.1.3-sp11-sanitized2|\
7.1.3-sp11-suspend-review20|7.2.0-sp11-73beta1)
	running_integration=1
	;;
esac

printf 'Rollback state: %s\n' "$state_path"
printf 'Will disable SP11 integration services, remove only recorded new\n'
printf 'files/trees, restore preserved originals, and regenerate GRUB.\n'
if [[ $offline_target -eq 1 ]]; then
	printf 'Execution: offline target mounted by the held live wrapper\n'
elif [[ $running_integration -eq 1 ]]; then
	printf 'Running kernel: %s (apply is blocked until a base kernel boots)\n' \
		"$(uname -r)"
fi

if [[ $apply -ne 1 ]]; then
	printf 'Dry run only. Re-run with --apply to continue.\n'
	exit 0
fi
[[ $offline_target -eq 1 || $running_integration -eq 0 ]] || {
	printf 'Refusing full removal while an SP11 integration kernel is running.\n' >&2
	printf 'Use the gated live-USB rollback wrapper instead.\n' >&2
	exit 1
}

# The installed power-profiles-daemon drop-in executes the SP11 wrapper
# directly. Stop it before restoring the saved wrapper or cp(1) can fail with
# ETXTBSY after the rollback has already removed the newly created boot files.
if [[ $offline_target -eq 0 ]]; then
	systemctl stop power-profiles-daemon.service 2>/dev/null || true
	systemctl disable --now \
		sp11-power-profile-cpufreq.service \
		sp11-charge-limit.service \
		sp11-bluetooth-address.service \
		sp11-noidle.service 2>/dev/null || true
	systemctl stop 'sp11-iptsd@*.service' 2>/dev/null || true
else
	systemctl disable \
		sp11-power-profile-cpufreq.service \
		sp11-charge-limit.service \
		sp11-bluetooth-address.service \
		sp11-noidle.service 2>/dev/null || true
fi

tac "$state_path/created-files.list" | while IFS= read -r created_file; do
	rm -f -- "$created_file"
done

if [[ -f "$state_path/created-trees.list" ]]; then
	tac "$state_path/created-trees.list" | while IFS= read -r created_tree; do
		case "$created_tree" in
			/boot/sp11-beta|\
			/usr/lib/modules/7.1.3-sp11-suspend-review20|\
			/usr/lib/modules/7.2.0-sp11-73beta1)
				rm -rf -- "$created_tree"
				;;
			"") ;;
			*)
				printf 'Unsafe recorded tree: %s\n' "$created_tree" >&2
				exit 1
				;;
		esac
	done
fi

if [[ -d "$state_path/root" ]]; then
	cp -a "$state_path/root/." /
fi

if [[ $offline_target -eq 0 ]]; then
	systemctl daemon-reload
	udevadm control --reload
fi
if [[ -f "$state_path/systemd-enable-state-before.tsv" ]]; then
	while IFS=$'\t' read -r managed_service service_state; do
		[[ "$managed_service" != "unit" ]] || continue
		case "$service_state" in
		enabled|linked)
			systemctl enable "$managed_service"
			;;
		enabled-runtime|linked-runtime)
			systemctl enable --runtime "$managed_service"
			;;
		disabled|not-found|static|indirect|alias|generated|transient)
			systemctl disable "$managed_service" 2>/dev/null || true
			;;
		masked)
			systemctl mask "$managed_service"
			;;
		masked-runtime)
			systemctl mask --runtime "$managed_service"
			;;
		esac
	done <"$state_path/systemd-enable-state-before.tsv"
fi
depmod -a
grub-mkconfig -o /boot/grub/grub.cfg

expected_windows_sha="$(
	sed -n 's/^windows_loader_sha256=//p' "$state_path/install-info"
)"
windows_loader="/efi/EFI/Microsoft/Boot/bootmgfw.efi"
[[ "$expected_windows_sha" =~ ^[0-9a-f]{64}$ &&
	-f "$windows_loader" &&
	"$(sha256sum "$windows_loader" | awk '{print $1}')" == \
	"$expected_windows_sha" ]] || {
	printf 'Windows Boot Manager identity changed during rollback.\n' >&2
	exit 1
}
if [[ $offline_target -eq 0 ]] &&
	! efibootmgr -v | grep -Fq 'Windows Boot Manager'; then
	printf 'Windows Boot Manager EFI entry is missing after rollback.\n' >&2
	exit 1
fi
if [[ -f /boot/grub/grubenv ]]; then
	next_entry="$(
		grub-editenv /boot/grub/grubenv list |
			sed -n 's/^next_entry=//p' |
			head -n1
	)"
	if [[ "$next_entry" == "sp11-beta-review20" || "$next_entry" == "sp11-beta-port73" ]]; then
		grub-editenv /boot/grub/grubenv unset next_entry
	fi
fi

if [[ $offline_target -eq 1 ]]; then
	printf 'Offline rollback applied. Shut down the live image and boot the restored system.\n'
else
	printf 'Rollback applied. Reboot and select the preserved base kernel.\n'
fi
