# SP11 beta firmware boundary

No firmware blob is tracked in this source repository. This directory defines
the only firmware files that a future beta image assembler may select from
verified distribution packages.

## Allowlist policy

`allowlist.tsv` is fail-closed. Every entry records the exact relative
firmware path, source package/version, uncompressed size, SHA-256, required
license/notice material, and purpose. An image assembler must:

1. acquire the exact signed package in `packages.lock.tsv`;
2. verify the package signature and package SHA-256;
3. extract only paths in `allowlist.tsv`;
4. verify every extracted file's size and SHA-256;
5. include the named license and notice files plus the exact `WHENCE`; and
6. reject any extra firmware file, symlink, special file, or unsafe path.

The Linux firmware source is tag `20260622`, commit
`b2722d241309a1872446c1d00c2e812bad055f89`. Its `WHENCE` explicitly calls
the selected Qualcomm/Atheros files redistributable under the named terms.
The signed wireless regulatory database comes from the separately locked
`wireless-regdb` package.

## Surface-specific external prerequisite

The qualified host loads Surface-specific ADSP and CDSP files that are
unowned by any distribution package. It also has an unowned Surface audio
topology and an unowned ath12k `board.bin`. Their hashes are documented in
`denylist.tsv` only to recognize and reject them; the hashes do not grant
redistribution rights.

As of upstream linux-firmware commit
`543b8f5f987c4da3f21550cf4827c69276986fbb`, none of those six
Surface-specific files is present in the official tree or `WHENCE`. They must
not be copied from this machine, a Windows partition, a Microsoft driver
package, or another installation into a published image.

Consequences for beta 1:

- display/GPU, QUPv3 serial devices, Bluetooth, regulatory data, and the
  official WCN7850 firmware may be included from the allowlist;
- audio and the ADSP/CDSP-dependent sensor path are unavailable in a pristine
  live boot unless the operator supplies compatible firmware locally;
- installation may offer an explicit, local-only import from an existing
  Linux installation or user-supplied source, but it must show the exact files
  and hashes and must not upload, bundle, or publish them; and
- the official ath12k `board-2.bin` path must pass an on-device test with the
  unowned fallback `board.bin` absent before Wi-Fi is claimed for the exact
  ISO.

The installer must continue without the denied files and clearly report the
resulting hardware limitations. Missing external firmware is not permission
to fetch a Windows package automatically.
