# Known issues and sharp edges

## Beta ISO and installer (2026-08-28)

- **Secure Boot must be off.** The live image and the installed GRUB are not
  signed. The installer does not touch Microsoft's keys.
- **No firmware, no sound/GPU.** Until the five owner files are on `SP11FW`
  (or installed with `sp11-firmware`), audio, microphones, the ambient
  sensor, and GPU acceleration are unavailable and Mesa logs
  `get_param failed`. `sp11-firmware status` tells you which case you are in.
- **BitLocker.** The Linux-side collector cannot read a BitLocker volume;
  run `RUN-IN-WINDOWS.cmd` from Windows instead.
- **Windows Fast Startup / hibernation** leaves the NTFS volume dirty, so
  `sp11-firmware --from-windows` refuses to mount it. Shut Windows down
  fully (Shift + Shut down) or disable Fast Startup.
- **Only one hardware unit** has been used for qualification. The GRUB
  `newc:` firmware path was verified for syntax and the fallback paths
  match what booted in July/August 2026, but the beta ISO built on
  2026-08-28 has not yet been cold-booted on hardware by the maintainer;
  reports welcome.
- **Wipe mode** was exercised on loop devices, not on the maintainer's NVMe.
- **ISO size.** Release assets larger than 2 GiB are split; join them with
  `cat` before writing (see the release README).
- The live root is copied into RAM: 3 GB of RAM is used by the live system
  before applications start.

This list is part of the release contract. The beta is useful, but it is not
finished.

## Cameras are experimental

The reviewed camera branch captured changing frames from the front IMX681,
rear OV13858, and IR VD55G0 sequentially on one OLED/X Elite unit. Concurrent
camera use, repeated switching, camera suspend/resume, color processing, and
normal desktop application integration are not qualified.

Rapid camera switching previously locked the camera path, and review10 corrects
it. The rear OV13858's first SCCB transaction after power-up intermittently
returned `-EIO` behind a CCI queue timeout whenever another camera on the same
SoC had run shortly beforehand; it reproduced on 26% of rear opens across 120
measured opens on review9, and never when the rear camera was used alone.
Retrying that single idempotent software-reset write clears it. On review10 a
60-cycle front/rear soak with no gap between sessions records zero capture
failures, against 24 of 60 on review9 in a back-to-back control. The 10-second
gap previously recommended here is no longer required.

The underlying transient is corrected, not explained. The CCI queue timeout
still occurs and is still logged — on 38 of those 60 opens — but the driver now
recovers and every session returns its frames, at a cost of roughly 137 ms on an
affected open. Why the first transaction stalls when another camera in the same
power domain is powered is not established. Expect the timeout line in the
kernel log; it is no longer a failure.

The PM8550 IR illuminator was tested only in bounded sessions with an
independent systemd fail-safe. The reviewed bounded bridge and separate
illuminator-off helper are included, but Howdy itself, an enrolled model, test
captures, and the separately built v4l2loopback module are not. Do not leave an
IR emitter active without an independent timeout and stop path.

Results from the withdrawn Practical8 line do not qualify any source or binary
outside the reviewed `sp11-camera-review` branch.

## External display brightness

DDC/CI over DisplayPort works as of review12. Two upstream `drm/msm` defects
prevented it: an EDID-read workaround that corrupted every other I2C-over-AUX
target, and a connector that never advertised its DDC bus. Both are fixed.

`ddcutil` still cannot find the bus. It locates displays by walking up the
sysfs tree from an i2c adapter looking for a video adapter driver, and on this
SoC the AUX bus is a sibling of the DRM device rather than a descendant, so the
walk fails and every bus is rejected before any I/O is attempted. There is no
option to override this. The kernel publishes the standard
`/sys/class/drm/<connector>/ddc` link, which is what a fix would use.

Until that is resolved, the desktop brightness sliders in GNOME and KDE will
not work either, since they use ddcutil's library. Talking to the monitor
directly does work.

## GPU hang investigation

