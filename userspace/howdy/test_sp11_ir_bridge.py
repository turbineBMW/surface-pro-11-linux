#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 turbinebmw
# SPDX-License-Identifier: MIT
"""Hardware-independent checks for the bounded SP11 IR bridge."""

from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import os
from pathlib import Path
import socket
import tempfile
import unittest
from unittest import mock


BRIDGE_PATH = (
    Path(__file__).resolve().parents[2]
    / "rootfs/usr/local/libexec/sp11-ir-bridge"
)
bridge_loader = SourceFileLoader("sp11_ir_bridge", str(BRIDGE_PATH))
bridge_spec = spec_from_loader("sp11_ir_bridge", bridge_loader)
if bridge_spec is None or bridge_spec.loader is None:
    raise RuntimeError(f"could not load bridge module from {BRIDGE_PATH}")
bridge = module_from_spec(bridge_spec)
bridge_spec.loader.exec_module(bridge)


class ConversionTests(unittest.TestCase):
    def test_y10p_drops_low_bits_and_stride_padding(self) -> None:
        line = bytearray(bridge.FRAME_STRIDE)
        for offset in range(0, bridge.Y10P_PAYLOAD_PER_LINE - 4, 5):
            line[offset : offset + 5] = bytes((1, 2, 3, 4, 255))
        frame = bytes(line) * bridge.FRAME_HEIGHT
        grey = bridge.y10p_to_grey(frame)
        self.assertEqual(len(grey), bridge.GREY_FRAME_BYTES)
        self.assertEqual(grey[:8], bytes((1, 2, 3, 4, 1, 2, 3, 4)))

    def test_y10p_rejects_partial_frame(self) -> None:
        with self.assertRaises(bridge.BridgeError):
            bridge.y10p_to_grey(b"\0" * (bridge.Y10P_FRAME_BYTES - 1))


class NotificationTests(unittest.TestCase):
    def test_ready_notification_comes_from_bridge_process(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            notify_path = str(Path(temporary_directory) / "notify.sock")
            with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as listener:
                listener.bind(notify_path)
                listener.settimeout(1)
                with mock.patch.dict(os.environ, {"NOTIFY_SOCKET": notify_path}):
                    bridge.notify_ready()
                self.assertEqual(listener.recv(64), b"READY=1")


class IlluminatorTests(unittest.TestCase):
    def make_led(self, root: Path, maximum: str = "255") -> Path:
        led = root / "ir:flash"
        led.mkdir()
        (led / "max_brightness").write_text(maximum, encoding="ascii")
        (led / "brightness").write_text("0", encoding="ascii")
        return led

    def test_single_reviewed_led_turns_on_and_off(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            led = self.make_led(root)
            illuminator = bridge.Illuminator(root)
            illuminator.on()
            self.assertEqual((led / "brightness").read_text(), "255")
            illuminator.off()
            self.assertEqual((led / "brightness").read_text(), "0")

    def test_missing_or_multiple_leds_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(bridge.BridgeError):
                bridge.Illuminator(root)
            self.make_led(root)
            other = root / "ir:flash-1"
            other.mkdir()
            (other / "max_brightness").write_text("255", encoding="ascii")
            with self.assertRaises(bridge.BridgeError):
                bridge.Illuminator(root)

    def test_unexpected_brightness_scale_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_led(root, "511")
            with self.assertRaises(bridge.BridgeError):
                bridge.Illuminator(root)


if __name__ == "__main__":
    unittest.main()
