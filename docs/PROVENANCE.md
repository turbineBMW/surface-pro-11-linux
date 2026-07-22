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
- Candidate release string: `7.1.3-sp11-camera-review5`
- Delta: 12 sanitized commits, 13 reviewed camera commits, and one corrective
  touch-driver commit

`kernel/sp11-sanitized2.bundle` preserves the exact incremental
history and requires the Linux base commit. The cumulative patch reproduces
the final source tree but not commit metadata.

`kernel/sp11-camera-review.bundle` adds the reviewed camera source on top of
that exact sanitized tip. Its cumulative patch reproduces the camera tree from
the sanitized prerequisite. `kernel/sp11-touch-spi-autoload.bundle` adds the
single modalias correction on top of the camera tip. All histories are
incremental and contain source, not a prebuilt kernel or module payload.

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
| Kernel config | `8834ac6021bc4d50034b55c0960938070541387c0984aed4cc6797601ecce7f1` |
| Module.symvers | `b58de2ebd5ca9649b0e7299e4b5b7e3965f70e06506b88c1ec3d5046ce2e9387` |
| Review4 merged config | `b2497f1a5340c6491dd86014d90a9cdd6dcf0a8b1f45806ceb76be35d972517f` |
| Review4 kernel Image | `9fcc24f29713663fdc89a16b5c3dfd097cc03fa91b3cf5b1a7e3e29a403a1338` |
| Review4 OLED DTB | `4caa12c8154470ea484890933f7997ec8e9a95b064927e0c2c8b814f9f658b3a` |
| Review5 merged config | `b2497f1a5340c6491dd86014d90a9cdd6dcf0a8b1f45806ceb76be35d972517f` |
| Review5 reproducible kernel Image | `39027932868b113b3068713dffd8b97168187a69547065ee4e77e7a136e79b97` |
| Review5 OLED DTB | `4caa12c8154470ea484890933f7997ec8e9a95b064927e0c2c8b814f9f658b3a` |
| Review5 module manifest | `337ddc859f8b932d78e316f6935b293e97472afb2d6373333f14058894902c2d` |

These hashes identify the clean review4 hardware-test artifact and the two
byte-identical corrected review5 builds completed on 2026-07-19. They are
validation evidence, not distributed binaries or binary publication approval.
A future payload and its complete corresponding-source archive will receive
separate identities after testing.
