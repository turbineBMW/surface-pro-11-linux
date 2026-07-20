# Credits and third-party notices

The sanitized Surface Pro 11 candidate is possible because of work from the
following projects and contributors. This summary supplements, and does not
replace, copyright notices, SPDX identifiers, commit authorship, or license
texts in the source artifacts.

- The Linux kernel community and Linux stable maintainers provide the
  `v7.1.3` base.
- Dale Whinham (`dwhinham`) provides the foundational Surface Pro 11 Arch Linux
  ARM bootstrap, firmware workflow, and early hardware-enablement work in
  `dwhinham/linux-surface-pro-11`.
- Jingyuan Liang, Jarrett Schultz, and Angela Czubak authored the HID-over-SPI
  commits preserved in the sanitized kernel history; Dmitry Antipov and the
  other reviewers and signers remain credited in the individual commits.
- Microsoft published the HID over SPI Protocol Specification 1.0 used by that
  driver work.
- The SP11-specific touch/QSPI implementation was independently written from
  public specifications, GPL-licensed Linux code, ACPI/device information, and
  runtime behavior observed on the author's own hardware. See
  `docs/TOUCH-QSPI-PROVENANCE.md` for the development-input boundary.
- The Linux Surface community provides iptsd, used unmodified from the pinned
  `linux-surface/iptsd` source commit.
- The libcamera project provides the LGPL-licensed codebase targeted by the
  optional IMX681 userspace patches.
- The Power Profiles Daemon project provides the GPL-licensed daemon targeted
  by the SP11 platform-profile patch.
- Qualcomm Innovation Center copyright and license notices remain in the Linux
  device-tree and Qualcomm driver files inherited from upstream Linux.
- Bryan O'Donoghue and Linaro's X1E80100 CAMSS binding work is credited in the
  reviewed camera branch and its in-tree provenance record.
- STMicroelectronics provides the GPL-licensed VD55G0 driver and sensor patch
  arrays pinned by the reviewed camera branch.
- Dale Whinham authored the ath12k `disable-rfkill` change carried with his
  original authorship and Signed-off-by trailer.

The camera-free sanitized branch remains the prerequisite for the separate,
reviewed camera branch. That camera branch uses attributed Qualcomm and ST GPL
material plus independently written Linux code derived from runtime hardware
observations. Aleksandrs
Vinarskis's Zenbook A14 work informed the withdrawn research line but was not
copied into the reviewed branch. Acknowledgement alone is not redistribution
permission; exact classifications and source boundaries are recorded below.

Exact source URLs, commit identities, classifications, and release obligations
are recorded in `docs/PROVENANCE.md`, `docs/REDISTRIBUTION-REVIEW.md`, and
`docs/LICENSING.md`.
