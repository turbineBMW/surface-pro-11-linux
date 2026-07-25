# SP11 battery charge limit

The root filesystem overlay contains a small boot and system-sleep integration
for the charge-threshold controls exposed by `qcom-battmgr` on the Surface Pro
11. It applies a configurable 75–80% window by default, checks exact readback,
and returns failure if the power-supply attributes never become writable or
firmware does not retain the requested values.

Run the isolated fake-sysfs tests with:

```sh
userspace/power/test-sp11-charge-limit.sh
```

The implementation was independently written from the Linux power-supply sysfs
interface and observations on the maintainer's own Surface Pro 11. It contains
no firmware, firmware-derived data, or third-party source.
