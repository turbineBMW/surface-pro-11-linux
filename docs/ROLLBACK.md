# Rollback and recovery

## Boot rollback

The beta installer must preserve the existing kernel and must not silently set
the new GRUB entry as the persistent default. If the test boot fails, power the
machine off, reopen GRUB, and select the known-good base entry.

Do not delete the base kernel, its modules, its DTB, or its initramfs while
testing this beta.

## Disable the userspace integrations

From a working boot, the reversible first response is:

```sh
sudo systemctl disable --now sp11-power-profile-cpufreq.service
sudo systemctl disable --now sp11-charge-limit.service
sudo systemctl disable --now sp11-bluetooth-address.service
sudo systemctl disable --now sp11-noidle.service
sudo systemctl stop 'sp11-iptsd@*.service'
```

The runtime-idle guard is a `systemd-suspend.service` drop-in rather than an
enabled service. Do not remove only the guard while booted with
`sp11_deep_idle=1`; select the conservative rollback kernel or remove that
kernel parameter first.

If a Windows Bluetooth controller identity override was configured for a Flex
Keyboard, remove `/etc/sp11/bluetooth-address.conf` and reboot. The address
helper will return to the firmware EFI address; BlueZ bonds stored below the
override adapter directory will no longer be active.

Stopping the cpufreq companion restores the hardware maximum on every policy.
Disabling `sp11-noidle.service` does not re-enable state1 until its sysfs values
are changed or the machine reboots; do not do that on the experimental kernel
unless you are intentionally diagnosing deep idle.

Disabling the charge-limit service prevents future boot applications, but the
currently programmed window remains active until firmware resets it. To allow
charging to 100% immediately, write an end threshold of 100:

```sh
echo 100 | sudo tee \
  /sys/class/power_supply/qcom-battmgr-bat/charge_control_end_threshold
```

## Restore the short power-button action

To restore systemd's default short power-button action, remove the project
drop-in and reload logind:

```sh
sudo rm /etc/systemd/logind.conf.d/10-sp11-power-key.conf
sudo systemctl reload systemd-logind.service
```

This logind configuration reload does not require restarting the service or
the graphical session.

## Restore the logind service watchdog

To remove the beta baseline's lid-suspend watchdog override, remove only its
drop-in and reboot:

```sh
sudo rm /etc/systemd/system/systemd-logind.service.d/10-sp11-suspend-watchdog.conf
sudo systemctl daemon-reload
sudo reboot
```

Do not restart logind from inside an active graphical session. A normal reboot
restores the vendor watchdog without invalidating the compositor's existing
session-device file descriptors.

## Full removal

The preferred removal path is the held live image. Boot it, verify the target
partition paths, and run the read-only offline preflight:

```sh
sudo sp11-rollback-live \
  --root-device /dev/nvme0n1p5 \
  --efi-device /dev/nvme0n1p1 \
  --report /run/media/live/SP11FW/rollback-preflight.txt
```

Do not copy those development-tablet paths without confirming them with
`lsblk`. Both targets must be unmounted before the wrapper starts. The
preflight mounts them read-only and verifies the complete transaction.

Apply requires both a separate flag and the exact held-local confirmation:

```sh
sudo sp11-rollback-live \
  --root-device /dev/nvme0n1p5 \
  --efi-device /dev/nvme0n1p1 \
  --apply \
  --confirm-held-local-rollback sp11-beta-review20 \
  --report /run/media/live/SP11FW/rollback-apply.txt
```

The wrapper isolates the target from the live system's `/run`, mounts it
writable only after read-only validation and confirmation, and invokes the
exact rollback tool embedded in the image. The rollback requires a complete
transaction marker, verifies every regular rollback-state file against
`STATE-SHA256SUMS`, verifies its separately recorded symlink identities,
removes only recorded new paths, never removes a reused compatible module
tree, restores preserved files and service enablement, regenerates module
metadata and GRUB, and rechecks the Windows loader, chainloader, and EFI entry.

The live path completed its physical qualification on the development Surface
Pro 11. A fresh transaction survived an installed candidate boot and deep
suspend/resume, passed the live read-only preflight, and rolled back through
the separately confirmed apply. The restored system booted its persistent
qualified entry with zero failed units, exact Windows loader and EFI state,
all recorded created paths absent, all saved files and symlinks restored, the
reused module tree retained, and the pre-install service enablement restored.

`grub.cfg` is regenerated during apply. Qualification therefore verifies its
preserved `/etc/grub.d` inputs byte-for-byte and its resulting menu
semantically: preserved entry count, required qualified/Windows entries, no
candidate path or exact candidate ID, and no pending one-shot. It does not
require the regenerated file to have the old generated-file SHA-256.

Direct installed-system rollback remains available for recovery development.
Its dry run may run from the beta kernel, but apply is blocked while an
integration kernel is active. If that legacy path is used, first boot an
independent preserved kernel. The script stops the power-profiles daemon
before restoring its live wrapper executable.

If the machine cannot boot, use the base project's recovery procedure or Linux
recovery media to restore the previous GRUB default.
