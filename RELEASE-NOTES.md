# Experimental source preview

This repository is a source-only preview for experienced Surface Pro 11 owners
and Linux hardware-enablement developers. It publishes the reviewed kernel
history, cumulative patches, configuration, userspace changes, provenance, and
build instructions behind the current proof of concept.

There is no downloadable kernel, module payload, installer image, or ISO in
this preview. Binary and ISO publication remains blocked by
`BINARY-RELEASE-HOLD.md` until exact corresponding source, licenses, archive
checks, and installation/rollback validation are complete.

## Reviewed kernel source

- Kernel release currently used for hardware validation:
  `7.1.3-sp11-camera-review5`
- Hardware-validated source commit:
  `86fc94c58a89a56c7ceb57b42c6025b2569da56d`
- Hardware-validated source tree:
  `4624d85595964242c26d7042106d068cbbdd9977`
- Next source candidate: `7.1.3-sp11-camera-review7`
- Candidate source commit: `2651afaca79b7e0e3a31d70eb21a6a000e172cf1`
- Candidate source tree: `2b70e7f701f7906db855ad27e527fc8fff891870`
- Base: Linux stable `v7.1.3` plus the attributed SP11/HID-over-SPI branch

The reviewed branch supports sequential capture from the front IMX681, rear
OV13858, and IR VD55G0 cameras on the tested OLED/X Elite Surface Pro 11. It
also enables the independently tested PM8550 IR illuminator and fixes automatic
loading of the touch/pen SPI transport. The bounded IR bridge source and its
independent illuminator-off helper are included; Howdy itself, the
v4l2loopback binary, enrolled face model, and test captures are not.

Review6 added a focused delayed controller posture re-query after resume. It
passed attached and detached suspend/resume tests, but a later Flex Keyboard
reattach recreated its HID devices without delivering the separate cover-state
notification. The cached detached posture suppressed the attached touchpad.

Review7 also observes the KIP connection event and schedules the same delayed,
controller-backed posture query. A manual query reproduced this exact recovery
without synthesizing an input state. Hardware qualification is pending, so
review5 remains the persistent fallback.

## Other validated hardware

- Touch, multitouch, pen hover/strokes, and eraser through iptsd
- Wi-Fi and Bluetooth
- Speakers, microphones, and volume rocker
- Attached keyboard, detached Bluetooth Flex Keyboard, and haptic touchpad
- Short power-button press suspends and wakes normally on a second press
- SAM fan telemetry and conservative power profiles
- Usable s2idle with deeper CPU idle disabled for stability

## Important limitations

- Tested on one Surface Pro 11 OLED/X Elite unit only
- Concurrent cameras, repeated switching, and camera suspend/resume remain
  incomplete
- Camera color processing and application integration remain experimental
- The CPU-idle mitigation increases idle power
- No clean-room installer or binary payload is currently offered
- The source is not represented as upstream-ready

The former Practical8 source and binary artifacts are withdrawn and are not
part of this repository's public object graph. See the provenance and camera
review documents for the replacement history and source boundaries.
