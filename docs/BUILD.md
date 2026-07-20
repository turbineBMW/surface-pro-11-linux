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
git switch sp11-camera-review
git rev-parse HEAD^{commit} HEAD^{tree}
```

The final command must print:

```text
675d89b381d8b730a3f2eff1086875481ee5b515
03c278405e6d2fd0ffa1fd4cad860ef45c7adbbc
```

The bundles are incremental: the sanitized bundle requires Linux `v7.1.3`,
and the camera bundle requires the sanitized tip. `kernel/README.md` also
documents cumulative-patch reconstruction.

## Build

The maintained helper verifies the exact source identity, merges the camera
configuration, and builds with Clang/LLVM and `W=1`:

```sh
./scripts/build-kernel.sh \
  --source /path/to/linux \
  --output /path/to/build \
  --jobs "$(nproc)"
```

The resulting kernel release is `7.1.3-sp11-camera-review4`. Primary outputs:

```text
/path/to/build/arch/arm64/boot/Image
/path/to/build/arch/arm64/boot/dts/qcom/x1e80100-microsoft-denali-oled.dtb
/path/to/build/Module.symvers
```

To stage modules without touching the host system:

```sh
make -C /path/to/linux O=/path/to/build \
  KERNELRELEASE=7.1.3-sp11-camera-review4 \
  LOCALVERSION= LLVM=1 \
  INSTALL_MOD_PATH=/path/to/stage modules_install
```

Compare the source commit/tree, release, config, compiler, Image, DTB, and
module ABI with `kernel/BUILDINFO` and `docs/CAMERA-REVIEW.md`. Toolchain or
timestamp differences can prevent byte-identical output even when the source
and configuration match.

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
