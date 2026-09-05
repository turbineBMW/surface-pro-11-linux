# Flex Keyboard poweroff guard (experimental, opt-in)

See `docs/BLUETOOTH.md` in the source tree for the workaround's scope and
evidence. In short: it was not shown to stop the attached keyboard's haptics
after battery poweroff reliably, later investigation points away from
Bluetooth, and it is therefore not enabled by the installer. Requires Python 3 and dbus-python, BlueZ, systemd, and the
configured paired keyboard address in `/etc/sp11/flex-keyboard-address`.

The guard runs its prepare action only while poweroff.target or
systemd-poweroff.service has a start job. An active Type=oneshot service with
RemainAfterExit=yes is ordered After=bluetooth.service and dbus.service, so
its stop action runs before those services are stopped. Ordinary service stop,
restart, suspend and reboot do not block the keyboard. The service is wanted
by bluetooth.service and PartOf it so restoration also runs after BlueZ restarts.

The durable root-only state file is
`/var/lib/sp11-flex-shutdown/restore.json`. It records the keyboard and adapter
addresses, original Blocked=false, version and boot ID. It contains no pairing
keys. The record is synced before the BlueZ property changes. Restoration uses
this saved identity even if the configured keyboard address changes later.
Originally blocked keyboards are left untouched without creating a record.

Commands (root required; use the configured privileged-command wrapper):

- `/usr/local/libexec/sp11-flex-shutdown check`: read-only readiness check.
- `/usr/local/libexec/sp11-flex-shutdown test`: block for two seconds, verify
  disconnection and attached interfaces, then restore automatically.
- `/usr/local/libexec/sp11-flex-shutdown restore`: remove only the helper-owned
  block; retain recovery metadata and report errors if restoration fails.
- `/usr/local/libexec/sp11-flex-shutdown prepare`: systemd poweroff action;
  a manual invocation outside a poweroff transaction does not block anything.

View logs with `journalctl -u sp11-flex-shutdown.service`. Before removing the
helper/service, run restore and verify restore.json is absent, then disable
the service. Do not delete recovery state to silence an error. If the keyboard
or adapter identity is no longer available, investigate that saved identity
before manually changing any device block state.

No firmware variables, Bluetooth keys, core keyboard drivers, adapter-wide
power settings, or detached reconnect rules are modified. The block necessarily
persists in BlueZ across boot until restoration executes. Booting another OS
before returning to Linux, or disabling BlueZ, postpones this Linux-side
restoration. Do not interpret one successful test as broad qualification.
