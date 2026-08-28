# Removing SP11 Linux again

## Dual-boot installation

The installer created exactly two partitions (an EFI partition labelled
`SP11EFI` and an ext4 root labelled `sp11root`) and one UEFI boot entry named
`SP11 Linux`. Windows, its EFI partition, and the recovery partition were not
modified.

1. Boot Windows (pick *Windows Boot Manager* in GRUB, or select Windows in
   UEFI settings).
2. In an administrator PowerShell, remove the boot entry:

   ```powershell
   bcdedit /enum firmware
   bcdedit /delete {identifier-of-SP11-Linux} /f
   ```

   Alternatively set Windows Boot Manager first in UEFI settings and leave
   the entry; it is harmless.
3. In **Disk Management**, delete the `sp11root` and `SP11EFI` volumes. If
   Disk Management refuses the small EFI volume, use `diskpart`
   (`select disk 0`, `list partition`, `select partition N`,
   `delete partition override`).
4. Extend `C:` into the freed space if you want.

Re-enable Secure Boot in UEFI settings if you turned it off only for Linux.

## Wipe installation

There is no Windows to go back to. Reinstall Windows with the
[Surface recovery image](https://support.microsoft.com/surface-recovery-image)
on a USB stick (≥ 16 GB) and boot it with Volume-Down + Power.

## Overlay installation on an existing Arch Linux ARM system

Use the transaction rollback: `sudo scripts/rollback.sh` from the repository
(or `sp11-rollback-live` from the live USB). See [ROLLBACK.md](ROLLBACK.md).
