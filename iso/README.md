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

The first snapshot resolves to 595 distinct recipe identities. The
`package-recipes.lock.tsv` SHA-256 is
`1361fe0a28652ddb62003925603186fb0b90df3c10d9d02479e902230895eed5`.
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
license and notice material. Surface-specific ADSP/CDSP/audio files and the
machine-local WCN7850 `board.bin` remain denied.

Under the active binary/ISO hold,
`scripts/cache-locked-packages.sh --local-staging` performs a non-installing
pacman download into `work/`, verifies repository and detached package
signatures, checks every locked SHA-256 and size, and extracts package build
metadata. It refuses release output and never modifies the host package
database.

The first held snapshot contains all 672 packages and signatures plus 2,016
extracted metadata files. Its `PACKAGE-SNAPSHOT.tsv` SHA-256 is
`cb336c6fa1dfab9644f304e89a797ab70d2e1131c6192484a5d043559c7221fe`.
It remains ignored local engineering output, not a release artifact.

## First held image

`scripts/build-held-live-image.sh` now assembles a non-installing ARM64 UEFI
GNOME environment from the package snapshot, exact review20 custom payload,
and firmware allowlist. `scripts/audit-held-live-image.sh` verifies the live
root, initramfs, firmware boundary, ARM64 fallback loader, El Torito entry,
GPT/ESP structure, and artifact manifest.

The first audit-passing image is documented in `LIVE-IMAGE.md`. It remains
under the binary/ISO hold and still requires removable-media hardware
qualification.

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