After approximately 16 hours and 49 minutes of extended use, the qualified
review20 host froze and then rebooted without an orderly shutdown. The
surviving journal contains no suspend attempt near the failure and no OOM,
thermal trip, active watchdog reset, kernel Oops, or remote-processor crash.
The host's development-only sysctl configuration intentionally panics after a
task remains blocked for 30 seconds and reboots 15 seconds later, which
explains the automatic reboot but not the original stall.

The exact review20 panic trace was not preserved because old EFI pstore
fragments had exhausted the firmware variable store. Those records have been
archived locally, pstore has been cleared, and approximately 94 KiB is
available for a future capture.

Historical pstore data from an older review9 boot contains repeated MSM/DPU
GPU hangchecks, Adreno GMU and HFI timeouts, and a blocked display commit that
ended in a hung-task panic. The recovery worker identified GPU work submitted
by Quickshell as the offending ring-buffer task. That does not prove Quickshell
caused the driver or firmware failure. The review20 journal also contains one
GMU fenced-register-write delay more than three hours before the later reset.
The MSM/Adreno GMU recovery path is therefore the leading hypothesis, not a
confirmed review20 root cause.

The panic-on-hung-task policy is host diagnostic instrumentation and is not
part of the public beta rootfs. The clean reproducible candidate needs extended
GPU observation during its one-shot hardware qualification.

## Suspend and idle power

The review20 release candidate uses PSCI `SYSTEM_SUSPEND` and enables runtime
PSCI state1 on all 12 CPUs. Runtime state1 reduced a matched detached
screen-on measurement by 1.47 W. An unguarded configuration later wedged while
entering suspend, so unguarded runtime state1 is rejected.

The qualified configuration installs a fail-closed suspend guard. It disables
state1 on all CPUs, forces outstanding residency to exit, and refuses suspend
unless the aggregate usage count remains flat for two seconds. It restores
state1 only after resume. This configuration passed repeated short cycles,
7- and 15-minute endurance cycles, and a 7 h 48 m overnight lid cycle. The
overnight cycle resumed from the lid with touchscreen, keyboard, touchpad,
audio, and both cameras working.

Do not enable `sp11_deep_idle=1` without the guard. A boot without that opt-in
retains the conservative `sp11-noidle.service` state1 block.

Suspend power remains poor. During the overnight cycle APSS was suspended for
99.986% of the wall interval, but AOSS, CXSD, and DDR-collapse counters stayed
at zero. Battery capacity fell from 80% to 51%, approximately 3.7 percentage
points per hour or 1.70--1.81 W. The same hardware-collapse failure is visible
under Windows. Expect roughly one day of standby, not multi-day standby, until
platform firmware permits the final collapse state.

On the tested systemd 261 host, a lid-triggered suspend longer than three
minutes can make logind's service watchdog terminate it during resume. The
result can look like a hard lock after the compositor loses its session-device
authorization. The reviewed rootfs carries the host-qualified
`WatchdogSec=0` drop-in used throughout the long review20 qualification. Its
tradeoff is documented in [docs/SUSPEND.md](docs/SUSPEND.md).

Separately, the attached Flex Keyboard touchpad has once resumed with contact
counting offset by one finger. Detaching and reattaching the keyboard restored
normal operation. An automatic software reset remains unqualified.

An earlier lid-resume path also left `SW_TABLET_MODE=1` while the lid reported
open, causing libinput to suppress the attached keyboard and touchpad. A
host-only state-specific healer corrected the tested machine, but that helper
has not completed public source review and is not included in this tree.

## Power profiles

The SAM/EC platform-profile path is real, but a short CPU workload showed no
meaningful difference between firmware profiles. The alpha therefore adds a
reversible, hardware-qualified userspace companion:

- power-saver: maximum 1,920,000 kHz on all three SCMI cpufreq domains;
- balanced: maximum 2,515,200 kHz;
- performance: restore 3,417,600 kHz.

Repeated battery-only fixed-work tests selected 1,920,000 over 1,670,400 kHz:
it completed both all-core and single-core work about 15.5% faster and used
less energy per completed job, while bounded idle draw was effectively tied.
This remains a practical field-test mapping, not a complete energy model.
Long-term battery drain, sustained thermals, and the disabled higher boost
point remain future work.

