# Bluetooth and Surface Pro Flex Keyboard

## Controller address setup

The SP11 WCN7850 controller initially appears as an unconfigured HCI device.
`sp11-bluetooth-address.service` supplies a public address before BlueZ starts.
By default, the helper uses the six address bytes in the firmware
`MacAddressEmulationAddress-*` EFI variable.

The public address can only be assigned while the controller is unconfigured.
Changing it on a running, configured controller is not a valid test; reboot
after selecting a different address.

## Detached Flex Keyboard

The Flex Keyboard does not expose a normal interactive pairing mode. A working
Linux setup can reuse the Bluetooth bond created by Windows 11, but both sides
of the bond must match:

1. import the keyboard's Windows LTK, IRK, signature keys, `ERand`, `EDiv`, and
   connection parameters into the corresponding BlueZ `info` file;
2. set `Trusted=true`, `AddressType=static`, `SupportedTechnologies=LE;`, and
   the other device metadata expected by BlueZ;
3. use the same local controller public address under which Windows created
   the bond; and
4. store the BlueZ device directory below that local controller address.

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

## Recovery

If Bluetooth does not return, remove the override from recovery media or a
wired-keyboard session, then reboot. The helper falls back to the firmware EFI
address. Existing bonds under either adapter directory are not deleted, but
only the directory matching the active local controller address is used.
