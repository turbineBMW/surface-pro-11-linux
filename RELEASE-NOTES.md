# Review20 beta consolidation

This branch prepares the exact, hardware-qualified review20 stack for a beta
ISO. Binary and ISO publication remains blocked by
`BINARY-RELEASE-HOLD.md` until clean reconstruction, archive review, and
install/rollback tests are complete.

## Qualified kernel

- Linux release: `7.1.3-sp11-suspend-review20`
- Source commit: `18d7951a10dc49e383d16c6af82fc2c07784de3d`
- Source tree: `b820f10abba096e23a28506d7ad591dffdedf1a8`
- Kernel Image SHA-256:
  `b3ca9ba56570ff1bf8217a866563f1e9788c5dfdc3a153a9b673e3b6e9624ed5`
- OLED DTB SHA-256:
  `5e9009f5bd96a760a33086d1a8842e3228e3d28c413f96d70aca4914f7e397ed`
- Preserved safe entry: `7.1.3-sp11-camera-review12`
- Review12 source commit:
  `a3e71f7080ee40dccfdd9500b8957a7c143fb6a2`

The cumulative review20 patch series and incremental Git bundle are included
under `kernel/`. See `docs/REVIEW20-CONSOLIDATION.md` for provenance,
qualification evidence, and remaining release gates.

## Validated on the tested OLED/X Elite unit

- OLED display, touchscreen, pen, attached keyboard, detached Flex Keyboard,
  haptic touchpad, Wi-Fi, and Bluetooth
- Speakers, microphones, volume controls, and three bounded power profiles
- Front, rear, and IR cameras, including repeated front/rear switching
- Battery charge-limit restore, ambient color sensor, fan telemetry, and
  DisplayPort DDC
- USB runtime power management with repeated dock/thumb-drive hotplug
- Guarded firmware-managed CPU idle during normal runtime
- Short and repeated suspend/resume, a ten-minute suspend, and a 7-hour
  48-minute overnight suspend with all checked hardware functional afterward

The runtime-idle suspend guard disables state1 before suspend and restores it
after resume only when the explicit `sp11_deep_idle=1` opt-in is present.

## Important limitations

- Qualified on one physical Surface Pro 11 OLED/X Elite unit only
- Suspend draw remains approximately 1.7–1.8 W in the overnight test; this
  permits more than 24 hours from a full battery but is not an ideal deepest
  platform sleep
- Unguarded state1 is not supported, and the firmware boundary remains under
  investigation
- Firmware is an external prerequisite and is not redistributed
- Other Surface Pro 11 variants, distributions, and boot loaders are not yet
  qualified
- Camera color tuning and ordinary desktop camera integration remain
  experimental

## Dual boot

The GRUB Windows chainloader entry works. A long blank delay before Windows
starts is expected when Windows USB/kernel debugging is enabled; that delay was
previously mistaken for a broken GRUB entry.
