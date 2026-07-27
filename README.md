# Experimental Linux support for the Surface Pro 11

> This is an experimental, works-on-one-machine hardware-enablement project.
> It is intended for developers and experienced Surface Pro 11 owners who can
> build a kernel, recover an unbootable system, and keep a known-good boot
> entry. It is not a distribution, supported product, or finished installer.

This repository publishes the reviewed source used to run Linux on a Microsoft
Surface Pro 11 OLED with Snapdragon X Elite. The current reviewed source
has working audio, microphones, front and rear RGB cameras, an IR camera and
illuminator, touch, pen input through iptsd, volume buttons, an ambient color
sensor, conservative power profiles, USB runtime power management, and
suspend with guarded firmware-managed CPU idle.

No prebuilt kernel, module archive, firmware, disk image, ISO, biometric model,
or camera capture is distributed here. See
[BINARY-RELEASE-HOLD.md](BINARY-RELEASE-HOLD.md). The long-term goal is an
installable image comparable to the project that bootstrapped this work, but
that is a later milestone with separate source-compliance and safety gates.

## Foundation and credit

The installation foundation is
[dwhinham/linux-surface-pro-11](https://github.com/dwhinham/linux-surface-pro-11),
which provides the original Arch Linux ARM bootstrap, firmware workflow, and
early SP11 enablement. This repository is an experimental enhancement layer,
not a replacement for that project.

The kernel work also incorporates or adapts attributed GPL-licensed work from
Linux kernel contributors, Dale Whinham, Bryan O'Donoghue and Linaro,
Qualcomm, and STMicroelectronics. Original commit authorship, SPDX identifiers,
copyright notices, exact source revisions, and the detailed research boundary
are preserved in [NOTICE.md](NOTICE.md),
[docs/PROVENANCE.md](docs/PROVENANCE.md), and
[docs/CAMERA-REVIEW.md](docs/CAMERA-REVIEW.md).
The unrelated public-repository root and final object-graph checks are recorded
in [docs/PUBLICATION.md](docs/PUBLICATION.md).

AI tools materially assisted development, cleanup, and validation. The scope
and limits of that assistance are disclosed in
[docs/AI-ASSISTANCE.md](docs/AI-ASSISTANCE.md).

## Licensing

This repository is an aggregate. The top-level MIT license applies to original
project integration scripts and documentation; it does not relicense Linux,
libcamera, Power Profiles Daemon, iptsd, or other imported and modified work.
Kernel artifacts retain their compatible GPL-2.0 and per-file licenses,
libcamera changes retain LGPL/CC0 terms, and the PPD patch retains GPL-3.0.
See [docs/LICENSING.md](docs/LICENSING.md) and the file-level REUSE metadata.

## Tested target

- Product: Microsoft Surface Pro, 11th Edition
- Device-tree compatible: `microsoft,denali`
- SoC/display: Snapdragon X Elite / X1E80100 / OLED
- Boot environment: UEFI and GRUB on the Arch Linux ARM foundation
- Reviewed kernel source: `7.1.3-sp11-suspend-review20`
- Exact source commit: `18d7951a10dc49e383d16c6af82fc2c07784de3d`
- Exact source tree: `b820f10abba096e23a28506d7ad591dffdedf1a8`
- Preserved safe source: `7.1.3-sp11-camera-review12` at
  `a3e71f7080ee40dccfdd9500b8957a7c143fb6a2`

Only one physical OLED/X Elite unit has been qualified. Do not assume that the
LCD, X Plus, 5G, or other Surface variants use an interchangeable device tree.
See [SUPPORTED-HARDWARE.md](SUPPORTED-HARDWARE.md).

## Current status

Validated on the tested unit:

- OLED display, Wi-Fi, Bluetooth, attached keyboard, detached Flex Keyboard,
  and haptic touchpad
- Laptop, detached, and folded-back posture transitions, including
  keyboard and touchpad suppression while folded behind the tablet
- Touch, multitouch, pen hover/strokes, and eraser through iptsd
- Speakers, microphones, volume rocker, SAM fan telemetry, and qualified
  three-tier power profiles
- Verified 75–80% battery charge window, reapplied at boot and after resume
- TCS3430 ambient color sensor through Qualcomm SSC and iio-sensor-proxy
- Short, repeated, ten-minute, and overnight suspend/resume tests
- Front IMX681, rear OV13858, and IR VD55G0 capture, including repeated
  front/rear switching
- PM8550 IR illuminator and a bounded local Howdy proof of concept
- Guarded firmware-managed CPU idle during runtime, disabled across suspend
- USB runtime power management with repeated dock/thumb-drive hotplug

Still experimental:

- Concurrent camera capture
- Camera color processing, tuning, and normal desktop application integration
- Firmware-limited suspend efficiency; the overnight test drew about 1.7–1.8 W
- Other SP11 variants and distributions
- The beta installer, binary payload, and ISO are still under release hold

Read [KNOWN-ISSUES.md](KNOWN-ISSUES.md) before testing. Lid-triggered suspend
diagnosis and the opt-in logind watchdog workaround are documented in
[docs/SUSPEND.md](docs/SUSPEND.md).

## Repository contents

- `kernel/`: incremental Git bundles, cumulative patches, config, build
  identity, and the camera config fragment
- `userspace/`: pinned iptsd identity, optional libcamera/Power Profiles
  Daemon source changes, and battery charge-limit tests
- `rootfs/`: reviewed services, udev rules, helpers, and tuning data
- `scripts/`: source build, static audit, and currently held binary tooling
- `docs/`: build, provenance, validation, limitations, and recovery records

Start with [docs/BUILD.md](docs/BUILD.md) and [kernel/README.md](kernel/README.md).
Flex Keyboard Bluetooth identity setup is documented in
[docs/BLUETOOTH.md](docs/BLUETOOTH.md).
The ambient color sensor architecture, private configuration prerequisite, and
developer installation are documented in [docs/SENSORS.md](docs/SENSORS.md).
The source is shared so other developers can reproduce, review, test, and
improve it; publication does not imply upstream readiness. Before sharing logs
or patches, read [CONTRIBUTING.md](CONTRIBUTING.md) for the privacy and
provenance boundary.

## Firmware and Windows boundary

Firmware remains an external prerequisite handled by the foundation project's
workflow and is not redistributed here. The reviewed source contains no
Windows driver package, proprietary firmware copied from Windows, raw WinDbg
trace, memory dump, private capture, credential, or enrolled biometric data.
The independently observed touch/QSPI and camera boundaries are documented in
[docs/TOUCH-QSPI-PROVENANCE.md](docs/TOUCH-QSPI-PROVENANCE.md) and
[docs/CAMERA-REVIEW.md](docs/CAMERA-REVIEW.md).

## Recovery first

Before trying any build:

1. Keep the known-good foundation kernel and its GRUB entry.
2. Keep recovery media available.
3. Verify that you can restore the boot files from another environment.
4. Never make an experimental kernel the only bootable entry.

Microsoft and Surface are names used only to identify compatible hardware.
This independent project is not affiliated with or endorsed by Microsoft,
Qualcomm, Linaro, STMicroelectronics, or the Linux kernel project.
