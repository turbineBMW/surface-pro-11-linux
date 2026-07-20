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
- Tested release string: `7.1.3-sp11-camera-review4`
- Delta: 12 sanitized commits followed by 13 reviewed camera commits

`kernel/sp11-sanitized2.bundle` preserves the exact incremental
history and requires the Linux base commit. The cumulative patch reproduces
the final source tree but not commit metadata.

`kernel/sp11-camera-review.bundle` adds the reviewed camera source on top of
that exact sanitized tip. Its cumulative patch reproduces the camera tree from
the sanitized prerequisite. Both histories are incremental and contain source,
not a prebuilt kernel or module payload.

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

## Generated artifact hashes

| Artifact | SHA-256 |
| --- | --- |
| Sanitized cumulative patch | `218ee1ec59a29887aab919fcd37c7d8a21f7ca421ea3757476ddbab76bf07914` |
| Sanitized Git bundle | `cd782a17f4c6645d63d51c057bc9115ac0b7167966a6ce8c663c6e351b79d3e7` |
| Kernel config | `8834ac6021bc4d50034b55c0960938070541387c0984aed4cc6797601ecce7f1` |
| Module.symvers | `b58de2ebd5ca9649b0e7299e4b5b7e3965f70e06506b88c1ec3d5046ce2e9387` |
| Review4 merged config | `b2497f1a5340c6491dd86014d90a9cdd6dcf0a8b1f45806ceb76be35d972517f` |
| Review4 kernel Image | `9fcc24f29713663fdc89a16b5c3dfd097cc03fa91b3cf5b1a7e3e29a403a1338` |
| Review4 OLED DTB | `4caa12c8154470ea484890933f7997ec8e9a95b064927e0c2c8b814f9f658b3a` |

These Image and DTB hashes identify the clean review4 build completed on
2026-07-19. They are validation evidence, not distributed binaries or binary
publication approval. A future payload and its complete corresponding-source
archive will receive separate identities after testing.
