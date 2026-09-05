# Known issues and sharp edges

## Beta ISO and installer (2026-09-05)

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
- **Only one hardware unit** has been used for qualification. The
  2026-08-28 beta was cold-booted on it from a USB 2.0 stick: GRUB firmware
  injection, validation, RAM copy, GNOME, Wi-Fi, Bluetooth, touch, pen,
  cameras, microphones, speakers, and GPU acceleration all worked with
  zero failed units. The 2026-09-05 image swaps the kernel for the Linux 7.3
  port that the same unit has run as its installed daily system since
  2026-08-28; the live image itself was rebuilt with the same package
  snapshot and has not been re-qualified from USB separately.
- **The screen goes black for one to two minutes** after the first boot
  messages while the live root is copied into RAM (107 s on a USB 2.0
  stick; faster on USB 3). That is normal; wait for GNOME.
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

The front camera's manual exposure control was inert until 2026-09-05 (the
driver wrote a register the IMX681 ignores); the shipped kernel writes the
right one (`kernel/sp11-imx681-exposure.patch`, Leon Silcott's correction), so
exposure now actually changes brightness. Automatic exposure tuning in
libcamera is separate and still rough.

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

## Half-screen colour tint after resume or screen off/on

Fixed in the shipped 7.3 port kernel since the 2026-09-05 beta (it was
"source only" in the 2026-08-28 beta's review20 kernel). With a gamma LUT
applied by the compositor (night-light tools such as wlsunset), every suspend/resume or DPMS
off/on left one half of the panel with a random colour tint and artifacts.
Root cause is in the upstream DPU driver: the gamma LUT SRAM is written during
the modeset before the block is active, and the write is lost. The fix is
`kernel/sp11-dpu-gc-lut-after-modeset.patch`; see `kernel/README.md`. Until a
build with it ships, changing the gamma (toggling or restarting the night-light
tool) clears the corruption immediately.

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

The shipped kernel (`7.2.0-sp11-73beta1`, the Linux 7.3 port) runs deep CPU
idle unrestricted: upstream 7.3 merged the PDC and idle-state work the review20
series carried, the review20 guards were dropped, idle draw fell by about
3.7 W, deep suspend measured 0.535 W over a 7 h overnight cycle (roughly 90 h
of standby instead of one day), and the maintainer's unit has run it daily
with dozens of suspend/resume cycles since 2026-08-28. If you suspect idle
states, the live menu's "CPU idle states off" entry (`cpuidle.off=1`) is the
conservative fallback. One hard freeze with automatic reboot happened on
2026-09-01 during a package upgrade and left no trace; this build therefore
loads `efi-pstore` as a module (the built-in backend never registered on this
firmware) and panics on hard lockups so the next one is captured.

The 2026-08-28 beta's review20 kernel used PSCI `SYSTEM_SUSPEND` with runtime
PSCI state1 behind a fail-closed suspend guard (`sp11_deep_idle=1`) and a
`sp11-noidle.service` block by default, because an unguarded configuration
had wedged while entering suspend. Those units remain in `rootfs/` for that
kernel; see `docs/SUSPEND.md`.

Ambient light sensor stream (fixed 2026-08-30): with the sensor stack installed,
a light claim (any `monitor-sensor --light` or desktop auto-brightness client)
starts an ADSP sensor stream that iio-sensor-proxy never disables; its
indications woke the SoC 0.2–0.8 s into every deep suspend, so a closed lid
cycled suspend every 30 s and eventually hung. `sp11-sensors-sleep` stops
iio-sensor-proxy across sleep. Diagnose future cases with `sp11-suspend-report`
(a short `slept_s` with IRQ 16 `smp2p-adsp` ticking is this signature). See
docs/SENSORS.md.

On the review20 kernel suspend power was poor: during its overnight cycle
APSS was suspended for 99.986% of the wall interval, but AOSS, CXSD, and
DDR-collapse counters stayed at zero and the battery drained 1.70--1.81 W
(roughly one day of standby). The 7.3 port kernel reaches 0.535 W.

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

If `iio-sensor-proxy.service` is masked on the host (`systemctl is-enabled`
prints `masked`), automatic brightness silently never starts even though
`sp11-sensors.service` is healthy; `scripts/install-sensors.sh` now unmasks it,
and an existing installation can be fixed with `systemctl unmask
iio-sensor-proxy.service`.

An empty `color_calibration.bin` crashes the Qualcomm sensor process; leave the
file absent when no valid record exists. Validate every installation after a
full host boot. Manually restarting the shared ADSP can incur long
firmware-client timeouts or trigger automatic ADSP recovery, so it is not a
substitute for that reboot test. See
[docs/SENSORS.md](docs/SENSORS.md).

## Flex Keyboard

Attached and detached Flex Keyboard modes work on the tested unit. Detached
mode pairs natively on Linux over the wired connector, with no Windows keys
(`sudo sp11-flex-pair`); this needs the two kernel patches in
`kernel/sp11-flex-bt-oob-pairing.patch` (KIP HID instance 9 registration, and
LE legacy out-of-band pairing support), which are part of the 7.3 port. A
udev-triggered service reconnects the keyboard on every detach. No
machine-specific address or Bluetooth key is distributed here.

**Haptics after poweroff.** With the keyboard attached, its touchpad can keep
clicking after a *battery-powered* poweroff; AC poweroff and suspend always
quiesce it. The kernel now issues the suspend report-disable sequence at
shutdown too (`kernel/sp11-surface-hid-shutdown.patch`), and captures show
the commands succeed in failing runs as well, so the cause is on the EC/pogo
power hand-off side and is still open. Detach the keyboard, or use suspend,
if it bothers you. An opt-in Bluetooth-blocking guard exists but was not
shown to help reliably; see `docs/BLUETOOTH.md`. Do not leave the keyboard
`Blocked` in BlueZ while attached: the kernel keeps auto-connecting it and the
keyboard reboots every ~12 s.

Two caveats. The Bluetooth adapter identity is *not* the
`MacAddressEmulationAddress` EFI value -- that is the Wi-Fi MAC, and on the
tested unit Bluetooth is one lower. And on a dual-boot machine Windows re-pairs
the keyboard on its own schedule, invalidating the Linux bond; pairing again
resolves it. See [docs/BLUETOOTH.md](docs/BLUETOOTH.md).

## Slim Pen 2 buttons

The tail button only works over Bluetooth. `sp11-pen-pair` bonds the pen as a
plain BLE HID device and the button arrives as Meta+F19/F20 on a keyboard
node. The pen never advertises on its own, so after it has been docked it must
be woken with a ~7 s tail-button hold before the bond reconnects; there is no
automatic pickup, and the Windows-style loosely-coupled provisioning that
would give one is not implemented. See [docs/BLUETOOTH.md](docs/BLUETOOTH.md).

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
