# Installation status

No prebuilt payload or ISO is published. `BINARY-RELEASE-HOLD.md` deliberately
blocks the old payload assembly and installer path until a new binary release
has complete corresponding source, license material, archive review, and clean
install/rollback validation.

Experienced developers may build the reviewed source by following `BUILD.md`
and `../kernel/README.md`. Installing a self-built kernel is currently a manual
development task and is not covered by a supported installer.

Before testing a self-built kernel:

1. start from the Arch Linux ARM and firmware workflow documented by
   `dwhinham/linux-surface-pro-11`;
2. retain that project's known-good kernel and boot entry;
3. keep recovery media and an alternate way to edit the boot filesystem;
4. install the experimental Image, DTB, modules, and initramfs under unique
   names;
5. add a separate GRUB entry without changing the persistent default; and
6. test it first with a one-shot boot selection.

Do not download, mirror, install, or redistribute the former Practical8
payload. It does not correspond to the reviewed source in this repository.

The eventual project goal is a reproducible installer or image with the same
kind of approachable bootstrap offered by the foundation project. That work is
not complete, and this source preview should not be described as an ISO or
distribution release.
