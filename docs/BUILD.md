# Build the experimental source

## Reconstruct the reviewed kernel history

```sh
git clone https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git linux
cd linux
git checkout v7.1.3
git fetch /path/to/surface-pro-11-linux/kernel/sp11-sanitized2.bundle \
  refs/heads/sp11-sanitized2:refs/heads/sp11-sanitized2
git fetch /path/to/surface-pro-11-linux/kernel/sp11-camera-review.bundle \
  refs/heads/sp11-camera-review:refs/heads/sp11-camera-review
git fetch /path/to/surface-pro-11-linux/kernel/sp11-touch-spi-autoload.bundle \
  refs/heads/fix/touch-spi-autoload:refs/heads/fix/touch-spi-autoload
git fetch /path/to/surface-pro-11-linux/kernel/sp11-tablet-mode-resume-resync.bundle \
  refs/heads/fix/tablet-mode-resume-resync:refs/heads/fix/tablet-mode-resume-resync
git switch fix/tablet-mode-resume-resync
git rev-parse HEAD^{commit} HEAD^{tree}
```

The final command must print:

```text
8625b38c7f8efca528ac8ea1df27bc7ee416605a
54cf9fad522b0600e72a545deb151fc749e201eb
```

The bundles are incremental: the sanitized bundle requires Linux `v7.1.3`,
the camera bundle requires the sanitized tip, the touch autoload correction
requires the camera tip, and the tablet-mode resume resynchronization requires
the touch-autoload tip. `kernel/README.md` also documents patch reconstruction.

## Build

The maintained helper verifies the exact source identity, merges the camera
configuration, and builds with Clang/LLVM and `W=1`:

```sh
./scripts/build-kernel.sh \
  --source /path/to/linux \
  --output /path/to/build \
  --jobs "$(nproc)"
```

The resulting kernel release is `7.1.3-sp11-camera-review6`. Primary outputs:

```text
/path/to/build/arch/arm64/boot/Image
/path/to/build/arch/arm64/boot/dts/qcom/x1e80100-microsoft-denali-oled.dtb
/path/to/build/Module.symvers
```

The helper derives `SOURCE_DATE_EPOCH` and `KBUILD_BUILD_TIMESTAMP` from the
reviewed source commit and fixes the build identity to
`sp11@reproducible #1`. Builds in different directories should therefore
produce byte-identical Image, DTB, configuration, `Module.symvers`, and module
content when the declared toolchain and other inputs match. Treat any mismatch
as a failed reproducibility check; do not publish the artifacts.

Review6 intentionally retains review4's byte-identical merged configuration:
the review5 touch correction and review6 resume correction change source only
and require no configuration change. Consequently,
`camera-review.config.fragment` still records
`CONFIG_LOCALVERSION="-sp11-camera-review4"`. The helper's enforced
`KERNELRELEASE=7.1.3-sp11-camera-review6` is the authoritative release identity
and must not be omitted when building or installing review6 artifacts.

The helper also requires Python 3.14.6 and invokes it with `-S` so host or user
site packages cannot change Kconfig feature visibility. In particular, the
optional `lxml` package otherwise changes whether
`CONFIG_DRM_MSM_VALIDATE_XML` is emitted in `.config`, even when the option
remains disabled. Disabling site packages reproduces the reviewed config hash
and the Kconfig feature visibility present during both clean builds.

To stage modules without touching the host system:

```sh
make -C /path/to/linux O=/path/to/build \
  KERNELRELEASE=7.1.3-sp11-camera-review6 \
  LOCALVERSION= LLVM=1 PYTHON3="python3 -S" \
  INSTALL_MOD_PATH=/path/to/stage modules_install
```

`modules_install` creates `build` and sometimes `source` symlinks that can
contain absolute local paths. Remove those symlinks from a release staging tree
or replace them with package-managed, non-private paths, then scan every staged
symlink and archive member before packaging.

Compare the source commit/tree, release, config, compiler, reproducible build
identity, Image, DTB, and module ABI with `kernel/BUILDINFO` and
`docs/CAMERA-REVIEW.md`. A different declared toolchain remains a distinct
build input and needs its own identity and validation.

Do not install the experimental kernel as the only bootable kernel. There is no
supported binary installer in this source preview; see `INSTALL.md`.

## iptsd

See `userspace/iptsd/README.md`. Touch and pen testing used both `iptsd` and
`iptsd-check-device` from the pinned clean upstream commit. No iptsd binary is
included here.

## libcamera

The optional bundle in `userspace/libcamera/` requires upstream libcamera
v0.7.1 commit `183e37362f57ff3ce7493abf0bc6f1b57b931f55`. Its README records the
source identity and matched IPA requirements. The tested machine currently uses
distribution libcamera packages plus the tuning file; do not mix a newly built
core with IPA modules or signatures from another build.

Kernel RAW capture does not require this older libcamera branch. Normal desktop
camera color processing and tuning remain experimental.

## Power Profiles Daemon

See `userspace/power-profiles-daemon/README.md`. No patched daemon binary is
included. If built locally, keep it separate from the distribution package so
the change remains reversible.

## IR and Howdy proof of concept

The reviewed kernel source enables the VD55G0 IR camera and PM8550 illuminator.
The local Y10P-to-GREY bridge, Howdy enrollment, and separately built
`v4l2loopback` module used during validation are deliberately not included in
this source preview. They require their own packaging and safety review before
distribution.
