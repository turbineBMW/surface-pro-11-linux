# Provenance and exact source identities

This document records what the experimental source candidate contains, where imported
work came from, and which development inputs were used. It is a provenance
record, not a legal opinion.

## Installation foundation

The installation and firmware bootstrap builds on Dale Whinham's
[`dwhinham/linux-surface-pro-11`](https://github.com/dwhinham/linux-surface-pro-11).
That project supplies the original Arch Linux ARM bootstrap, external firmware
workflow, and early Surface Pro 11 enablement. No Microsoft or Qualcomm
firmware file is included here.

## Kernel

The separate `kernel/sp11-surface-hid-shutdown.patch` adds an original shutdown
callback using the existing in-tree HID suspend API in the GPL-2.0-or-later
Surface HID transport. It contains no firmware-derived code or vendor report
payloads. It makes poweroff issue the same touchpad report-disable sequence as
suspend; captured traces confirmed the commands succeed, and also that a
battery-powered poweroff can leave the attached Flex Keyboard's haptics on
regardless, so the callback is correct but not a complete fix
(`KNOWN-ISSUES.md`). It is part of the 7.3 port branch.

The separate `kernel/sp11-imx681-exposure.patch` adapts Leon Silcott's
GPL-2.0-only IMX681 register correction from
[`ooaklee/linux_ms_dev_kit-sp11` commit `b1754869f458`](https://github.com/ooaklee/linux_ms_dev_kit-sp11/commit/b1754869f458).
It changes only the exposure-register definition to `CCI_REG24(0x0229)`.
It imports no firmware or sensor-table bytes and does not change the historical
review20 bundle identities below. External hardware evidence motivated the
correction and local fixed-gain measurements confirmed it. It is part of the
7.3 port branch.

- Upstream: Linux stable
- Upstream URL: `https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git`
- Base tag: `v7.1.3`
- Base commit: `199c9959d3a9b53f346c221757fc7ac507fbac50`
- Sanitized tip: `2ace98eb6ef18cbd48074eed9f5b585d19ce398b`
- Sanitized tree: `3924711c8ab3ee5c0208d214a4433eafc271df42`
- Camera tip: `675d89b381d8b730a3f2eff1086875481ee5b515`
- Camera tree: `03c278405e6d2fd0ffa1fd4cad860ef45c7adbbc`
- Touch autoload fix tip: `86fc94c58a89a56c7ceb57b42c6025b2569da56d`
- Touch autoload fix tree: `4624d85595964242c26d7042106d068cbbdd9977`
- Tablet-mode resynchronization tip: `940bbc856a120e6f967f9dbaf825d5473bfae664`
- Tablet-mode resynchronization tree: `62edee5183ed3b42ee3a2f9f0c71066c3ab87742`
- Charge-limit reliability tip: `4d50f4a7a8debb28b5780f80f941f1fcee4036cd`
- Charge-limit reliability tree: `9de653f31534b28a525f86d23c441deb831c0e2f`
- Camera-switch fix tip: `fd1932d6e2a45e665c062b1b1c810f09db46ab4e`
- Camera-switch fix tree: `c30f01a3d05a28bf8c4a0e809fc8f81a919927af`
- Review12 prerequisite tip: `a3e71f7080ee40dccfdd9500b8957a7c143fb6a2`
- Review20 qualified tip: `18d7951a10dc49e383d16c6af82fc2c07784de3d`
- Review20 qualified tree: `b820f10abba096e23a28506d7ad591dffdedf1a8`
- Candidate release string: `7.1.3-sp11-suspend-review20`
- Delta: 12 sanitized commits, 13 reviewed camera commits, and one corrective
  touch-driver commit, three tablet-mode resynchronization commits, one
  charge-limit reliability commit, and one camera-switch fix commit

`kernel/sp11-suspend-review20.bundle` adds 20 commits to the exact review12
prerequisite. It contains the PDC wake/deep-idle series with original
authorship, subsequent suspend and power corrections, and the locally tested
review20 integration changes. The accompanying 20-message patch series
reconstructs the same source delta. Exact hashes and the local-commit
sign-off boundary are recorded in `docs/REVIEW20-CONSOLIDATION.md`.

`kernel/sp11-sanitized2.bundle` preserves the exact incremental
history and requires the Linux base commit. The cumulative patch reproduces
the final source tree but not commit metadata.

`kernel/sp11-camera-review.bundle` adds the reviewed camera source on top of
that exact sanitized tip. Its cumulative patch reproduces the camera tree from
the sanitized prerequisite. `kernel/sp11-touch-spi-autoload.bundle` adds the
single modalias correction on top of the camera tip. All histories are
incremental and contain source, not a prebuilt kernel or module payload.
`kernel/sp11-tablet-mode-resume-resync.bundle` adds the delayed resume and KIP
connection controller posture re-queries on top of the exact touch-autoload
tip. `kernel/sp11-charge-limit-reliability.bundle` adds the focused Qualcomm
battery-manager correction on top of the exact tablet-mode resynchronization
tip.

The history preserves the original authorship of the HID-over-SPI work:

- Jingyuan Liang — six commits
- Jarrett Schultz — three commits
- Angela Czubak — two commits
- Dmitry Antipov, Dmitry Torokhov, and other reviewers/signers recorded in the
  individual commit messages

Those commits implement Microsoft's published
[HID over SPI protocol specification](https://www.microsoft.com/en-us/download/details.aspx?id=103325)
and retain Microsoft, Google, Red Hat, ENAC, and individual copyright notices
where present. The remaining consolidated SP11 platform commit is attributed
to `turbinebmw` in the bundle.

SP11 touch/QSPI changes were independently written from the published HID-over-
SPI specification, Linux source, hardware experiments, and WinDbg runtime
traces of the author's own Surface Pro 11 and licensed Windows installation.
The author reports no NDA, confidential documentation, proprietary source
access, decompilation, or disassembly-derived pseudocode. No Windows binary,
firmware extracted from Windows, memory dump, trace log, or copied proprietary
source is included in the sanitized artifacts. The detailed input declaration
and distribution boundary are recorded in `docs/TOUCH-QSPI-PROVENANCE.md`.

The public kernel history is curated rather than a verbatim copy of the private
research history. The original HID-over-SPI commit authorship is preserved,
while an unused descriptor-only diagnostic mode and its captured packet
expectations were removed from both the final tree and distributed Git objects.

## Excluded former kernel material

The camera-free prerequisite and fresh reviewed camera history omit every
camera commit from the former Practical8 line. In particular, neither public
history imports the former additions as Git objects:

- Windows camera-package sensor tables for IMX681 or OV13858;
- the VD55G0 firmware patch or its embedded byte array;
- Windows C-PHY replay tables or CAMNOC values;
- the imported Qualcomm C-PHY table changes; or
- the Surface camera device-tree and CAMSS enablement changes.

The replacement camera sources are documented independently in
`docs/CAMERA-REVIEW.md`. Former Practical8 artifacts are withdrawn and must not
be copied into a public repository or release. See
`docs/REDISTRIBUTION-REVIEW.md`.

## iptsd

- Upstream: `https://github.com/linux-surface/iptsd.git`
- Exact commit: `a83bc1232f7096f8b33b50fdbda249cd640de670`
- Version commit subject: `iptsd v3.1.0`
- Local source changes: none
- License: `GPL-2.0-only`

The release-specific udev rule, service, and sleep integration in `rootfs/`
are original MIT-licensed integration work. A binary release must accompany
the iptsd binary with this exact corresponding source or a compliant written
source offer.

## libcamera

- Upstream: `https://git.libcamera.org/libcamera/libcamera.git`
- Exact SP11 tip: `72dc8cff6447792e8d1c0668f3c353eb0740e0db`
- Exact tree: `d27c3bd9f4ce87d2cdf87f52ffd9d63bacf744b1`

The first two patches modify LGPL-2.1-or-later files and add independently
written IMX681 property/helper entries. The third adds an original CC0-1.0
tuning file based on a measured black pedestal and modifies libcamera's build
metadata. These userspace materials are optional; kernel RAW capture does not
depend on shipping this older libcamera branch.

## Power Profiles Daemon

- Upstream: `https://gitlab.freedesktop.org/upower/power-profiles-daemon`
- Tested version: `0.30`
- Distribution package: Arch Linux ARM `0.30-1`
- License: `GPL-3.0-only`

The SP11 patch points the existing platform-profile backend at the generic
class device and accepts the kernel's `balanced-performance` spelling. A
binary release must include the complete corresponding PPD source and patch,
or a compliant source offer.

## Battery charge-limit integration

The boot and system-sleep service under `rootfs/` is original MIT-licensed
integration work based on Linux's documented power-supply sysfs interface and
live behavior observed on the maintainer's own Surface Pro 11. It contains no
firmware, firmware-derived tables, proprietary source, or captured data.

## Qualcomm sensor userspace

- hexagonrpc upstream: `https://github.com/linux-msm/hexagonrpc`
- Tested version: 0.4.0
- Exact base commit: `dd9ac70c026e1bad93e8cffa3801255b8ceb551e`
- License: GPL-3.0-or-later
- libssc upstream: `https://codeberg.org/DylanVanAssche/libssc`
- Tested version: 0.4.4
- Exact base commit: `3befde3ef215bdb78c4a48aa72c99cd458c2aed0`
- License: GPL-3.0-or-later

The hexagonrpc patch implements reverse-RPC file operations from the public
FastRPC `apps_std` interface and constrains mutation to the Qualcomm sensor
registry. The libssc patch maps the existing light abstraction to the
Microsoft `surface color sensor` endpoint based on target-hardware discovery
and flashlight testing.

The Microsoft Surface Pro 11 driver pack was used privately to identify the
active sensor and supply the qualified machine's sensor configuration. No
driver package, JSON/protobuf configuration, calibration, generated registry,
Windows binary, or firmware from that package is included. The published
implementation contains open-source patches, original service integration,
and factual runtime behavior only. See `docs/SENSORS.md`.

## Bounded IR bridge review branch

The `feature/howdy-ir-review` branch contains an original MIT-licensed bridge
that configures the already reviewed VD55G0 media graph and converts its
644x604 Y10P stream to an 8-bit GREY v4l2loopback stream. It was written during
publication review from the published kernel/media topology, standard
media-controller and V4L2 interfaces, the documented Y10P layout, and the
functional lessons of the maintainer's frozen local proof of concept. It does
not copy the legacy file, preserve its shell-command construction, or include
its raw/PNG output modes, unbounded illumination modes, PAM edits, machine
paths, enrolled models, or captures.

The local validation dependency was v4l2loopback 0.15.4, upstream tag commit
`0f9ee86760b7f2bea174b7e3e7a1d38845da0ab4`, licensed
GPL-2.0-or-later. The direct recognition proof used the Arch package
`howdy 2.6.1-3`, corresponding to upstream Howdy tag commit
`3c9537a35f23773ceca86e79be1ebed3ebe774cc`, licensed MIT. Neither project,
their binaries, a face model, nor PAM configuration is included. The
maintainer selected MIT for the public repository's original integration work
on 2026-07-19. Legacy local bridge files without explicit license headers remain
excluded; this selection does not retroactively license or redistribute them.

## Generated artifact hashes

| Artifact | SHA-256 |
| --- | --- |
| Sanitized cumulative patch | `218ee1ec59a29887aab919fcd37c7d8a21f7ca421ea3757476ddbab76bf07914` |
| Sanitized Git bundle | `cd782a17f4c6645d63d51c057bc9115ac0b7167966a6ce8c663c6e351b79d3e7` |
| Touch autoload patch | `3e698738381fdec196600beb6b7b7e9997dd1cfc53e086eee6e6cb3dfbdc6f0e` |
| Touch autoload Git bundle | `02c18a42b44ddefa2c084f5336df68b3ceac2011779aaa299c07cd0e0970add1` |
| Tablet-mode resynchronization patch | `12f36124f5b7a3d69c22dea082042cbea3cf1c1a784358bad41055a3646db8da` |
| Tablet-mode resynchronization Git bundle | `5c866e0add29dd2c40fa92df73bcbe2d11754d8fed99ab8986aaf8672612d0ab` |
| Charge-limit reliability patch | `39295b72da15d0ee562321f2639def026ded06b3b2321bbb91f6e4ee7ff8fdf6` |
| Charge-limit reliability Git bundle | `89bee6d67608f2d87f3952e1c72be58affcb02eb2ff2f8f8c1ca0ea2aaf06641` |
| Kernel config | `8834ac6021bc4d50034b55c0960938070541387c0984aed4cc6797601ecce7f1` |
| Module.symvers | `b58de2ebd5ca9649b0e7299e4b5b7e3965f70e06506b88c1ec3d5046ce2e9387` |
| Review4 merged config | `b2497f1a5340c6491dd86014d90a9cdd6dcf0a8b1f45806ceb76be35d972517f` |
| Review4 kernel Image | `9fcc24f29713663fdc89a16b5c3dfd097cc03fa91b3cf5b1a7e3e29a403a1338` |
| Review4 OLED DTB | `4caa12c8154470ea484890933f7997ec8e9a95b064927e0c2c8b814f9f658b3a` |
| Review5 merged config | `b2497f1a5340c6491dd86014d90a9cdd6dcf0a8b1f45806ceb76be35d972517f` |
| Review5 reproducible kernel Image | `39027932868b113b3068713dffd8b97168187a69547065ee4e77e7a136e79b97` |
| Review5 OLED DTB | `4caa12c8154470ea484890933f7997ec8e9a95b064927e0c2c8b814f9f658b3a` |
| Review5 module manifest | `337ddc859f8b932d78e316f6935b293e97472afb2d6373333f14058894902c2d` |
| Review6 merged config | `b2497f1a5340c6491dd86014d90a9cdd6dcf0a8b1f45806ceb76be35d972517f` |
| Review6 reproducible kernel Image | `f7ca4995d138d9d03969d5c8cbd65764eb5b5b35c0fa3b201c693a3f62df8dd1` |
| Review6 OLED DTB | `4caa12c8154470ea484890933f7997ec8e9a95b064927e0c2c8b814f9f658b3a` |
| Review6 module manifest | `a4075bc8d26c2637ad46adb377ee42741eb95f987ad439a1e0a1fbe557534b43` |
| Review7 merged config | `b2497f1a5340c6491dd86014d90a9cdd6dcf0a8b1f45806ceb76be35d972517f` |
| Review7 reproducible kernel Image | `caf4fb1db047807a6ff74f5212de51ba96e777a7820e1f7c58ab8d5c210894eb` |
| Review7 OLED DTB | `4caa12c8154470ea484890933f7997ec8e9a95b064927e0c2c8b814f9f658b3a` |
| Review7 module manifest | `1fdf6690301ab8961d69be2e95d5cef928d30c898551a76f38ca9ec088263d1b` |
| Review8 merged config | `b2497f1a5340c6491dd86014d90a9cdd6dcf0a8b1f45806ceb76be35d972517f` |
| Review8 reproducible kernel Image | `c14a14d353a61693f4306b2cea1704d8af50374d2e8647afd12ac9d1e66fd625` |
| Review8 OLED DTB | `4caa12c8154470ea484890933f7997ec8e9a95b064927e0c2c8b814f9f658b3a` |
| Review8 module manifest | `64dd759c407e21a2493e835153b1bc3927a6dea3d51b7d5d2f9d4d16e6ee6084` |
| Review9 merged config | `ce3235cba604521c4b0bc1ce639278e70d612b0e76fa464aee9fd8592f60106c` |
| Review9 reproducible kernel Image | `2027d41c9d34658d44aba3d6497592f470bb0ffe3abc70712f20fd246afe093d` |
| Review9 vmlinux | `eff87c55a359dde9abceaf9dcfbad6874db1d54bc19c1ee3d111e4d3e1463302` |
| Review9 OLED DTB | `4caa12c8154470ea484890933f7997ec8e9a95b064927e0c2c8b814f9f658b3a` |
| Review9 module manifest | `837037c94f02312080ce9873cb37aef07478b9bd5200d99d5834c9bf06375cbc` |
| Review9 qcom_battmgr module | `79885843e52a40418bf22b00536e14bb248d2c94f43812a11c70f95d6b131483` |

These hashes identify the clean review4 hardware-test artifact and the two
byte-identical corrected review5 builds completed on 2026-07-19, and two
byte-identical review6 builds completed on 2026-07-21, and two byte-identical
review7 builds completed from its source tip. Review6 hardware testing exposed
the reattach gap, and review7 exposed transient raw state zero. Review8 passed
live-module reattach testing, its two clean builds are byte-identical, and its
exact-artifact boot and attached/detached hardware matrix passed. These are
validation evidence, not distributed binaries or binary publication approval.
Review9 likewise has two byte-identical clean builds; its exact-artifact boot,
complete practical hardware matrix, charge-window readback, and persistent
default promotion passed. A controlled charger protection-domain restart was
unavailable because retail firmware rejected it as disabled before any state
transition. A future payload and its complete corresponding-source archive
will receive separate identities after testing.
