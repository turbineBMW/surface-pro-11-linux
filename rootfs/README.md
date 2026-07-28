# Experimental root filesystem overlay

This allowlisted tree contains only the integrations required by the qualified
machine:

- Bluetooth EFI-address setup service/helper
- conservative deep-idle fallback plus the qualified fail-closed runtime-idle
  suspend guard
- systemd-logind watchdog override qualified for long lid-triggered suspend
- dynamic iptsd udev/service/sleep lifecycle
- Surface platform-profile module loading and patched PPD selection
- early X1E VideoCC provider loading through an mkinitcpio configuration
  drop-in
- Qualcomm SSC startup and the SP11-specific libssc selection for the ambient
  color sensor
- three-tier power-profile cpufreq companion and sleep hook target
- verified 75–80% battery charge limit applied at boot and after system sleep
- short power-button press mapped to suspend through logind
- CC0 IMX681 simple-pipeline tuning data
- source-review-only bounded VD55G0-to-v4l2loopback IR bridge and independent
  illuminator-off helper (bounded on-device validation passed)

The future installer is intended to copy regular files with their repository
modes, create the power-profile system-sleep symlink, and back up destinations
that already exist. Binary installation is currently held, so these files are
published for source review and manual development use only. No diagnostic
pstore, network logging, touch probes, or development boot entries are
included.

The sensor units do not include their external configuration tree or either
userspace binary. `scripts/install-sensors.sh` accepts those locally built and
operator-supplied inputs for bounded developer testing.
