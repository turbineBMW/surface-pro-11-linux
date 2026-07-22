# Known issues and sharp edges

This list is part of the release contract. The alpha is useful, but it is not
finished.

## Cameras are experimental

The reviewed camera branch captured changing frames from the front IMX681,
rear OV13858, and IR VD55G0 sequentially on one OLED/X Elite unit. Concurrent
camera use, repeated switching, camera suspend/resume, color processing, and
normal desktop application integration are not qualified.

Rapid camera switching can lock the camera path. Repeated sequential switching
has remained stable when each transition is separated by at least 10 seconds,
but that observation is not an endurance guarantee. Keep at least that gap
until the asynchronous teardown/reinitialization race is characterized.

The PM8550 IR illuminator was tested only in bounded sessions with an
independent systemd fail-safe. The reviewed bounded bridge and separate
illuminator-off helper are included, but Howdy itself, an enrolled model, test
captures, and the separately built v4l2loopback module are not. Do not leave an
IR emitter active without an independent timeout and stop path.

Results from the withdrawn Practical8 line do not qualify any source or binary
outside the reviewed `sp11-camera-review` branch.

## Suspend and idle power

Suspend/resume is usable s2idle and has repeatedly preserved touch, pen, and
Bluetooth. Stability currently depends on disabling PSCI CPU idle state1 on all
12 CPUs with `sp11-noidle.service`. The CPUs can still use WFI and scale down,
but idle energy use will be higher than the hardware should ultimately achieve.

Do not remove this mitigation merely to improve a benchmark. The unresolved
deep-idle path previously caused display/NoC wedges and failed resume.

On the tested systemd 261 host, a lid-triggered suspend longer than three
minutes can make logind's own service watchdog terminate it during resume. The
result can look like a hard lock after the compositor loses its session-device
authorization. An explicitly opt-in, host-tested workaround and its tradeoff
are documented in [docs/SUSPEND.md](docs/SUSPEND.md); it is not installed by
the project rootfs.

Separately, the attached Flex Keyboard touchpad has once resumed with contact
counting offset by one finger. Detaching and reattaching the keyboard restored
normal operation. An automatic software reset remains unqualified.

## Power profiles

The SAM/EC platform-profile path is real, but a short CPU workload showed no
meaningful difference between firmware profiles. The alpha therefore adds a
reversible userspace companion:

- power-saver: maximum 2,515,200 kHz on all three SCMI cpufreq domains;
- balanced/performance: restore 3,417,600 kHz.

This is a practical field-test cap, not a tuned energy model. Battery drain,
sustained thermals, and the disabled higher boost point remain future work.

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
