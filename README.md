# Linux for the Surface Pro 11 (Snapdragon X Elite) — public beta

> Experimental. For people who can use a terminal, keep backups, and recover
> a tablet that does not boot. Read [RELEASE-STATUS.md](RELEASE-STATUS.md)
> and [KNOWN-ISSUES.md](KNOWN-ISSUES.md) before flashing anything.

This repository is the source, tooling, and documentation behind a live and
installer ISO for the Microsoft Surface Pro 11 OLED with Snapdragon X Elite
(`microsoft,denali`). On the tested unit the following work: OLED display,
touch, pen (through iptsd), attached and Bluetooth Flex Keyboard and haptic
touchpad, Wi-Fi, Bluetooth, speakers, microphones, front/rear cameras, IR
camera, volume buttons, battery charge limit, ambient colour sensor, power
profiles, and suspend/resume (s2idle, with the documented CPU-idle
mitigation).

## Try it

1. Download the ISO from the releases page and write it to a USB stick.
2. In Windows, open the stick's `SP11FW` drive and run `RUN-IN-WINDOWS.cmd`.
   It copies five firmware files (audio/compute DSP, GPU) from your own
   Windows installation onto the stick; they cannot be shipped in the ISO.
3. Disable Secure Boot, boot the stick (Volume-Down + Power), test.
4. Optionally run **Install SP11 Linux** for dual boot or a full wipe.

Full walkthrough: **[docs/GETTING-STARTED.md](docs/GETTING-STARTED.md)**.
Firmware details and alternatives: [docs/FIRMWARE.md](docs/FIRMWARE.md).
Removing it again: [docs/UNINSTALL.md](docs/UNINSTALL.md).

## What is in the box

- Kernel `7.1.3-sp11-suspend-review20`: upstream Linux 7.1.3 plus the
  patches in `kernel/` (camera, touch, tablet mode, DP DDC, charge limit,
  suspend/idle work). Reproducible builds; see `docs/BUILD.md`.
- Arch Linux ARM package set (GNOME 50, PipeWire, libcamera, NetworkManager,
  Rnote, Firefox, …) pinned in `iso/packages.lock.tsv`.
- `rootfs/`: the services and helpers that make the hardware behave (iptsd
  lifecycle, charge limit, power profiles, Bluetooth address, deep-idle
  mitigation, …).
- `scripts/`: firmware collectors (`sp11-collect-firmware.ps1`,
  `sp11-firmware.py`), the installer (`sp11-install-plan.py`,
  `sp11-install-executor.py`, `sp11-installer-ui.py`), the live-image builder
  and audits, and the overlay installer for existing Arch Linux ARM systems.
- Only redistributable firmware (`firmware/allowlist.tsv`). No Windows
  driver files, traces, or private data are tracked.

## Foundation and credit

The Arch Linux ARM bootstrap, firmware workflow, and early SP11 enablement
come from [dwhinham/linux-surface-pro-11](https://github.com/dwhinham/linux-surface-pro-11).
The kernel work incorporates GPL-licensed work from Linux contributors, Dale
Whinham, Bryan O'Donoghue and Linaro, Qualcomm, and STMicroelectronics;
authorship and provenance are preserved in [NOTICE.md](NOTICE.md),
[docs/PROVENANCE.md](docs/PROVENANCE.md), and [docs/CAMERA-REVIEW.md](docs/CAMERA-REVIEW.md).
AI tools materially assisted development and validation
([docs/AI-ASSISTANCE.md](docs/AI-ASSISTANCE.md)).

## Licensing

Aggregate: the MIT licence covers the project's own scripts and
documentation; kernel material keeps GPL-2.0 and per-file licences, libcamera
changes LGPL/CC0, the Power Profiles Daemon patch GPL-3.0. See
[docs/LICENSING.md](docs/LICENSING.md) and the REUSE metadata.

## Tested target

- Microsoft Surface Pro, 11th Edition, OLED, Snapdragon X Elite (X1E80100)
- One physical unit. The LCD, X Plus, 5G, and Surface Laptop variants are
  **not supported** (different hardware, not just untested);
  see [SUPPORTED-HARDWARE.md](SUPPORTED-HARDWARE.md).

## Contributing and reporting

Open issues with the diagnostics report from
`sp11-live-firstboot-capture.sh` (review it first: it contains device
identifiers). Read [CONTRIBUTING.md](CONTRIBUTING.md) for the privacy and
provenance boundary; never attach firmware packs or Windows driver files.

Microsoft and Surface are names used only to identify compatible hardware.
This project is not affiliated with or endorsed by Microsoft, Qualcomm,
Linaro, STMicroelectronics, or the Linux kernel project.
