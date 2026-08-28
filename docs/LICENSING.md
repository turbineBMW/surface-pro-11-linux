# Licensing map

This repository is an aggregate of patches and integration material for
several upstream projects. Original scripts and documentation are licensed
under the top-level MIT license. The top-level license does not replace or
override the terms of imported or modified upstream work.

The public source preview contains no prebuilt kernel, module, userspace
executable, firmware, payload, disk image, or ISO. A future binary release must
be accompanied by complete corresponding source and the applicable license and
copyright material tracked in `docs/REDISTRIBUTION-REVIEW.md`.

- Linux kernel patch and bundle: the per-file Linux licenses represented by
  `GPL-2.0-only`, `BSD-2-Clause`, and `BSD-3-Clause`; the bundle preserves
  individual SPDX identifiers, copyrights, authors, and commit metadata.
- iptsd: `GPL-2.0-only`.
- libcamera patches: `LGPL-2.1-or-later`, with the original tuning data also
  available under `CC0-1.0`.
- Power Profiles Daemon patch: `GPL-3.0-only`.
- hexagonrpc and libssc patches: `GPL-3.0-or-later`.
- Bounded SP11 IR bridge, service integration, tests, and documentation:
  original project work under `MIT`.
- Howdy itself, if obtained separately: upstream `MIT`; it is not included in
  this repository and its license does not cover v4l2loopback, kernel code, or
  other dependencies.
- IMX681 tuning YAML: `CC0-1.0`.
- Generated build identity and symbol data: `CC0-1.0` where marked.
- SP11 AudioReach topology source: `BSD-3-Clause`; its generated topology
  binary carries the same terms. The project-authored ALSA UCM routing is
  `MIT`.

The original sensor systemd units, developer installer, and documentation are
MIT-licensed. Microsoft/Qualcomm sensor configuration and generated
persistence and the five files in `firmware/external-required.tsv` are
owner-supplied external prerequisites and are not distributed.

The qualified WCN7850 `board.bin` is an unmodified record extracted from the
redistributable `board-2.bin` in the locked `linux-firmware-atheros` package.
Its exact source record and output identity are recorded in
`firmware/derived.tsv`; the Qualcomm firmware license and notices accompany
the binary.

Canonical license texts live in `LICENSES/`. File-level assignments are
recorded in SPDX headers or `REUSE.toml`; run `reuse lint` before release.
