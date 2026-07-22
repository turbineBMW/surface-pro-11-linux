# Experimental root filesystem overlay

This allowlisted tree contains only the integrations required by the qualified
machine:

- Bluetooth EFI-address setup service/helper
- deep-idle stability mitigation
- dynamic iptsd udev/service/sleep lifecycle
- Surface platform-profile module loading and patched PPD selection
- measurable power-saver cpufreq companion and sleep hook target
- short power-button press mapped to suspend through logind
- CC0 IMX681 simple-pipeline tuning data

The future installer is intended to copy regular files with their repository
modes, create the power-profile system-sleep symlink, and back up destinations
that already exist. Binary installation is currently held, so these files are
published for source review and manual development use only. No diagnostic
pstore, network logging, touch probes, or development boot entries are
included.
