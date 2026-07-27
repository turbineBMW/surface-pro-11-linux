# Review20 release consolidation

## Frozen identity

The local integration ref `integration/beta-review20` freezes the exact kernel
source used by the qualified review20 Image:

| Item | Identity |
| --- | --- |
| Base public review12 | `a3e71f7080ee40dccfdd9500b8957a7c143fb6a2` |
| Qualified review20 commit | `18d7951a10dc49e383d16c6af82fc2c07784de3d` |
| Qualified review20 tree | `b820f10abba096e23a28506d7ad591dffdedf1a8` |
| Integration ref | `integration/beta-review20` |
| Additional commits | 20 |
| Qualified Image | `b3ca9ba56570ff1bf8217a866563f1e9788c5dfdc3a153a9b673e3b6e9624ed5` |
| Qualified OLED DTB | `5e9009f5bd96a760a33086d1a8842e3228e3d28c413f96d70aca4914f7e397ed` |

The ref and qualified commit resolve to the same tree. It is a local recovery
and reproducibility anchor, not yet a published source bundle.

## Commit classification

The 20-commit delta contains:

- four preparatory qcom-pdc commits authored by Mukesh Ojha;
- the seven-patch Hamoa PDC/deep-idle v4 series authored by Maulik Shah,
  Sneh Mankad, and Stephan Gerhold;
- nine local integration and diagnostic commits.

The imported commits preserve their authorship, copyright context, review
trailers, and sign-offs. The primary deepest-idle posting and review thread
are:

- <https://lkml.iu.edu/hypermail/linux/kernel/2603.1/09605.html>
- <https://lkml.org/lkml/2026/3/13/1521>
- <https://lkml.iu.edu/2603.1/11924.html>

The related earlier RSC sleep/wake vote-flush fix is:

- <https://lkml.iu.edu/hypermail/linux/kernel/2401.0/00883.html>

The local commits divide into release behavior and retained diagnostics:

| Commit | Purpose | Initial beta disposition |
| --- | --- | --- |
| `b876b8111695` | Denali runtime-state1 opt-in | Required |
| `81d01fe5d5be` | s2idle-only experimental path | Retain for exact-tree beta; unused |
| `89a328dd7dba` | report selected PDC mode | Retain; diagnostic log only |
| `53dc1d07fcda` | preserve driver veto for s2idle-only states | Retain with its paired path |
| `a481fb41b90c` | kernel-doc correction | Retain |
| `b7ea57b19e1a` | reset SMP2P inbound cache only on restart | Required |
| `8fec8ad7374a` | optional IPCC suspend mask | Required by qualified command line |
| `21bf647eff0b` | dynamic-debug RPMh cache trace | Retain; inert unless enabled |
| `18d7951a10dc` | remove QCE's inappropriate sleep vote | Required |

Removing the unused diagnostic interfaces would produce a different Image.
For the first beta, preserving the exact qualified tree is lower risk.
Cleanup can happen in a later candidate followed by the full hardware and
suspend qualification again.

Seven local commits do not contain `Signed-off-by` trailers. This project does
not represent AI-assisted work as having a human DCO certification. Before
any upstream submission, the human maintainer must review those changes and
make their own intentional certification. Source publication under the
project's existing provenance policy does not claim upstream acceptance.

## Userspace safety configuration

The public beta branch now contains the exact qualified runtime-idle guard:

```text
rootfs/usr/local/libexec/sp11-runtime-idle-suspend-guard
rootfs/etc/systemd/system/systemd-suspend.service.d/10-sp11-runtime-idle-guard.conf
```

It also contains:

- the conservative state1-disabled fallback when `sp11_deep_idle=1` is absent;
- the logind watchdog override used during long lid-suspend qualification.

The guard content SHA-256 is
`31af7630b55313ef82cda79c0c1669a3a94cea5ac71e4857cd37fe3b4cb0869a`.
The systemd suspend drop-in SHA-256 is
`a2b708ccb9d61669ddfebb6be8bdcc0e54ec0717e697f8f6894f5a64436ce847`.

## Source artifact staging

The source-content gate completed on the frozen ref:

- changed paths are limited to 11 relevant kernel source, documentation, and
  device-tree files;
- no binary diff is present;
- the patch contains no private path, host identity, credential, proprietary
  marker, or withdrawn implementation marker;
- imported authorship and sign-off trailers are preserved;
- the only checkpatch findings are the recorded missing human sign-offs and
  commit-message wrapping/description issues in seven local commits;
- no code-style checkpatch error was found.

The mechanically generated artifacts are:

| Artifact | SHA-256 |
| --- | --- |
| `kernel/sp11-suspend-review20.patch` | `855eb015df2fa1af281f531e401cb419101ef950738e4d27042f360ebf3d9b04` |
| `kernel/sp11-suspend-review20.bundle` | `0c078953e0f827a1b3fd126e818debce17fe851452d61f0e8758dd4e4b521385` |

The patch has 20 mail messages and 25 file diffs. The bundle has one head,
`integration/beta-review20`, and requires exact public review12. Their hashes,
structure, expected tip, single-head property, and blocked-material scans are
now enforced by `scripts/audit-release.sh`.

## Next source gate

1. reconstruct the tree from a clean Linux `v7.1.3` clone and every published
   incremental bundle;
2. hardware-test the clean reconstructed Image, then finish a second clean
   build and prove the two clean outputs are byte-identical;
3. promote the clean Image hash into the installer only after that hardware
   test;
4. assemble and audit the exact payload.

The first clean build matches the qualified source, configuration,
`Module.symvers`, OLED DTB, and all 3,758 in-tree modules. Its Image differs
from the installed qualified Image in 122 bytes because the qualification
build used a different UTS build timestamp and an empty build-number field.
The clean candidate deliberately uses the pinned source timestamp and build
number `1`; it therefore needs a one-shot hardware test before promotion.

`BINARY-RELEASE-HOLD.md` remains active throughout this work.
