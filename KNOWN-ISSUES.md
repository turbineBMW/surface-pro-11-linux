# Known issues and sharp edges

This list is part of the release contract. The alpha is useful, but it is not
finished.

## Cameras are experimental

The reviewed camera branch captured changing frames from the front IMX681,
rear OV13858, and IR VD55G0 sequentially on one OLED/X Elite unit. Concurrent
camera use, repeated switching, camera suspend/resume, color processing, and
normal desktop application integration are not qualified.

The PM8550 IR illuminator was tested only in bounded sessions with an
independent systemd fail-safe. The local Howdy bridge, enrolled model, test
captures, and separately built v4l2loopback module are not included here. Do
not leave an IR emitter active without an independent timeout and stop path.

Results from the withdrawn Practical8 line do not qualify any source or binary
outside the reviewed `sp11-camera-review` branch.

## Suspend and idle power

Suspend/resume is usable s2idle and has repeatedly preserved touch, pen, and
Bluetooth. Stability currently depends on disabling PSCI CPU idle state1 on all
12 CPUs with `sp11-noidle.service`. The CPUs can still use WFI and scale down,
but idle energy use will be higher than the hardware should ultimately achieve.

Do not remove this mitigation merely to improve a benchmark. The unresolved
deep-idle path previously caused display/NoC wedges and failed resume.

## Power profiles

The SAM/EC platform-profile path is real, but a short CPU workload showed no
meaningful difference between firmware profiles. The alpha therefore adds a
reversible userspace companion:

- power-saver: maximum 2,515,200 kHz on all three SCMI cpufreq domains;
- balanced/performance: restore 3,417,600 kHz.

This is a practical field-test cap, not a tuned energy model. Battery drain,
sustained thermals, and the disabled higher boost point remain future work.

## Power button

A short press of the tablet power button currently requests immediate orderly
shutdown. This is desktop policy, not a hardware failure, but it is easy to hit
accidentally. Change the login/session policy or avoid the button until the
project provides a qualified default.

## Audio

Speakers and microphones work. Speaker volume is conservative; no software
boost is included.

## Flex Keyboard

The attached keyboard works. Detached Flex Keyboard Bluetooth mode has not been
implemented.

## Boot warnings and probe order

The boot log contains known probe/dependency warnings, including a Surface HID
instance that can fail probe with `-71` while the required input devices still
bind. Cleanup is deferred until the working hardware paths are preserved in a
more maintainable patch series.
