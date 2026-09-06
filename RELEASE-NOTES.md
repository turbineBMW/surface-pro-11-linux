# Public beta 2 (2026-09-05)

Second beta ISO. The big change is the kernel: the image and the installer
now ship the Linux 7.3 forward port, `7.2.0-sp11-73beta1`, which the
maintainer's tablet has run as its daily system since 2026-08-28, built
reproducibly with `scripts/build-kernel.sh --profile port-7.3`
(`kernel/port-7.3/BUILDINFO`). The 2026-08-28 beta's `7.1.3-sp11-suspend-review20`
kernel stays published and buildable as the `review20` profile. Everything
below except the first three items was already on `main` as source; this is
the first image that contains it.

Image: `sp11-linux-beta-20260905-aarch64.iso`, SHA-256
`594b9b96843ce9cebcc9a3687e0c443db6db3563eb5b47c1dac480b98a627e4b`
(2,161,037,312 bytes; the release carries it split in two parts for
GitHub's 2 GiB asset limit, join them with `cat` as the release README
says). Windows USB creator: `sp11-usb-creator-windows-20260905.zip`.
Build inputs and the per-stage identities are in `docs/BUILD-ISO.md`,
`kernel/port-7.3/BUILDINFO` and the release's `BUILD-ARTIFACTS.tsv`.

