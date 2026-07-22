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
- Next source candidate: `7.1.3-sp11-camera-review8`
- Candidate source commit: `940bbc856a120e6f967f9dbaf825d5473bfae664`
- Candidate source tree: `62edee5183ed3b42ee3a2f9f0c71066c3ab87742`
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

Review7 also observed the KIP connection event, but its single delayed query
could receive transient raw state zero and leave tablet mode asserted. Review8
rejects values outside the valid posture range and retries for a bounded
30-second settling window, stopping on the first valid controller response.
The review8 live module passed repeated detach/reattach testing; exact clean
builds are byte-identical and exact full-kernel qualification is pending, so
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
