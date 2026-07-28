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
- the logind watchdog override used during long lid-suspend qualification;
- an mkinitcpio drop-in that loads the X1E VideoCC provider before the root
  filesystem is mounted.

The guard content SHA-256 is
`31af7630b55313ef82cda79c0c1669a3a94cea5ac71e4857cd37fe3b4cb0869a`.
The systemd suspend drop-in SHA-256 is
`a2b708ccb9d61669ddfebb6be8bdcc0e54ec0717e697f8f6894f5a64436ce847`.
The VideoCC drop-in SHA-256 is
`274f034664f810d666194af6682f652537323444ca61b70d0f70768c34bb27cb`.

The qualified host previously supplied `videocc-sm8550.ko` as an external
exact-ABI diagnostic module and forced it into a special initramfs. That was a
reproducibility gap: the provider is required for the clock framework to
complete its normal `sync_state()` pass, but the published configuration had
`CONFIG_SM_VIDEOCC_8550` disabled. The corrected candidate builds it in-tree
as a module, forces it into every generated initramfs, and makes the installer
reject an initramfs that omits it. The resulting module is byte-identical to
the qualified external module, SHA-256
`ca449eebd9520ff44473302755fe8760cc11341928db8be6dbf8b2cc5f5957e8`.

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

## Reproducible candidate

Two independent builds from empty output directories completed with Clang and
LLD 22.1.8, Python 3.14.6, and lxml 6.1.1. Both used the pinned identity
`sp11@reproducible #1`, source timestamp `2026-07-26T14:35:25Z`, exact commit
`18d7951a10dc49e383d16c6af82fc2c07784de3d`, and exact tree
`b820f10abba096e23a28506d7ad591dffdedf1a8`.

The corrected builds are byte-identical across `Image`, `vmlinux`, OLED DTB,
`.config`, `Module.symvers`, `System.map`, module indexes, generated
build-identity files, and the relative paths and contents of all 3,759 in-tree
modules:

| Artifact | SHA-256 |
| --- | --- |
| Clean candidate Image | `918ed2560654355555535290fd0d9657e1afc7022b3e46cc8396155d3575f256` |
| OLED DTB | `5e9009f5bd96a760a33086d1a8842e3228e3d28c413f96d70aca4914f7e397ed` |
| Configuration | `c68c4b072713503c8282cb09ff8f05aa4876966503c65331732bfe0775196c52` |
| `Module.symvers` | `b58de2ebd5ca9649b0e7299e4b5b7e3965f70e06506b88c1ec3d5046ce2e9387` |
| `vmlinux` | `90908d0308d237da3035702b1919cd8c044988b9031cb3e1b1847e829cc631a6` |
| `System.map` | `6e83a803f5d8ce698b7372d07b35cd1d591f92db9ce373c76251336d4c261807` |
| Normalized module manifest | `82a376eecf320b7182ae94ff1b1acc0bf854b203727b903a1f97cab26d5ed637` |
| `videocc-sm8550.ko` | `ca449eebd9520ff44473302755fe8760cc11341928db8be6dbf8b2cc5f5957e8` |

The corrected clean Image intentionally differs from the historical locally
qualified Image in both reproducible UTS build metadata and configuration
metadata for the newly in-tree VideoCC module. The superseded candidate's
122-byte metadata-only comparison therefore does not apply. The source tree,
OLED DTB, and module ABI are unchanged, and the newly in-tree provider exactly
matches the qualified provider binary.

The exact candidate is staged at
`out/stage/beta-review20-videocc-clean-20260727`. Its 3,759 installed modules
match build A byte-for-byte, report only
`7.1.3-sp11-suspend-review20 SMP preempt mod_unload aarch64`, and reproduce the
normalized module-manifest hash above. The 244 MiB stage has complete depmod
indexes, no symlinks, special files, unsafe paths, or host paths, and resolves
`videocc_sm8550` to the expected in-tree module.

A separate base-hook packaging probe used that staged module root and the
shipped mkinitcpio drop-in. `lsinitcpio` confirmed
`usr/lib/modules/7.1.3-sp11-suspend-review20/kernel/drivers/clk/qcom/videocc-sm8550.ko`
inside the generated image. The probe is not a production initramfs and is not
part of the candidate stage.

A full one-shot initramfs was then generated from the candidate stage with the
qualified host's complete hook and early-module set plus `videocc_sm8550`. Its
content path set matches the qualified review20 initramfs except that the same
VideoCC binary moves from `updates/diagnostic/` to the in-tree
`kernel/drivers/clk/qcom/` path. The full image is
`out/probes/review20-videocc-full-initramfs-20260727.img`, SHA-256
`e28cf33f869c8ae6106619c8ebb2eaa88b89f2e23b231817687e2ce14f855636`.
It was installed under a unique boot path for target qualification.