- **Front-camera exposure works** (`kernel/sp11-imx681-exposure.patch`, Leon
  Silcott's correction): the IMX681 driver wrote a 16-bit exposure register
  the sensor ignores; it now writes the 24-bit latch the mode table
  initialises. Fixed-gain RAW measurements confirmed the old control was inert
  and the new one responds monotonically; photos, video, lighting changes,
  reopening and suspend/resume were exercised. Automatic exposure tuning is
  still separate work.
- **Attached Flex Keyboard at poweroff:** the kernel now issues the same
  touchpad report-disable sequence at shutdown as at suspend
  (`kernel/sp11-surface-hid-shutdown.patch`). That is correct but not
  sufficient: on battery the keyboard's haptics can still stay on after
  poweroff, and captures show identical successful commands in failing runs,
  so the cause sits on the EC/pogo power hand-off side and remains open (see
  `KNOWN-ISSUES.md`). An experimental Bluetooth-blocking guard
  (`sp11-flex-shutdown.service`) is included as opt-in source only; it was not
  shown to help reliably and is not enabled by the installer.
- **Power-profile helper hardened:** a legitimately lower effective kernel
  limit (thermal or boost QoS) no longer fails verification; a write failure
  rolls back every attempted policy; a failed service start keeps those
  rollback limits while an intentional stop restores the full range. The
  three profile targets are unchanged. 18 tests. Update the helper and its
  unit together.
- **Kernel build and image pipeline** follow the kernel: `sp11-cpufreq-boost`
  is enabled instead of the review20 `sp11-noidle` block, the live menu
  offers a `cpuidle.off=1` entry as the conservative fallback, `sp11_deep_idle`
  and the ipcc diagnostic switch are gone from every command line (they do not
  exist on 7.3), `efi-pstore` is a module so panics are actually captured on
  this firmware, and hard lockups panic instead of freezing silently. The
  rollback tools accept installs of either beta.

- **Boot splash:** Plymouth with the SP11 theme now covers the RAM copy on
  the live image and the boot of an installed system. The initramfs hook
  (`rootfs/etc/initcpio/install/sp11plymouth`) brings the whole display
  chain up early (msm plus the ADSP, type-C retimer and pmic_glink drivers
  and firmware it needs), so the panel lights up a few seconds into boot
  when the owner firmware is present. Package `plymouth 26.134.222-2` joins
  the frozen July package snapshot (664 live packages).
- **Windows USB creator** (`sp11-usb-creator-windows-<date>.zip`): one
  script that collects the firmware, writes the ISO to the stick sector by
  sector and copies the firmware onto it. Written because Rufus in ISO mode
  breaks the three-partition image. Reviewed, not yet widely run.
- **Guided pairing:** "Pair Surface Flex Keyboard" and "Pair Surface Slim
  Pen 2" in the app grid explain the steps and the current shortcomings,
  then run the pairing tools. The live image now carries the pairing tools
  and the detach-reconnect hook too.

Carried over from the source-only changes published between the betas:

- **Linux 7.3 forward port** (`kernel/port-7.3/`): the review20 series on
  mainline 7.3 with the upstreamed PDC/idle commits dropped and deep idle
  unrestricted. About 3.7 W less at idle, 0.535 W in deep suspend, a clean
  overnight cycle and a full day of suspend/resume. Now the shipped kernel.
- **Flex Keyboard pairs natively over Bluetooth** with no Windows keys:
  `kernel/sp11-flex-bt-oob-pairing.patch` (KIP OOB HID node + LE legacy OOB
  pairing in SMP) and `sp11-flex-pair`, plus a udev hook that reconnects the
  keyboard on every detach. The Bluetooth address documentation was corrected
  (the EFI value is the Wi-Fi MAC; the adapter is one lower).
- **Slim Pen 2 tail button** via a plain BLE bond (`sp11-pen-pair`), arriving
  as Meta+F19/F20.
- **Half-screen colour tint after resume/DPMS** fixed in the DPU driver
  (`kernel/sp11-dpu-gc-lut-after-modeset.patch`).
- **Ambient light sensor:** `install-sensors.sh` unmasks
  `iio-sensor-proxy.service`, which a masked host unit had silently disabled.
- **Suspend self-wake fixed:** once anything claimed the ambient light sensor,
  iio-sensor-proxy left the ADSP sensor stream running and it woke the SoC
  under a second into every suspend (the 2026-08-29 overnight lid cycle looped
  46 times and then hung). `sp11-sensors-sleep` now stops the proxy across
  sleep; a `sp11-suspend-tracker` hook and `sp11-suspend-report` record every
  cycle (duration, drain, wake IRQ, wakeup sources, IRQs that ticked).

# Public beta (2026-08-28)

First public beta ISO. Compared with the held engineering images of July and
August 2026:

- **Firmware collection no longer depends on the maintainer's file hashes.**
  `RUN-IN-WINDOWS.cmd` / `sp11-collect-firmware.ps1` (Windows) and the new
  `sp11-firmware` tool (Linux) pick the newest complete driver package per
  component from the Windows DriverStore, keep DSP image and device tree
  together, prefer the GPU file Windows actually deploys, and record
  provenance in a v2 manifest. Linux validates structure at boot. The newer
  CDSP package installed by Windows Update (driver 30.0.0219.1000) was
  verified to boot on the review20 kernel.
- **Firmware reaches the kernel through GRUB.** When the five files are on
  `SP11FW`, GRUB appends them to the initramfs (`newc:`), so GPU acceleration
  and audio work from the first boot without any partition discovery in early
  userspace. Initramfs partition import and a pre-login userspace service
  remain as fallbacks; `/etc/sp11-external-firmware-status` records which
  path succeeded.
- **Installer:** installing without owner firmware is now allowed after an
  explicit confirmation; `sp11-firmware` and the documentation are copied to
  the installed system so firmware can be added later
  (`sudo sp11-firmware install --from-windows`).
- **Image:** SquashFS switched to xz (smaller ISO), `SP11FW` grown to
  128 MiB, Codex/engineering helper files removed from the USB stick,
  `START-HERE.txt` rewritten.
- **Release plumbing:** `BINARY-RELEASE-HOLD.md` replaced by
  `RELEASE-STATUS.md`; build/audit scripts no longer require the hold;
  `scripts/package-release.sh` produces release file names, `SHA256SUMS`,
  and split parts for GitHub's 2 GiB asset limit.
- Documentation: `docs/GETTING-STARTED.md`, `docs/FIRMWARE.md`,
  `docs/UNINSTALL.md`, `docs/BUILD-ISO.md`; `README.md` and
  `docs/INSTALL.md` rewritten for the beta.

The kernel (`7.1.3-sp11-suspend-review20`), package set, and installer
executor logic are unchanged from the qualified August 2026 builds.

Hardware check on 2026-08-28 (maintainer's unit, USB 2.0 stick, firmware
collected by `RUN-IN-WINDOWS.cmd` on Windows): GRUB injected the five files,
the initramfs validated them before module loading, the RAM copy verified in
107 s, and GNOME came up with zero failed units and GPU acceleration; Wi-Fi,
Bluetooth, touch, pen, cameras, microphones, and speakers worked. A fatal
early-hook redirection found during this test is fixed (commit 3d5b372).

# Review20 beta consolidation

This branch prepares the exact, hardware-qualified review20 stack for a beta
ISO. Binary and ISO publication remains blocked by
`BINARY-RELEASE-HOLD.md` until clean reconstruction, archive review, and
install/rollback tests are complete.

The first non-installing ARM64 UEFI GNOME image has now been assembled under
that hold. Its first physical boot exposed and rejected an incompatible
Zstandard SquashFS that the qualified kernel could not decompress. The
corrected image uses the kernel-supported gzip codec, resolves the real live
medium, carries the early display/input stack, and passes strengthened static
package, firmware, privacy, initramfs, codec, service, EFI, GPT, and
artifact-hash audits. It reached GNOME with working OLED and touchscreen, but
was then rejected because SquashFS's `-all-root` option changed the live
user's private home ownership to root. The current image preserves staged
numeric ownership and audits the finished SquashFS home metadata. The repair3
image additionally copies and verifies the SquashFS in RAM, avoiding repeated
read failures when the tested USB hub resets. It booted from removable media
and passed OLED, touch, pen, Wi-Fi, speakers, microphones, and cameras. It is
still held pending source closure and install/rollback qualification; it is
not a release. See `iso/LIVE-IMAGE.md`.

The blob-free one-drive path also passed with the exact owner-supplied
`SP11FW` pack. Wi-Fi, speakers, microphones, cameras, touch, and pen worked,
the diagnostic report persisted to the writable partition, and a reboot
repeated the complete hardware pass. Qualcomm
Windows driver 1.0.4374.1300's newer board-data revision timed out during
ath12k BDF loading and is deliberately rejected. The final fail-closed
artifact, SHA-256
`2fe5f6050ec32b8d5c8d4497198fc87cb1f5ee7ac51057d4efdb8da9dd641d48`,
also passed the complete on-device hardware check. Both Windows and Linux
in-place population of the physical writable partition have been exercised;
the original Linux path reproduced all six qualified files while preserving
helpers and reports. A provenance follow-up then established that the working
`board.bin` is an unmodified redistributable record inside the allowlisted
WCN7850 `board-2.bin`. The successor image therefore includes that exact
extracted record and reduces the owner-supplied companion contract to five
DSP/GPU files. The fresh-media workflow passed end to end: the bundled
Windows collector produced exactly five verified files and no board data,
then the exact ISO, SHA-256
`32af335c8e737799589d0179a3620355402d2b9b06dbf604009c8044800f9741`,
cold-booted with internal Wi-Fi, touch, pen, speakers, microphones, and
cameras working and zero failed units. The persistent report SHA-256 is
`8935f6228769e6988f8cd918c480cdfad0029926850c50671e876556d8bd7b74`.
The earlier absent-companion and incompatible-board boots remain valid tests
of the old six-file all-or-nothing contract.

Installation work has crossed the first controlled mutation gate. The
physical live-wrapper preflight passed while preserving the GRUB config, GRUB
environment, Windows loader, and empty installer namespace. The exact held
installer then created a complete integrity-protected rollback transaction,
installed only its isolated `/boot/sp11-beta` namespace, regenerated GRUB
with the Windows chainloader intact, preserved the persistent default, and
armed only the next boot. The independent post-apply verifier passed the
kernel, DTB, all 3,759 modules, initramfs VideoCC, rollback state, Windows
loader/EFI entry, and one-shot checks. The one-shot target boot, Windows boot,
and live rollback subsequently passed. The separate fresh-machine installer
also completed a physical dual-boot reinstall through partitioning, root
population, target configuration, and both installed-system verification
passes. Its final NVRAM step exposed a reinstall bug: the executor refused the
intentionally retained stale `SP11 Linux` entry instead of replacing it after
the ESP received a new GPT identity. Manual deletion/recreation recovered the
already populated system without repartitioning, and the installed system
booted with Windows Boot Manager preserved and zero failed units. The
maintained executor now reconciles one or more stale entries, preserves
non-SP11 BootOrder, validates exactly one active replacement, and has
fresh/stale/duplicate/failure-cleanup regressions. Explicit repair/removal,
physical wipe qualification, and the complete post-install hardware matrix
remain open.

The first held successor containing that fix has been rebuilt and statically
audited. It is 2,396,196,864 bytes with SHA-256
`d50e4729fcd7654029e3f5e7d8c16dbabf8ce8cc3660f1d550ad06bdfb5b944f`.
The build also closes an installed-root staging portability defect by
normalizing filesystem-specific directory allocation sizes out of the root
manifest while retaining exact file sizes/hashes, symlink targets, modes, and
ownership. The installed-root archive remains byte-identical. The ISO was
written to the development thumb drive with serial `0308100000000053`; an
exact 2,396,196,864-byte device read-back reproduced the ISO SHA-256 above.
Physical reinstall/removal qualification remains required before this
successor can advance.

The next held live-image iteration adds a deterministic owner-supplied
2880x1920 Tux Surface wallpaper, GNOME's orange accent, and the signed native
Rnote 0.14.2-2 package. The exact qualified iptsd 3.1.0 payload and dynamic
pen-device lifecycle remain unchanged. The live closure is now 663 packages;
the wallpaper remains local engineering input and is not added to the public
source tree.

## Qualified kernel

- Linux release: `7.1.3-sp11-suspend-review20`
- Source commit: `18d7951a10dc49e383d16c6af82fc2c07784de3d`
- Source tree: `b820f10abba096e23a28506d7ad591dffdedf1a8`
- Promoted reproducible Kernel Image SHA-256:
  `918ed2560654355555535290fd0d9657e1afc7022b3e46cc8396155d3575f256`
- Historical locally qualified Image SHA-256:
  `b3ca9ba56570ff1bf8217a866563f1e9788c5dfdc3a153a9b673e3b6e9624ed5`
- OLED DTB SHA-256:
  `5e9009f5bd96a760a33086d1a8842e3228e3d28c413f96d70aca4914f7e397ed`
- Preserved safe entry: `7.1.3-sp11-camera-review12`
- Review12 source commit:
  `a3e71f7080ee40dccfdd9500b8957a7c143fb6a2`

The cumulative review20 patch series and incremental Git bundle are included
under `kernel/`. See `docs/REVIEW20-CONSOLIDATION.md` for provenance,
qualification evidence, and remaining release gates.

## Reproducible beta candidate

Two clean builds from empty output directories are byte-identical across the
kernel Image, `vmlinux`, OLED DTB, configuration, module ABI, generated build
identity, and all 3,759 in-tree modules. The clean candidate Image SHA-256 is
`918ed2560654355555535290fd0d9657e1afc7022b3e46cc8396155d3575f256`.
The X1E VideoCC provider is now part of that reproducible module set and is
forced into the initramfs; its binary exactly matches the provider used during
earlier hardware qualification. On 2026-07-28, the corrected Image passed its
one-shot target boot, active state1 checks on all 12 CPUs, VideoCC binding,
deep suspend/resume, and the complete post-resume hardware matrix. It is now
the Image accepted by the payload assembler, installer, and verifier and was
promoted as the tested host's persistent default while preserving the prior
review20, review12, and Windows boot entries.

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
- Only a narrow official linux-firmware allowlist is eligible for the future
  ISO. The audio topology and UCM routing are now covered by tracked
  redistributable source. Six Surface-specific DSP/GPU/board files are not
  redistributable from the qualified host. The hybrid ISO supplies a writable
  `SP11FW` partition preloaded only with editable collector tools, a
  user-invoked persistent diagnostic capture, and instructions; the owner uses
  it to add firmware after writing the live USB. The ISO continues safely
  while its firmware payload is absent or incompatible, with documented
  hardware limitations.
- Other Surface Pro 11 variants, distributions, and boot loaders are not yet
  qualified
- Camera color tuning and ordinary desktop camera integration remain
  experimental
- One extended-use graphical freeze followed by an automatic debug panic and
  reboot remains under investigation; historical crash data points toward the
  MSM/Adreno GMU recovery path, but the exact review20 failure was not captured

## Dual boot

The GRUB Windows chainloader entry works. A long blank delay before Windows
starts is expected when Windows USB/kernel debugging is enabled; that delay was
previously mistaken for a broken GRUB entry.
