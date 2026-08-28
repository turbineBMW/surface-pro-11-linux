# Fresh-machine installer contract

Status: design, read-only planner, unprivileged interactive planning preview,
reproducible held installed-system root artifact, and a full loop-only
install/verify/removal executor are implemented. The preview desktop entry is
staged but disconnected. No physical-disk executor is authorized or embedded
in the held live image.

## Product boundary

The existing `install.sh` is an overlay transaction for an already installed,
known-good Arch Linux system. It is not a fresh-machine installer and must not
be exposed as one.

The fresh installer will have four separately testable layers:

1. a read-only inventory and planner running as the live user;
2. an interactive terminal UI that explains and confirms the immutable plan;
3. a minimal privileged executor that accepts only a current, signed/hashed
   plan and performs the listed operations; and
4. an installed-system verifier and partition-aware removal workflow.

Until all four layers pass disposable-disk and physical qualification, the live
image may show planning information but must not offer an install action.

The first implementation of layer 2 now exists as
`scripts/sp11-installer-ui.py`. It calls only the read-only planner, explains
the Windows-first shrink workflow, shows dual-boot and wipe consequences, and
saves a non-executable plan only after an exact `SAVE` response. The staged
GNOME entry is not consumed by the live-image builder.

## Dual boot

Dual boot is the recommended path.

The user must first use Windows Disk Management to shrink the Windows volume
and leave the result unallocated. Windows documents that shrinking creates
adjacent unallocated space without reformatting the volume:
<https://learn.microsoft.com/en-ie/windows-server/storage/disk-management/shrink-a-basic-volume>.

The installer will never resize, move, unlock, repair, or format NTFS,
BitLocker, Microsoft Reserved, Windows Recovery, or the existing Windows EFI
System Partition. It accepts only an already unallocated, aligned extent
immediately after the Microsoft basic-data partition and before the Windows
Recovery partition.

Inside that extent it plans:

- a new 1 GiB FAT32 EFI System Partition owned by this Linux installation; and
- one ext4 Linux root partition consuming the remaining aligned space.

The dedicated Linux ESP keeps Linux boot files and rollback ownership separate
from Windows. The installer must still mount the Windows ESP read-only and
verify `EFI/Microsoft/Boot/bootmgfw.efi` before any mutation.

Minimum unallocated space is 33 GiB: 1 GiB ESP plus 32 GiB root. A larger root
is strongly recommended.

## Wipe and install

Wipe mode is a separate plan, never a fallback from dual boot. It is forbidden
for removable, hot-plug, USB, read-only, serial-less, mounted, or ambiguous
devices.

Before execution the UI must display the exact model, serial, size, and current
partition list. The user must type:

```text
ERASE <physical-disk-serial>
```

and accept a second confirmation that Windows, recovery partitions, and all
data will be unrecoverable from that disk. Wipe mode creates a new GPT, a 1 GiB
Linux ESP, and an ext4 root partition. It does not create Windows recovery
media and cannot restore Windows.

## Immutable plan

The read-only planner emits canonical JSON containing:

- schema version and mode;
- physical disk path, model, serial, size, transport, and GPT identity;
- a SHA-256 fingerprint of the complete observed block-device inventory;
- every preserved partition identity;
- exact byte-aligned start and size for each proposed partition;
- required read-only prechecks;
- the destructive confirmation text, where applicable; and
- a plan ID derived from all of the above.

The held executor now implements this rule only for explicitly marked
disposable loop images. It regenerates the complete fixture plan, compares
live size/sector/GPT and preserved-partition identities, and refuses mounted or
changed targets before mutation. Physical-disk support remains absent.

Its transaction journal records the canonical plan, source fixture, complete
live inventories before and after mutation, original `sfdisk` table, exact
created partition and filesystem identities, state transitions, and events.
Dual-boot removal accepts only an intact `PARTITIONED` journal and deletes only
the two unchanged journal-owned partitions. The disposable test restores the
original Windows-style GPT table byte-for-byte. Wipe journals deliberately
have no recovery/removal claim.