## Target-hardware qualification

On 2026-07-28, the candidate booted once without changing the persistent
review20 fallback. It reported the exact pinned identity
`sp11@reproducible #1 SMP PREEMPT_DYNAMIC 2026-07-26T14:35:25Z`; its Image,
OLED DTB, and initramfs matched the recorded hashes; GRUB consumed the
one-shot; and pstore remained empty. The in-tree VideoCC module loaded from
the standard initramfs path, matched the qualified module byte-for-byte, and
bound to `aaf0000.clock-controller`. Runtime PSCI state1 accumulated residency
on all 12 CPUs.

The first candidate deep-suspend test completed the PSCI syscore
suspend/resume path, powered down CPUs 1--11, suspended and resumed both
VideoCC power domains, and woke from the power button on IRQ 216. Touchscreen,
keyboard, touchpad, audio, front camera, and rear camera passed both before
and after resume. The local pre/post evidence files have SHA-256
`cfa97764b1a2cf1c2f85e0fdf6749d7b146869c014cc1c327056b7c9faa40fb6`
and
`bb8b9a7e9d9fbad4d794622669b069ecc93cd86ae199748675e0c80ce91db1be`.

The clean Image hash is therefore promoted into the payload assembler,
installer, and verifier.

After successful qualification, the host persistent default was promoted to
`sp11-beta-review20-videocc-qualified-20260728`. The historical guarded
review20 entry and review12 entries remain available as fallbacks, the Windows
Boot Manager chainloader remains present, and the one-shot GRUB environment
was empty. Dated copies of the previous default and generated GRUB
configuration were retained before promotion.

## Held payload staging

The assembler now requires an explicit audited kernel stage. It no longer
copies the old host boot directory or archives the live `/usr/lib/modules`
tree. It verifies the promoted Image, OLED DTB, in-tree VideoCC module, all
three qualified userspace binaries, exactly 3,759 kernel modules, and the
absence of stage symlinks and special files before producing normalized
archives.

Two independent held local assemblies on 2026-07-28 produced a byte-identical
archive, SHA-256
`d6192f47672772adf781170743427141f65beb88d6c2abb47703118108f59679`.
Both archive layers passed hash, relative-path, symlink, and special-file
checks. The module archive contains exactly 3,759 modules, has VideoCC only at
the standard in-tree path, and contains no external diagnostic VideoCC,
`v4l2loopback`, or `sp11_genpd_sync_release` module. The archive includes
`LOCAL-STAGING-NOT-FOR-RELEASE`; it is ignored local engineering output, not a
release candidate.

The next gate is complete corresponding-source and license staging for every
binary before any releasable payload is assembled.

## Custom-payload corresponding source

The three qualified userspace binaries were reconstructed from the pinned
source and documented build environment on 2026-07-28. iptsd and
`iptsd-check-device` reproduced byte-for-byte after pinning Meson's fmt 12.0.0
fallback, disabling LTO and warnings-as-errors, and using the recorded
source/build directory names. Patched Power Profiles Daemon 0.30 likewise
reproduced byte-for-byte from peeled tag commit
`5b4994c8a91290481bef87a5bae95391d0ec677f` and the published patch. A PPD
rebuild under another directory differed only in debug-path strings and the
derived build ID.

The source assembler packages:

- the complete exact review20 kernel tree, release config, `Module.symvers`,
  BUILDINFO, build helper, cumulative patch, and incremental bundle;
- the complete exact iptsd tree plus CLI11 2.6.1, Eigen 5.0.1, fmt 12.0.0,
  Microsoft GSL 4.2.0, spdlog 1.15.3, their wrap metadata, cached source
  archives, and license files;
- the complete patched PPD 0.30 tree, patch, license, and exact build recipe.

Two independent assemblies produced a byte-identical complete-source archive,
SHA-256
`521e99ff30d32c4be2d14aa99de05d4839e3dae8f570d87a5bfc8e7e5ac534ee`.
The outer and nested checksums pass. Its 99,867 kernel, 2,985 iptsd/dependency,
and 71 PPD members have safe relative paths and the required license files.
All 99 upstream kernel symlinks resolve within the kernel source root; the
other source archives contain no symlinks.

This closes corresponding source for the custom held payload only. The live
ISO's future distribution-package manifest and matching package sources remain
a separate gate.

`BINARY-RELEASE-HOLD.md` remains active throughout this work.
