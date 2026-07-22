# Rollback and recovery

## Boot rollback

The alpha installer must preserve the existing kernel and must not silently set
the new GRUB entry as the persistent default. If the test boot fails, power the
machine off, reopen GRUB, and select the known-good base entry.

Do not delete the base kernel, its modules, its DTB, or its initramfs while
testing this alpha.

## Disable the userspace integrations

From a working boot, the reversible first response is:

```sh
sudo systemctl disable --now sp11-power-profile-cpufreq.service
sudo systemctl disable --now sp11-bluetooth-address.service
sudo systemctl disable --now sp11-noidle.service
sudo systemctl stop 'sp11-iptsd@*.service'
```

If a Windows Bluetooth controller identity override was configured for a Flex
Keyboard, remove `/etc/sp11/bluetooth-address.conf` and reboot. The address
helper will return to the firmware EFI address; BlueZ bonds stored below the
override adapter directory will no longer be active.

Stopping the cpufreq companion restores the hardware maximum on every policy.
Disabling `sp11-noidle.service` does not re-enable state1 until its sysfs values
are changed or the machine reboots; do not do that on the experimental kernel
unless you are intentionally diagnosing deep idle.

To restore systemd's default short power-button action, remove the project
drop-in and reload logind:

```sh
sudo rm /etc/systemd/logind.conf.d/10-sp11-power-key.conf
sudo systemctl reload systemd-logind.service
```

This logind configuration reload does not require restarting the service or
the graphical session.

## Full removal

First boot the preserved base kernel. The rollback script refuses to remove the
module tree or boot payload while the alpha kernel is running.

Then use `scripts/rollback.sh` from the same release used for installation. It
removes only files listed in that release manifest. Review its dry-run output
before confirming removal with `--apply`; it regenerates module metadata and
the GRUB configuration afterward.

If the machine cannot boot, use the base project's recovery procedure or Linux
recovery media to restore the previous GRUB default.
