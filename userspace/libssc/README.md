<!-- SPDX-License-Identifier: MIT -->

# Surface color sensor mapping for libssc

The tested base is libssc 0.4.4 at upstream commit
`3befde3ef215bdb78c4a48aa72c99cd458c2aed0`.

Surface Pro 11 firmware registers both `ambient_light` and `color` SSC data
types. The former produces zero-only samples on the tested OLED model. The
latter is the Microsoft `surface color sensor`; its standard repeated-float
report places illuminance in element zero. This patch makes libssc's existing
light API consume that endpoint, so iio-sensor-proxy can continue using the
normal `SSCSensorLight` interface.

```sh
git clone https://codeberg.org/DylanVanAssche/libssc.git
cd libssc
git checkout 3befde3ef215bdb78c4a48aa72c99cd458c2aed0
git apply /path/to/0001-light-use-surface-color-sensor.patch
meson setup build --prefix=/usr --buildtype=debugoptimized
meson compile -C build
```

Install the resulting `libssc.so.2` separately under
`/usr/local/lib/sp11/`. The supplied iio-sensor-proxy service drop-in selects
that private library path without overwriting the distribution package.

This mapping is intentionally SP11-specific. Do not replace a system libssc
globally on unrelated Qualcomm devices.
