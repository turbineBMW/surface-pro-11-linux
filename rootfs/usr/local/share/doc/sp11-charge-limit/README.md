# Surface Pro 11 charge-limit service

`sp11-charge-limit.service` programs the Qualcomm battery manager's writable
charge-control thresholds at boot. The matching system-sleep hook programs them
again after suspend, hibernation, or hybrid sleep.

The default `/etc/sp11-charge-limit.conf` window is 75–80%. Change both integer
assignments there to use another supported window. The current driver accepts a
start threshold from 50 through 95 and an end threshold from 55 through 100;
the start value must be lower than the end value.

Check the live state with:

```sh
cat /sys/class/power_supply/qcom-battmgr-bat/charge_control_start_threshold
cat /sys/class/power_supply/qcom-battmgr-bat/charge_control_end_threshold
systemctl status sp11-charge-limit.service
```

The helper deliberately writes both values even when sysfs already reports the
configured window. This reprograms firmware after a remote battery-manager
restart instead of trusting the driver's cached readback.
