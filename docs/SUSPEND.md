# Guarded runtime idle, lid suspend, and the logind watchdog

> **2026-09-05:** the beta now ships the Linux 7.3 port kernel
> (`7.2.0-sp11-73beta1`), on which deep CPU idle is unrestricted and the
> guard described in the first section does not exist. The runtime-idle
> policy below applies only to the review20 kernel of the 2026-08-28 beta.
> The logind watchdog section still applies to both. Suspend diagnostics for
> the shipped kernel: `sp11-suspend-report` (see `docs/SENSORS.md` for the
> ambient-light stream that used to break suspend).

## Qualified review20 policy (2026-08-28 beta kernel only)

The beta release candidate opts into runtime PSCI state1 with
`sp11_deep_idle=1` because it materially reduces screen-on idle power. The
kernel-side Denali block remains the default when that parameter is absent.

Runtime state1 is not safe across suspend entry by itself. After more than
3.8 million runtime entries, an unguarded ten-minute test wedged while entering
suspend and required a forced reboot. The rootfs therefore installs:

```text
/usr/local/libexec/sp11-runtime-idle-suspend-guard
/etc/systemd/system/systemd-suspend.service.d/10-sp11-runtime-idle-guard.conf
```

Before `systemd-sleep` enters the kernel, the guard disables state1 on all
12 CPUs, schedules work on every CPU to force outstanding residency to exit,
and requires the aggregate state1 usage count to remain exactly flat for two
seconds. Any failed write, missing CPU, or continuing entry causes
`ExecStartPre` to fail and prevents suspend. After a successful resume,
`ExecStartPost` restores state1 on all 12 CPUs.

The guarded policy passed five short cycles, 7- and 15-minute endurance
cycles, more runtime-state1 exposure than the rejected configuration, and a
7 h 48 m overnight lid-triggered suspend. The overnight APSS residency was
99.986%, the lid woke the system, and all tested hardware worked afterward.

The deeper platform states still do not engage. The overnight cycle consumed
1.70--1.81 W and lost 29 displayed battery percentage points. Users should
expect approximately 3.7 percentage points of suspend drain per hour and
should not treat suspend as multi-day storage.

## Scope

The logind configuration below addresses a separate failure reproduced on the
tested Surface Pro 11 OLED/X Elite unit with systemd 261. It is included in
the beta rootfs baseline because all long guarded review20 qualification,
including the overnight lid cycle, used it.

The failure is specific to the lid-triggered path observed on this machine. A
direct `systemctl suspend` cycle remained in genuine suspend-to-idle for about
62 minutes without restarting logind. A lid-triggered cycle instead remained
asleep for about 3 minutes 52 seconds, then systemd reported the vendor
three-minute `systemd-logind.service` watchdog timeout during resume. Logind
was terminated and restarted, the compositor lost its existing session/DRM
device authorization, and the result appeared to be a hard resume lock.

No kernel panic, oops, or persistent-storage crash record accompanied the
failure. This workaround does not change the kernel sleep state, deepen
suspend, or modify lid-switch policy.

## Installed workaround

The rootfs installs:

```ini
# /etc/systemd/system/systemd-logind.service.d/10-sp11-suspend-watchdog.conf
[Service]
WatchdogSec=0
```

After installation, reload unit metadata and reboot:

```sh
sudo systemctl daemon-reload
sudo reboot
```

Do not restart logind from inside the active graphical session to activate the
change. During testing, doing so invalidated the compositor's existing DRM file
descriptors and required restarting the compositor. A normal reboot activates
the drop-in without that disruption.

After reboot, verify the effective value:

```sh
systemctl show systemd-logind.service \
  -p WatchdogUSec -p MainPID -p NRestarts -p ActiveState
```

`WatchdogUSec=0` confirms that the service watchdog is disabled.

## Validation on the tested unit

Two lid-triggered cycles passed beyond the former three-minute failure boundary
with the drop-in active:

- 250.75 seconds in suspend-to-idle before wake;
- 259.90 seconds in suspend-to-idle after a fresh reboot.

