# Desktop integration notes

## Haptic touchpad right click

The tested machine disables tap-to-click and uses libinput's `clickfinger`
method: one-finger physical press is left click; a two-finger physical press
anywhere on the haptic pad is right click.

For Niri:

```kdl
input {
    touchpad {
        // Leave `tap` disabled.
        click-method "clickfinger"
    }
}
```

Other Wayland compositors and desktop environments expose the same libinput
click-method choice through their own configuration layer.

## Chassis buttons

The volume rocker is emitted by `gpio-keys` as standard `KEY_VOLUMEUP` and
`KEY_VOLUMEDOWN`, including hold-to-repeat. A normal desktop audio service
should display its usual OSD without custom bindings.

The power button's current immediate-shutdown behavior is a known policy issue.
This alpha deliberately does not install an unqualified global override.
