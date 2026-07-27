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

First boot the preserved base kernel. The rollback script refuses to remove the
module tree or boot payload while the alpha kernel is running.

Then use `scripts/rollback.sh` from the same release used for installation. It
removes only files listed in that release manifest. Review its dry-run output
before confirming removal with `--apply`; it regenerates module metadata and
the GRUB configuration afterward.

If the machine cannot boot, use the base project's recovery procedure or Linux
recovery media to restore the previous GRUB default.