## Battery charge limit

The Qualcomm battery manager accepts a charge-control window, but the setting
is not persistent firmware configuration. It must be programmed again after
boot. The remote battery-manager service can also restart independently and
forget its active limit while an older kernel continues to show cached
threshold values.

The rootfs service therefore writes and verifies the configured window at boot
and after system sleep. The focused kernel correction additionally propagates
firmware write errors and restores the cached window after a remote service
reconnect. Review9 passed exact boot, sleep/resume, and 75–80% readback tests.
The retail firmware rejected a controlled charger protection-domain restart as
disabled before any state transition, so the kernel reconnect path could not
be forced without disrupting the shared audio and sensor DSP.

## Power button

The rootfs maps a short tablet power-button press to suspend instead of the
systemd default poweroff action. On the tested niri session, a second short
press woke the system normally after a genuine suspend-to-idle cycle. Desktop
software can take ownership of power-key handling and override logind policy;
other sessions remain unqualified.

The project does not change logind's long-press policy or the hardware's forced
power-off behavior.

## Audio

Speakers and microphones work. Speaker volume is conservative; no software
boost is included.

Those results require Surface-specific ADSP firmware. The five exact
owner-supplied DSP/GPU files are unowned, absent from upstream linux-firmware,
and denied from the published ISO. The topology itself is
reproducibly built from tracked BSD-3-Clause source and the UCM routing is
project-authored. The live image obtains the remaining files only from the
exact-hash FAT32 `SP11FW` partition on the owner's live USB. That partition
ships only with editable redistributable collector/diagnostic tools and
instructions; it does not publish or automatically download the firmware or
transmit diagnostics.

Qualcomm Windows driver 1.0.4374.1300 supplies an 88,780-byte Microsoft-signed
`bdwlan.elf`. It is not a compatible replacement for the qualified board
record: ath12k times out loading the BDF with `-110`. The working 88,872-byte
`board.bin` is instead extracted without modification from the
redistributable WCN7850 `board-2.bin` selected from the locked
`linux-firmware-atheros` package and is included in the live root.
The device-specific 88,792-byte DPP `WLAN_CLPC.PROVISION` ELF also timed out
with `-110`. Replacing only its ELF envelope with the qualified legacy layout
produced the same failure, so the incompatibility is in the DPP payload rather
than merely the newer ELF structure. Both DPP-derived hashes are rejected.

## Ambient color sensor

The sensor requires an external Microsoft/Qualcomm configuration tree,
hexagonrpcd registry-write support, and the SP11 libssc color-endpoint mapping.
None of the proprietary configuration, calibration, or generated registry is
distributed here.

An empty `color_calibration.bin` crashes the Qualcomm sensor process; leave the
file absent when no valid record exists. Validate every installation after a
full host boot. Manually restarting the shared ADSP can incur long
firmware-client timeouts or trigger automatic ADSP recovery, so it is not a
substitute for that reboot test. See
[docs/SENSORS.md](docs/SENSORS.md).

## Flex Keyboard

Attached and detached Flex Keyboard modes work on the tested unit. Detached
mode currently requires importing a bond created by Windows and using the same
local controller identity. Native Linux pairing has not been implemented, and
no machine-specific address or Bluetooth key is distributed here. See
[docs/BLUETOOTH.md](docs/BLUETOOTH.md).

## Boot warnings and probe order

The boot log contains known probe/dependency warnings, including a Surface HID
instance that can fail probe with `-71` while the required input devices still
bind. Cleanup is deferred until the working hardware paths are preserved in a
more maintainable patch series.

## Windows boot delay with debugging enabled

The GRUB `Windows Boot Manager` chainloader entry works on the tested
dual-boot system. That Windows installation has USB/kernel debugging enabled
and may show an unusually long blank transition before boot continues. The
delay was initially mistaken for a broken GRUB entry; waiting for Windows
confirmed that chainloading succeeds.

The installer must preserve the existing Windows firmware entry and EFI
loader. It must not disable or modify Windows debugging policy.
