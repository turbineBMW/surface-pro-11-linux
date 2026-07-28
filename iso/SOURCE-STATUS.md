# Distribution source staging status

The exact distribution-package source closure remains an active release hold.
The binary packages are fully pinned and verified, but the authoritative Arch
Linux ARM source and change endpoints have returned HTTP 500 since at least
2024 and still failed on 2026-07-28:

- `https://archlinuxarm.org/packages/aarch64/acl/files`
- `https://archlinuxarm.org/packages/aarch64/acl/log`

Arch Linux ARM's public repository states that it contains recipes modified
from Arch upstream, while unmodified recipes should be obtained from Arch
Linux. Its project forum gives the same routing guidance:

- `https://github.com/archlinuxarm/PKGBUILDs`
- `https://archlinuxarm.org/forum/viewtopic.php?t=15900`
- `https://archlinuxarm.org/forum/viewtopic.php?t=17169`

That routing is necessary but not yet sufficient to prove the exact build
input. A concrete sample demonstrates the gap:

- Arch Linux ARM's signed `acl 2.4.0-1` aarch64 `.BUILDINFO` records
  `pkgbuild_sha256sum`
  `a4e556c0a43fc27000ef25bdcf7d7bf5c700eb7145e6c9c84f170b3621f67927`;
- the immutable Arch Linux `2.4.0-1` packaging tag points to commit
  `2dabdf495db1ea7eec4a94da43a22b917c19bce3`;
- that tag's `PKGBUILD` SHA-256 is
  `187dc04af82d474c038ce266bf3912dc0acd3240860e8e1a0b96e41755dd51b7`;
  and
- the latter hash matches Arch Linux's own signed x86_64 package, but not the
  Arch Linux ARM package.

The held image therefore does not claim that the canonical Arch tag is the
exact ARM recipe. Before release, all 595 recipe identities must be recovered
from authoritative history or a restored Arch Linux ARM export, matched to
the hashes in `package-recipes.lock.tsv`, and paired with every local patch,
upstream source, license, and source-to-binary association.

This unresolved provenance gap does not prevent local boot engineering. It
does prevent publication of the ISO and is one reason
`BINARY-RELEASE-HOLD.md` remains active.
