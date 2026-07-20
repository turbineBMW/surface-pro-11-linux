#!/bin/bash

# Restore the exact files preserved by install.sh. The default is dry-run.

set -euo pipefail

apply=0
state_path="/var/lib/sp11-alpha/latest"

usage() {
	printf 'Usage: sudo %s [--state BACKUP_DIRECTORY] [--apply]\n' "$0"
}

while (($#)); do
	case "$1" in
		--state) state_path="$2"; shift 2 ;;
		--apply) apply=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done

[[ $EUID -eq 0 ]] || { printf 'Run with sudo/root.\n' >&2; exit 1; }
case "$(uname -r)" in
	7.1.3-sp11-touch-practical8|7.1.3-sp11-sanitized1|7.1.3-sp11-sanitized2)
	printf 'Refusing full removal while the alpha kernel is running.\n' >&2
	printf 'Boot the preserved base kernel, then run rollback again.\n' >&2
	exit 1
		;;
esac
state_path="$(readlink -f -- "$state_path")"
[[ "$state_path" == /var/lib/sp11-alpha/backups/* ]] || {
	printf 'Unsafe rollback state path: %s\n' "$state_path" >&2
	exit 1
}
[[ -f "$state_path/install-info" && -f "$state_path/created-files.list" ]] || {
	printf 'Incomplete rollback state: %s\n' "$state_path" >&2
	exit 1
}

printf 'Rollback state: %s\n' "$state_path"
printf 'Will disable SP11 alpha integration services, remove only recorded new\n'
printf 'files/trees, restore preserved originals, and regenerate GRUB.\n'

if [[ $apply -ne 1 ]]; then
	printf 'Dry run only. Re-run with --apply to continue.\n'
	exit 0
fi

systemctl disable --now sp11-power-profile-cpufreq.service 2>/dev/null || true
systemctl disable --now sp11-bluetooth-address.service 2>/dev/null || true
systemctl disable --now sp11-noidle.service 2>/dev/null || true
systemctl stop 'sp11-iptsd@*.service' 2>/dev/null || true

tac "$state_path/created-files.list" | while IFS= read -r created_file; do
	[[ "$created_file" == /* && "$created_file" != "/" ]] || {
		printf 'Unsafe recorded file: %s\n' "$created_file" >&2
		exit 1
	}
	rm -f -- "$created_file"
done

if [[ -f "$state_path/created-trees.list" ]]; then
	tac "$state_path/created-trees.list" | while IFS= read -r created_tree; do
		case "$created_tree" in
			/boot/sp11-alpha|/usr/lib/modules/7.1.3-sp11-touch-practical8|\
			/usr/lib/modules/7.1.3-sp11-sanitized1|\
			/usr/lib/modules/7.1.3-sp11-sanitized2)
				rm -rf -- "$created_tree"
				;;
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

systemctl daemon-reload
udevadm control --reload
depmod -a
grub-mkconfig -o /boot/grub/grub.cfg

printf 'Rollback applied. Reboot and select the preserved base kernel.\n'
