# Experimental source preview

This repository is a source-only preview for experienced Surface Pro 11 owners
and Linux hardware-enablement developers. It publishes the reviewed kernel
history, cumulative patches, configuration, userspace changes, provenance, and
build instructions behind the current proof of concept.

There is no downloadable kernel, module payload, installer image, or ISO in
this preview. Binary and ISO publication remains blocked by
`BINARY-RELEASE-HOLD.md` until exact corresponding source, licenses, archive
checks, and installation/rollback validation are complete.

## Reviewed camera source

- Kernel release used for hardware validation:
  `7.1.3-sp11-camera-review4`
- Source commit:
  `675d89b381d8b730a3f2eff1086875481ee5b515`
- Source tree:
  `03c278405e6d2fd0ffa1fd4cad860ef45c7adbbc`
- Base: Linux stable `v7.1.3` plus the attributed SP11/HID-over-SPI branch

The reviewed branch supports sequential capture from the front IMX681, rear
OV13858, and IR VD55G0 cameras on the tested OLED/X Elite Surface Pro 11. It
also enables the independently tested PM8550 IR illuminator. A local Howdy
proof of concept succeeded, but the bridge, v4l2loopback binary, enrolled face
model, and test captures are not distributed in this source preview.

## Other validated hardware

- Touch, multitouch, pen hover/strokes, and eraser through iptsd
- Wi-Fi and Bluetooth
- Speakers, microphones, and volume rocker
- Attached keyboard and haptic touchpad
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
