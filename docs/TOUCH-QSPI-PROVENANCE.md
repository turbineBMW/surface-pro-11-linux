# Touch and QSPI development provenance

Date recorded: 2026-07-19

This record describes the development inputs for the Surface Pro 11 touch and
QSPI implementation. It is an engineering provenance statement, not a legal
opinion.

## Author declaration

The author reports that the SP11-specific implementation was developed on a
personally controlled Surface Pro 11 using its licensed Windows installation.
The author had no Microsoft or Qualcomm source-code access, confidential
documentation, NDA, vendor portal, or other proprietary access.

Installed Windows driver packages were retained as private research inputs and
used to identify the components and runtime activity to observe. The technical
behavior supplied to the implementation process came from WinDbg runtime
traces. The author reports no use of decompiled source, disassembly-derived
pseudocode, leaked source, or restricted vendor documentation.

AI coding assistants helped interpret the runtime observations and write Linux
code. That assistance does not replace source attribution: published third-
party code remains credited to its human authors, and the SP11-specific code is
recorded as the author's independent interoperability implementation.

## Permitted and published inputs

- Linux stable `v7.1.3` and the licenses and notices contained in that tree;
- the GPL-licensed HID-over-SPI commits by Jingyuan Liang, Jarrett Schultz, and
  Angela Czubak, including the reviews and sign-offs recorded in their commit
  messages;
- Microsoft's publicly published HID over SPI Protocol Specification 1.0;
- public Linux device-tree, SPI, Qualcomm GENI, and GPI implementations;
- ACPI and device information exposed by the author's own hardware; and
- runtime register, DMA, packet, interrupt, and timing behavior observed with
  WinDbg on that hardware.

## SP11-specific observations

The independently written Linux implementation uses functional observations
including the paired QSPI channel assignment, transfer-ring sizing, adjacent
FIFO writes, initial watermark servicing, and device power-on timing. These are
documented in the public source as technical controller requirements rather
than as reproductions of another driver's source expression.

## Material excluded from the release

The public release does not contain Windows driver packages, Windows binaries,
firmware extracted from Windows, memory dumps, WinDbg logs, decompiler output,
disassembly, proprietary source, or restricted documentation.

The private development history contained a bounded descriptor-only bring-up
mode. That mode included device-specific packet expectations, report metadata,
and a report-descriptor checksum used to validate runtime captures. It was not
required by the working configuration and has been removed from both the final
source tree and the distributed Git object history.

The full private research history and input inventory are retained privately as
development evidence. The public kernel history is deliberately curated: it
preserves the original HID-over-SPI authorship and then records the reviewed
SP11 end state without the diagnostic-only experiments.

## Distribution boundary

Only independently written Linux source, openly licensed upstream work, and
the documentation needed to reproduce the Linux build may be distributed.
Private Windows files and research traces must not be added to Git history,
source archives, release assets, issue attachments, or build logs.
