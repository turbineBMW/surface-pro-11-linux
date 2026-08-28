> **Beta note (2026-08-28):** the current builder invocation, inputs, and
> release packaging are documented in [`docs/BUILD-ISO.md`](../docs/BUILD-ISO.md).
> The image now uses SquashFS/xz and a 128 MiB `SP11FW` partition, and GRUB
> passes owner firmware to the kernel via `initrd … newc:`. Earlier sections
> below describe the held engineering images and remain as history.

# SP11 beta live-image package profile

This directory freezes the distribution-package input to the first
Surface Pro 11 beta live image. It is intentionally narrower than the
maintainer's daily-driver installation.

## Recommended desktop

The live image uses a conservative GNOME 50 Wayland session:

- GDM, GNOME Shell, Settings, Files, Console, Text Editor, Disks, System
  Monitor, Logs, and Disk Usage Analyzer;
- GNOME's built-in touch keyboard and accessibility stack;
- NetworkManager, Wi-Fi, Bluetooth, PipeWire, WirePlumber, and ALSA tools;
- distribution libcamera, signed IPA modules, libcamera tools, the PipeWire
  libcamera plugin, and the GStreamer libcamera plugin;
- Snapshot, Sound Recorder, Firefox, Loupe, and Papers for live validation
  and documentation;
- Rnote 0.14.2-2 for pressure, tilt, eraser, and handwriting validation with
  the exact qualified project iptsd runtime;
- an owner-supplied Tux Surface wallpaper and GNOME orange accent as
  deterministic local engineering defaults; and
- a bounded set of filesystem, partitioning, networking, and recovery tools.

The direct runtime inputs are in `packages-live.aarch64.tsv`. The much
smaller host-side image-construction toolset is in
`packages-build.aarch64.tsv`.

## Exact package lock

`scripts/generate-package-lock.sh --write` resolves both profiles against an
empty pacman local database and the currently synchronized Arch Linux ARM
repository databases. It writes:

- `packages.lock.tsv`, containing the complete transitive closure, exact
  version, architecture, package filename, repository SHA-256, compressed
  size, installed size, binary URL, package page, and source-files URL; and
- `repositories.lock.tsv`, containing the SHA-256 of every repository
  database used for dependency resolution.

After packages are cached, `generate-package-recipe-lock.sh` derives
`package-recipes.lock.tsv` from their signed `.BUILDINFO` metadata. It records
the exact `pkgbuild_sha256sum` used for every distinct `pkgbase`, including
split packages, rather than trusting a moving packaging branch.

The current snapshot resolves to 596 distinct recipe identities. The
`package-recipes.lock.tsv` SHA-256 is
`ee489a2f3931d0a424b56a4e5d6d004e8593805d4db56cc0f147bc9984879847`.
The Arch Linux ARM `Source Files` endpoint was returning HTTP 500 when this
lock was created, so source staging must use the pinned Arch/Arch Linux ARM
packaging histories as a fallback and reject any PKGBUILD whose checksum does
not match the lock.

The generated lock is a snapshot, not a promise that a rolling mirror will
retain old files. Before an image can be released, the build must cache every
exact signed package named by the lock and verify its SHA-256. The release
source bundle or durable written source offer must also retain:

1. each package's exact Arch Linux ARM `Source Files` recipe;
2. all local files and patches referenced by that recipe;
3. every upstream source archive needed by the recipe;
4. the binary package's `.BUILDINFO`, `.PKGINFO`, `.MTREE`, signature, and
   applicable license material; and
5. the source-to-binary association for split packages through `pkgbase`.

Arch Linux package recipes alone are not complete corresponding source: they
normally contain URLs for acquiring upstream source. The upstream inputs must
therefore be retained as well. Package recipes should be pinned by immutable
commit or archived source snapshot rather than a moving branch.
The current authoritative-source mismatch and acceptance criteria are
recorded in `SOURCE-STATUS.md`.

## Inputs outside this lock

The audited SP11 review20 kernel/modules, iptsd, patched Power Profiles
Daemon, rootfs overlay, and their corresponding-source archive are custom
payload inputs. They remain covered by the separate held-payload manifests
and are not represented as distribution packages here.

Firmware is separate from the distribution package closure. The first held
image selects exactly the 11 redistributable files in
`firmware/allowlist.tsv` from four verified signed packages and copies their
license and notice material. It also extracts the exact qualified WCN7850
board record described by `firmware/derived.tsv` without changing its bytes.
The exact tested audio topology is built from tracked BSD-3-Clause source and
paired with the tracked project UCM profile. Five owner-supplied DSP/GPU files
remain denied from the ISO. A 64 MiB
FAT32 `SP11FW` partition, containing only editable redistributable collector
and diagnostic scripts, an exact-hash manifest, and quick-start instructions,
is appended for safe post-write personalization and persistent, user-invoked
issue capture on the same USB drive.

Under the active binary/ISO hold,
`scripts/cache-locked-packages.sh --local-staging` performs a non-installing
pacman download into `work/`, verifies repository and detached package
signatures, checks every locked SHA-256 and size, and extracts package build
metadata. It refuses release output and never modifies the host package
database.

The current held snapshot contains all 673 packages and signatures plus 2,019
extracted metadata files. Its `PACKAGE-SNAPSHOT.tsv` SHA-256 is
`60a1d33fd546985a9a73ce286fb34b1cbd9fb153436f6639a12fa55901e3cf14`.
It remains ignored local engineering output, not a release artifact.

## First held image

`scripts/build-held-live-image.sh` now assembles an ARM64 UEFI GNOME
environment from the package snapshot, exact review20 custom payload, and
firmware allowlist. It embeds a manifest-covered held installer kit and a
separate live wrapper that can only mount an explicitly selected internal
root and ESP read-only and run installer preflight. It exposes no live apply
path. The builder requires the exact local Tux Surface PNG by SHA-256, copies
it only into held work output, compiles GNOME system defaults for both
light/dark wallpaper and orange accent, and does not add the artwork to the
public tree. `scripts/audit-held-live-image.sh` verifies those defaults,
Rnote's exact package version, the qualified iptsd binary, live root,
installer kit, module manifest, read-only wrapper policy, initramfs, firmware
boundary, ARM64 fallback loader, El Torito entry, GPT/ESP structure, and
artifact manifest.

The first physical boot rejected an incompatible live-root compression
choice. The next image reached GNOME with working touch but exposed and
rejected global SquashFS owner rewriting. The repair3 image copied and
verified the live root in RAM to survive the tested USB hub reset, then passed
OLED, touch, pen, Wi-Fi, speakers, microphones, and cameras on target
hardware. The artifact and remaining publication gates are documented in
`LIVE-IMAGE.md`. It remains under the binary/ISO hold.

## Hard exclusions

The first beta does not include:

- Quickshell, Niri, or the maintainer's personalized desktop configuration;
- AUR/foreign packages, proprietary applications, developer SDKs, containers,
  or compilers;
- Howdy, biometric models, PAM changes, the IR bridge, or v4l2loopback;
- Windows drivers, private traces, generated sensor registries, Bluetooth
  keys/identity, NetworkManager profiles, credentials, or machine identifiers;
- `linux`, `linux-aarch64`, or another distribution kernel alongside the
  exact SP11 review20 payload;
- runtime USB-autosuspend, MSM PSR, or other rejected power experiments; or
- proprietary SSC sensor configuration. The open `iio-sensor-proxy` package
  is included for future safe enablement, but its SP11 sensor service must
  remain disabled when the external configuration is absent.

`scripts/audit-package-lock.sh` enforces the package-level exclusions and
detects repository or dependency drift.
