#!/bin/sh
# Restart SP11 iptsd around system sleep so stylus reports survive SPI-HID reset.

set -eu

SYSTEMCTL="/usr/bin/systemctl"
SYSTEMD_ESCAPE="/usr/bin/systemd-escape"
CHECK_DEVICE="/usr/local/libexec/sp11-iptsd-check-device"
BINARY="/usr/local/libexec/sp11-iptsd"
STATE="/run/sp11-iptsd-sleep.state"
UNIT_GLOB="sp11-iptsd@*.service"

log() {
    echo "sp11-iptsd-sleep: $*"
}

operation="${2:-unknown}"
phase="${1:-unknown}"

case "$operation" in
    suspend|hibernate|hybrid-sleep|suspend-then-hibernate)
        ;;
    *)
        exit 0
        ;;
esac

case "$phase" in
    pre)
        {
            printf 'boot_id=%s\n' "$(cat /proc/sys/kernel/random/boot_id)"
            $SYSTEMCTL list-units "$UNIT_GLOB" --state=active --plain --no-legend \
                | awk '{print "unit=" $1}'
        } >"$STATE"

        units="$($SYSTEMCTL list-units "$UNIT_GLOB" --state=active --plain --no-legend \
            | awk '{print $1}')"
        stopped=0
        for unit in $units; do
            old_pid="$($SYSTEMCTL show "$unit" -p MainPID --value)"
            [ "$old_pid" -gt 0 ] || {
                log "pre failure: invalid PID for $unit"
                exit 1
            }
            [ "$(readlink -f "/proc/$old_pid/exe")" = "$BINARY" ] || {
                log "pre failure: executable mismatch for $unit PID $old_pid"
                exit 1
            }
            printf 'old=%s:%s\n' "$unit" "$old_pid" >>"$STATE"
            $SYSTEMCTL stop "$unit"
            stopped=$((stopped + 1))
            log "pre stopped $unit PID $old_pid"
        done
        log "pre complete: stopped=$stopped operation=$operation"
        ;;
    post)
        sleep 1
        eligible=0
        attempts=0
        while [ "$attempts" -lt 50 ]; do
            eligible=0
            for device in /dev/hidraw*; do
                [ -e "$device" ] || continue
                if "$CHECK_DEVICE" --quiet "$device"; then
                    instance="$($SYSTEMD_ESCAPE --path "$device")"
                    unit="sp11-iptsd@$instance.service"
                    $SYSTEMCTL restart "$unit"
                    ready=0
                    ready_attempts=0
                    new_pid=0
                    owners=""
                    executable=""
                    while [ "$ready_attempts" -lt 50 ]; do
                        new_pid="$($SYSTEMCTL show "$unit" -p MainPID --value)"
                        executable=""
                        if [ "$new_pid" -gt 0 ]; then
                            executable="$(readlink -f "/proc/$new_pid/exe" 2>/dev/null || true)"
                        fi
                        owners="$(fuser "$device" 2>/dev/null || true)"
                        owner_count="$(printf '%s\n' "$owners" | awk '{print NF}')"
                        owner_pid="$(printf '%s\n' "$owners" | awk '{print $1}')"
                        if [ "$($SYSTEMCTL is-active "$unit" || true)" = "active" ] \
                            && [ "$executable" = "$BINARY" ] \
                            && [ "$owner_count" -eq 1 ] \
                            && [ "$owner_pid" = "$new_pid" ]; then
                            ready=1
                            break
                        fi
                        ready_attempts=$((ready_attempts + 1))
                        sleep 0.1
                    done
                    [ "$ready" -eq 1 ] || {
                        log "post failure: readiness timeout for $unit PID $new_pid executable=$executable owners=$owners"
                        exit 1
                    }
                    eligible=$((eligible + 1))
                    log "post started $unit PID $new_pid for $device readiness_attempts=$ready_attempts"
                fi
            done
            [ "$eligible" -gt 0 ] && break
            attempts=$((attempts + 1))
            sleep 0.1
        done
        [ "$eligible" -gt 0 ] || {
            log "post failure: no eligible digitizer appeared"
            exit 1
        }
        rm -f "$STATE"
        log "post complete: eligible=$eligible operation=$operation"
        ;;
    *)
        exit 0
        ;;
esac

exit 0
