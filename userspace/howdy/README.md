# Bounded SP11 IR bridge review preview

> This source-review integration does not install Howdy,
> enroll a face, modify PAM, enable biometric login, or authorize a binary
> payload. The bridge is restricted to the reviewed Surface Pro 11 OLED/X
> Elite kernel and has passed one bounded target-hardware test on that exact
> platform. This is not broad compatibility or eye-safety certification.

The bridge converts the VD55G0's 644x604 packed Y10P stream to an 8-bit GREY
v4l2loopback stream. Its intended initial consumer is a direct, non-PAM Howdy
test. It deliberately has no still-image or raw-file output mode.

## Safety model

The reviewed device tree combines the verified PM8550 sinks into one IR flash
LED with a conservative 600 mA torch ceiling. The bridge accepts exactly that
one LED, checks its expected brightness scale, and refuses to run on another
device-tree compatible or kernel release.

Illumination is bounded twice:

- the bridge turns the torch off in its `finally` cleanup and refuses a runtime
  longer than 14 seconds;
- systemd enforces `RuntimeMaxSec=15` and runs the separate
  `sp11-ir-light-off` helper before and after every invocation, including
  abnormal process exits.

This is a proof-of-concept safety boundary, not an eye-safety certification.
Do not stare into the camera module at close range. Stop the service and invoke
the independent off helper if behavior is unexpected:

```sh
sudo systemctl stop sp11-ir-bridge.service
sudo /usr/local/libexec/sp11-ir-light-off
```

## Dependencies and source obligations

- reviewed kernel source at
  `86fc94c58a89a56c7ceb57b42c6025b2569da56d`, built as
  `7.1.3-sp11-camera-review5`;
- `media-ctl` and `v4l2-ctl` from v4l-utils;
- Python 3 and NumPy;
- FFmpeg;
- systemd;
- v4l2loopback 0.15.4, tag commit
  `0f9ee86760b7f2bea174b7e3e7a1d38845da0ab4`, GPL-2.0-or-later, built
  locally for the exact running kernel.

Howdy itself is not included or installed. The local proof of concept used the
Arch package `howdy 2.6.1-3`, corresponding to upstream tag commit
`3c9537a35f23773ceca86e79be1ebed3ebe774cc` under the MIT license. That old
release identity is evidence, not a recommendation for PAM use. Howdy's own
documentation warns that it is less secure than a password and must not be the
sole authentication method. Its version, transitive dependencies, packaging,
model source, and current security posture require a new review before any
package is proposed. A future binary release that ships v4l2loopback or another
GPL/LGPL component must include its exact complete corresponding source and
applicable license material.

## Bounded validation result

On 2026-07-19 the exact reviewed bridge was tested on the reviewed
`7.1.3-sp11-camera-review4` kernel with v4l2loopback 0.15.4. An eight-second run
produced 12 GREY loopback frames with 12 distinct hashes; no frame was saved.
Normal timeout and SIGTERM returned the IR LED to zero.

On 2026-07-20 the same bridge was retargeted only to the integrated review5
kernel identity and exercised in two bounded previews with a separately built
review5 v4l2loopback 0.15.4 module. Both runs reached readiness, returned IR
brightness to zero, left no bridge/FFmpeg/media-graph process behind, and added
no kernel warning. The normal visual preview was also confirmed by the
maintainer. The external module and Howdy remain local test dependencies and
are not included here.

The initial hardened `Type=notify` test found that invoking `systemd-notify` as
a child was incompatible with the empty capability bounding set and default
`NotifyAccess=main`. Readiness was changed to send the notification directly
from the bridge process and covered by a Unix-socket unit test. The corrected
service reached readiness under the documented hardening. After its main
process was sent SIGKILL, systemd ran the independent `ExecStopPost` helper,
which exited successfully and returned brightness from 255 to zero. The final
kernel log contained no new camera warning, oops, or call trace.

## Manual development staging

Do not make the experimental kernel your only boot entry. Build and install
v4l2loopback 0.15.4 against the exact running kernel, then load it with the
reviewed endpoint configuration:

```sh
sudo modprobe v4l2loopback \
  video_nr=42 card_label='SP11 IR' exclusive_caps=1
```

Stage the reviewed files manually from this tree, preserving modes:

```text
rootfs/etc/modprobe.d/sp11-ir-loopback.conf
rootfs/etc/sp11-ir-bridge.conf
rootfs/etc/systemd/system/sp11-ir-bridge.service
rootfs/usr/local/libexec/sp11-ir-bridge
rootfs/usr/local/libexec/sp11-ir-light-off
```

Also install this README as
`/usr/local/share/doc/sp11-howdy/README.md`, run `systemctl daemon-reload`, and
start the bridge only for a bounded local test:

```sh
sudo systemctl start sp11-ir-bridge.service
v4l2-ctl -d /dev/video42 --all
```

Because the unit is `Type=notify`, `systemctl start` succeeds only after the
first complete converted frame reaches FFmpeg. The service stops itself after
15 seconds.

For a Howdy experiment, first pin and review a Howdy version, configure only
its camera device as `/dev/video42`, enroll locally, and invoke its direct test
command while this bounded service runs. Do not edit `/etc/pam.d/*` during this
review phase.

## Privacy and security

Face templates are authentication secrets. Keep enrollment data and all RGB/IR
captures local, mode-restricted, and out of Git, bug reports, diagnostic
archives, backups that are not intended to contain biometrics, and release
payloads. Face recognition is not equivalent to presence detection and may be
vulnerable to presentation attacks. Keep password authentication and a tested
root/recovery path.

The bridge runs as root because the current camera graph and LED sysfs controls
require it. Its service has no network address family, no home access, an empty
capability bounding set, a read-only system tree, and a fixed short lifetime.
Those restrictions do not make third-party Howdy models or PAM configuration
trusted.

## Rollback

No PAM file should have changed. To remove the preview:

1. stop and disable `sp11-ir-bridge.service`;
2. run `sp11-ir-light-off` and verify the LED brightness reads zero;
3. remove the five staged files listed above and the installed README;
4. run `systemctl daemon-reload`;
5. unload v4l2loopback if unused, and remove its local module/configuration.

Keep the known-good kernel and recovery entry throughout testing.
