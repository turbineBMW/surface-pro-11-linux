# Binary and ISO release hold

The source code, reviewed patches, Git bundles, documentation, and build
instructions in this repository may be published for experimental development
and testing. This file blocks publication of prebuilt kernels, modules,
userspace binaries, payload archives, disk images, and ISOs.

No binary release is authorized until it has exact corresponding source for
every GPL/LGPL binary, all required license texts and notices, reproducible
build identities, archive/privacy checks, and clean install and rollback
validation on supported hardware.

The hold permanently excludes every former Practical8 patch, Git bundle,
kernel Image, DTB, module tree, payload archive, and Git object that contains
the withdrawn camera implementation. Those objects must not be copied into a
new source repository or binary release.

The reviewed `sp11-camera-review` branch replaces that implementation. It uses
documented GPL sources for the Qualcomm and ST material and independently
written Linux code for runtime hardware observations. Its bounded validation
is recorded in `docs/CAMERA-REVIEW.md`, but that source validation is not a
binary or ISO release authorization.

Local building and hardware testing may continue. Remove this file only as an
intentional binary-release action after the binary gates in
`docs/REDISTRIBUTION-REVIEW.md` are complete. This is an engineering
compliance guard, not legal advice or a guarantee against third-party claims.
