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
- IMX681 tuning YAML: `CC0-1.0`.
- Generated build identity and symbol data: `CC0-1.0` where marked.

Canonical license texts live in `LICENSES/`. File-level assignments are
recorded in SPDX headers or `REUSE.toml`; run `reuse lint` before release.