The same held executor now audits and extracts the reproducible installed root,
imports all five size/hash-verified owner firmware files, writes target
filesystem and machine/NVMe identities, creates the selected password-backed
user, builds the exact review20 initramfs, and installs ARM64 GRUB only on the
dedicated Linux ESP. Dual boot records the preserved Windows loader identity
and generates an explicit filesystem-UUID-bound chainloader entry.

The independent installed verifier maps the same backing image through a
second kernel-read-only loop, mounts ext4 with `ro,noload` and the Linux ESP
read-only, regenerates the complete root+ESP manifest, and checks the account,
five firmware hashes, `fstab`, machine/NVMe identities, 3,759 modules, VideoCC
inside the initramfs, Linux boot payloads, ARM64 fallback loader, GRUB
configuration, and unchanged Windows Boot Manager. Two consecutive verifier
passes succeed before journal-driven removal.

## Installed system artifact

The live root is not an installation source. A dedicated installed-system
rootfs artifact will be built from the locked package snapshot and exact SP11
payload, with its own manifest and SHA-256. Live-only accounts, autologin,
diagnostics, installer files, caches, and firmware-extraction state are
excluded.

The first held artifact now implements that boundary. It is built directly
from the frozen 663-package signed closure, the project installed-system
overlay, exact review20 payload, allowlisted/derived firmware, and
redistributable audio topology. It contains no named human user, locks root,
leaves machine ID and `fstab` for the executor, and requires the five
owner-supplied firmware files at install time.

The artifact contains 121,262 independently manifested filesystem entries and
3,759 exact modules. Target-generated NVMe identity, Java/font/loader caches,
and package-install timestamps are removed or normalized before the manifest
is recorded. Engineering design documents are not embedded in the target
root, avoiding a self-reference between an artifact hash and documentation
that records that hash.

Two complete builds from new directories independently installed and
normalized the frozen closure, passed the full audit, and produced identical
root manifests, boot manifests, artifact tables, boot payloads, and archive
bytes. The 953,559,601-byte archive has SHA-256
`37466c74b4640b300c9f31e242050b42d75bb5163e3a02cf2228562285631993`;
the root manifest has SHA-256
`aea2358bb9d7b326fbf486e0e013936b2cbeb3984e5ce0bce4a6bad83ac67be1`.

## Removal and recovery

Dual-boot removal must be transaction-aware: verify the installation manifest,
remove only the Linux boot entry and Linux-owned ESP/root partitions, and leave
the resulting space unallocated for Windows to reclaim. It must never delete
the Microsoft EFI entry or Windows partitions.

Wipe-mode removal cannot recreate Windows. The user must boot official Surface
recovery media.

## Secure Boot

Secure Boot is a later, optional qualification track. The intended artifact is
an ARM64 unified kernel image containing the exact kernel, initramfs, command
line, and Denali device tree, signed by a project-controlled certificate.
`ukify` supports both a device-tree section and Secure Boot signing:
<https://man.archlinux.org/man/ukify.1.en>.

Surface UEFI supports custom third-party certificate configuration:
<https://learn.microsoft.com/en-us/surface/manage-surface-uefi-settings>.
Enrollment therefore remains an explicit physical UEFI action. The installer
must preserve Microsoft keys and must not automatically replace PK, KEK, or
`db`. The unsigned held live image continues to require Secure Boot disabled
until the signed boot chain has its own physical qualification record.

## Qualification order

1. Preserve two verified, disconnected copies of all SP11 work.
2. Test inventory and planning against synthetic and loopback disk layouts.
3. Build and verify the dedicated installed-system root artifact.
4. Implement the minimal executor and rollback journal. The complete loop-only
   partitioning, root population, account/boot provisioning, double read-only
   verification, dual removal, and wipe/no-recovery workflow passes.
5. Qualify dual boot, removal, and wipe mode on disposable media.
6. [x] Connect the audited interactive installer and application entry, embed
   the exact installed-system artifact, then rebuild and audit the held live
   image. The 2,396,192,768-byte artifact has SHA-256
   `853a0c5fda8a054c1bc824ba73077f04e3996d4653a669c54f25244224e07919`
   after correcting and loop-qualifying exact replacement of an existing
   terminal SP11 Linux ESP/root pair.
7. Restore Windows to factory state and run the complete physical matrix.
8. Qualify the optional signed Secure Boot path independently.
