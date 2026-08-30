# Bluetooth and Surface Pro Flex Keyboard

## Controller address setup

The SP11 WCN7850 controller initially appears as an unconfigured HCI device.
`sp11-bluetooth-address.service` supplies a public address before BlueZ starts.
By default, the helper uses the six address bytes in the firmware
`MacAddressEmulationAddress-*` EFI variable.

**That EFI value is the Wi-Fi MAC, not the Bluetooth address.** On the tested
unit the Bluetooth adapter is that address **minus one** in the last octet, and
that is the identity a Flex Keyboard bonds to. Confirm before relying on the
default:

```sh
btmgmt info | grep addr
```

If it does not match the address the keyboard is bonded to, set the override
described below. Without it the adapter runs under an identity no keyboard has
ever paired with, and detached mode cannot work by any route.

The public address can only be assigned while the controller is unconfigured.
Changing it on a running, configured controller is not a valid test; reboot
after selecting a different address.

## Detached Flex Keyboard

The Flex Keyboard does not expose an interactive pairing mode and does not
advertise to an unknown host. It is paired **over the wired connector**: the
host writes its Bluetooth address and a 128-bit pairing key to a vendor HID
collection on the keyboard, and the keyboard then authenticates over Bluetooth
using that key as an LE legacy out-of-band TK.

This works natively on Linux and needs nothing from Windows. It requires two
kernel changes, both carried as patches with this release:

1. registration of KIP HID instance 9, so the pairing channel (PID `0C8F`,
   Microsoft "Bluetooth OOB Coupling", HID usage page `0xFFF4`) is enumerated;
   and
2. LE legacy out-of-band pairing support in the Bluetooth stack, which upstream
   had left unimplemented.

Pairing is repeatable and may be re-run at any time. That matters on a
dual-boot machine: Windows re-pairs the keyboard on its own schedule, which
invalidates the Linux bond, and the fix is simply to pair again.

Note that the keyboard uses the wired link whenever it is attached, so it must
be detached for the Bluetooth connection to come up. `bluetoothd` background
auto-connect does not reliably pick it up; an explicit connect does, so a
detach hook is the practical arrangement.

### Pairing on Linux

With a kernel carrying `kernel/sp11-flex-bt-oob-pairing.patch` (the 7.3 port
in `kernel/port-7.3/` includes it), attach the keyboard and run:

```sh
sudo sp11-flex-pair --status   # read the channel, change nothing
sudo sp11-flex-pair            # pair; detach when prompted
```

The tool finds the `0C8F` hidraw node, sends the adapter's public address to
the keyboard, waits for the keyboard's identity report, writes a fresh random
128-bit key over the wire, registers the same key with the kernel as LE legacy
OOB data, and then waits for you to detach. Pairing completes within a few
seconds of detaching; the resulting bond is stored as authenticated
(`Authenticated=1`) and the adapter's Secure Connections setting is left on --
the kernel selects the legacy path for this peer only. The key is never
printed. On success the keyboard's address is written to
`/etc/sp11/flex-keyboard-address`.

Reconnect on detach is handled by `rootfs/etc/udev/rules.d/99-sp11-flex-bt.rules`:
when the wired `045E:0C8B` HID endpoint disappears it starts
`sp11-flex-bt-connect.service`, which issues an explicit `bluetoothctl connect`
to the recorded address with retries and logs under `journalctl -t flex-bt`.
Nothing happens if the address file is absent.

If the keyboard has been re-paired by Windows since, the Linux bond is stale;
`sp11-flex-pair --status` shows `HostPairingExists=0` and running the pairing
again resolves it.

### Reusing a Windows bond instead

Where the kernel patches are not in use, a bond created by Windows 11 can be
imported instead. Both sides must match:

1. import the keyboard's Windows LTK, IRK, signature keys, `ERand`, `EDiv`, and
   connection parameters into the corresponding BlueZ `info` file;
2. set `Trusted=true`, `AddressType=static`, `SupportedTechnologies=LE;`, and
   the other device metadata expected by BlueZ;
3. use the same local controller public address under which Windows created
   the bond; and
4. store the BlueZ device directory below that local controller address.

This is a workaround, not the supported path: the imported key is invalidated
the next time Windows re-pairs the keyboard.

Treat the Windows registry hive and every Bluetooth key as secrets. Do not add
them to this repository, terminal transcripts, issue reports, or diagnostics.

If the Windows adapter address differs from the firmware EFI address, create
`/etc/sp11/bluetooth-address.conf` containing:

```sh
SP11_BLUETOOTH_PUBLIC_ADDRESS=AA:BB:CC:DD:EE:FF
```

Replace the example with the Windows adapter address that contains the Flex
Keyboard bond. The helper accepts one canonical, unicast MAC address and
rejects malformed, multicast, zero, and broadcast values. Keep the file local;
the project does not install a machine-specific override.

After the BlueZ bond is present below the matching adapter directory, reboot.
Attach the keyboard long enough to power it, then detach it. BlueZ should
resolve the keyboard identity, authenticate with the imported bond, and expose
the Bluetooth HID and battery services.

## Surface Slim Pen 2

Inking and pressure work over the digitizer without Bluetooth. The tail
button, however, is only delivered over BLE, and Windows does it without ever
bonding the pen (a "loosely-coupled" GATT stack with an AES-CMAC coupling key
and a virtual HID device). Linux does not need any of that: the pen accepts an
ordinary Just Works bond and then presents a keyboard node whose tail button
sends **Meta+F19** (click) and **Meta+F20** (double click); a long press
follows the same scheme as Meta+F18. Bind those in the compositor.

```sh
sp11-pen-pair        # no root; hold the tail button 5-7 s until the LED blinks
```

Two things about the pen are not faults:

- It is silent unless it is in pairing mode. Undocking, docking, inking and
  single clicks produce no advertisement at all, so no daemon can pick it up
  automatically. After it has been docked in the keyboard (which returns it to
  its Windows-style mode) hold the tail button about 7 s until the LED blinks;
  the existing bond then resumes in roughly 10--15 s without re-pairing.
  A pen that shows no LED at all needs Microsoft's reset -- hold 10 s, then
  the 7 s hold.
- Battery level arrives over the same bond (`bluetoothctl info` shows
  `Battery Percentage`), and the keyboard's pen charger reports docked pen
  charge on its own HID channel.

Do not probe the digitizer's (`045E:0C83`) vendor `0xFFF4` HID collection over
hidraw: feature reads there time out and leave the stylus path dead until the
`spi_hid_of` driver is rebound or the machine is rebooted. The keyboard-side
channels (`0C8E`, `0C8F`) are safe.

## Recovery

If Bluetooth does not return, remove the override from recovery media or a
wired-keyboard session, then reboot. The helper falls back to the firmware EFI
address. Existing bonds under either adapter directory are not deleted, but
only the directory matching the active local controller address is used.