Opening the lid woke the machine in both tests without a power-button press.
Logind retained its PID, reported zero restarts, and produced no watchdog or
failed session-device restoration message. The first test passed physical
checks of the touchpad, touchscreen, pen, Wi-Fi, detached Bluetooth Flex
Keyboard, speakers, microphones, and cameras.

## Tradeoff

The watchdog normally detects a logind process that remains alive but stops
servicing its event loop. With `WatchdogSec=0`, systemd will not automatically
abort and restart logind for that type of hang. The vendor `Restart=always`
setting remains intact and still restarts logind after an ordinary process
exit or crash. No kernel, hardware, systemd-manager, or other service watchdog
is disabled.

Keep this workaround in the narrowly targeted beta baseline until the lid path
receives a narrower fix or the exact packaged system passes equivalent long
lid-suspend qualification without it.

## Review8 tablet-mode resynchronization

A separate lid-resume symptom can leave the Surface Aggregator tablet-mode
input switch at its early resume value after the embedded controller posture
has settled. If that stale value is tablet mode, libinput can suppress the
attached keyboard and touchpad even though their devices are present.

Review6 kept the driver's immediate resume query and added one controller
re-query after two seconds. It uses the existing serialized update path and
emits an input change only if the controller reports a different posture. This
is deliberately narrower than synthesizing `SW_TABLET_MODE=0` from userspace.
The combination “lid open + tablet mode” is legitimate when the Flex Keyboard
is detached or folded back, so that combination alone is not proof of a fault.

Attached and detached suspend/resume tests passed on review6. A subsequent Flex
Keyboard reattach recreated the keyboard and touchpad endpoints while the
tablet-mode switch remained cached as `disconnected`. Rebinding only the switch
driver made it query the controller, report `laptop`, and immediately restore
one-finger touchpad motion. No input state was synthesized.

Review7 therefore also observed the KIP connection event (`0x2c`) and
scheduled the same delayed controller query. Its first physical qualification
returned raw KIP state zero, outside the valid 1..6 posture range, and left
tablet mode asserted.

Review8 rejects out-of-range posture values and retries every two seconds for
a bounded 30-second settling window after a connection change. It stops the
sequence when the controller returns a valid posture. The final live module
passed repeated physical detach/reattach cycles without rebinding or synthetic
input. The exact full kernel then passed five consecutive physical reattach
cycles, attached lid-triggered s2idle, and detached power-button s2idle. The
attached and Bluetooth touchpads, both keyboard paths, touchscreen, pen, Wi-Fi,
Bluetooth, audio, microphones, and all three cameras remained healthy after the
sequence. With the attached keyboard folded completely behind the tablet,
keyboard and touchpad input were suppressed; returning it to typing position
restored both. Review9 retains this qualified source unchanged, and review8 is
installed as its rollback kernel.

The read-only diagnostic can record both the controller state and live evdev
switch state without injecting input, rebinding a driver, or changing policy:

```sh
sudo ./scripts/diagnose-tablet-mode.py --samples 6 --interval 1
```

Run it after a suspect resume before detaching or reattaching the keyboard.
Interpret the result in the context of the physical keyboard posture; the tool
intentionally does not label any state combination as invalid.

## Separate attached-touchpad resume fault

One post-reboot lid cycle left the attached touchpad with an apparent stale
contact: one-finger motion did nothing, two fingers moved the pointer, and
clickfinger behavior was offset by one contact. Raw input capture isolated the
bad reports to the attached Surface Aggregator HID path; the Bluetooth path was
clean. Detaching and reattaching the Flex Keyboard recreated the attached HID
endpoints and restored normal behavior.

That fault is independent of the logind watchdog workaround. A targeted
software rebind of the touchpad endpoint remains unqualified and is not
included here.

## Rollback

Remove only the drop-in and reboot:

```sh
sudo rm /etc/systemd/system/systemd-logind.service.d/10-sp11-suspend-watchdog.conf
sudo systemctl daemon-reload
sudo reboot
```

After reboot, `systemctl show systemd-logind.service -p WatchdogUSec` should
again report the vendor watchdog interval.
