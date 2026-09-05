#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest

HELPER = Path(__file__).resolve().parents[2] / "rootfs/usr/local/libexec/sp11-flex-shutdown"
loader = importlib.machinery.SourceFileLoader("flex_shutdown", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
KEYBOARD = "AA:BB:CC:DD:EE:01"
ADAPTER = "AA:BB:CC:DD:EE:02"


class FakeBluez:
    def __init__(self):
        self.pending = True
        self.blocked = False
        self.connected = True
        self.calls = []
        self.fail_block = False
        self.fail_restore = False
        self.stuck_connected = False
        self.find_failures = 0

    def poweroff_pending(self):
        return self.pending

    def find(self, device, adapter=None):
        if self.find_failures:
            self.find_failures -= 1
            raise RuntimeError("BlueZ not ready")
        if device != KEYBOARD or adapter not in (None, ADAPTER):
            raise RuntimeError("Wrong device or adapter")
        return "/keyboard", ADAPTER

    def properties(self, path):
        assert path == "/keyboard"
        return {"Blocked": self.blocked, "Connected": self.connected, "Paired": True}

    def block(self, path, value):
        assert path == "/keyboard"
        self.calls.append(value)
        if value and self.fail_block:
            raise RuntimeError("Set blocked failed")
        if not value and self.fail_restore:
            raise RuntimeError("Unblock failed")
        self.blocked = value
        if value and not self.stuck_connected:
            self.connected = False


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.config = self.root / "address"
        self.config.write_text(KEYBOARD + "\n")
        self.state = module.State(self.root)
        self.bluez = FakeBluez()
        self.present = True
        self.guard = module.Guard(self.bluez, self.state, self.config,
                                  lambda: self.present, sleep=lambda _: None)

    def test_poweroff_blocks_then_restore_clears_owned_state(self):
        self.assertTrue(self.guard.prepare())
        self.assertTrue(self.bluez.blocked)
        self.assertFalse(self.bluez.connected)
        self.assertFalse(self.state.read()["original_blocked"])
        self.guard.restore()
        self.assertEqual(self.bluez.calls, [True, False])
        self.assertIsNone(self.state.read())

    def test_durable_record_precedes_block(self):
        original = self.bluez.block
        def block(path, value):
            self.assertIsNotNone(self.state.read())
            original(path, value)
        self.bluez.block = block
        self.guard.prepare()

    def test_manual_stop_or_reboot_does_not_block(self):
        self.bluez.pending = False
        self.assertFalse(self.guard.prepare())
        self.assertEqual(self.bluez.calls, [])

    def test_detached_skipped(self):
        self.present = False
        self.assertFalse(self.guard.prepare())
        self.assertEqual(self.bluez.calls, [])

    def test_missing_configuration_skipped(self):
        self.config.unlink()
        self.assertFalse(self.guard.prepare())
        self.assertEqual(self.bluez.calls, [])

    def test_preexisting_user_block_preserved(self):
        self.bluez.blocked = True
        self.assertFalse(self.guard.prepare())
        self.guard.restore()
        self.assertTrue(self.bluez.blocked)
        self.assertEqual(self.bluez.calls, [])

    def test_pending_state_not_overwritten(self):
        self.guard.prepare()
        before = self.state.path.read_bytes()
        with self.assertRaises(RuntimeError):
            self.guard.prepare()
        self.assertEqual(before, self.state.path.read_bytes())

    def test_write_failure_does_not_block(self):
        def fail(_):
            raise OSError("Disk full")
        self.state.write = fail
        with self.assertRaises(OSError):
            self.guard.prepare()
        self.assertEqual(self.bluez.calls, [])

    def test_block_failure_rolls_back(self):
        self.bluez.fail_block = True
        with self.assertRaises(RuntimeError):
            self.guard.prepare()
        self.assertFalse(self.bluez.blocked)
        self.assertIsNone(self.state.read())

    def test_connection_does_not_drop_rolls_back(self):
        self.bluez.stuck_connected = True
        with self.assertRaises(RuntimeError):
            self.guard.prepare()
        self.assertFalse(self.bluez.blocked)
        self.assertIsNone(self.state.read())

    def test_restore_failure_preserves_recovery_record(self):
        self.guard.prepare()
        self.bluez.fail_restore = True
        with self.assertRaises(RuntimeError):
            self.guard.restore()
        self.assertIsNotNone(self.state.read())

    def test_restore_without_record_does_not_change_user_block(self):
        self.bluez.blocked = True
        self.guard.restore()
        self.assertEqual(self.bluez.calls, [])

    def test_restore_uses_record_even_if_configuration_changed(self):
        self.guard.prepare()
        self.config.write_text("00:11:22:33:44:55")
        self.guard.restore()
        self.assertFalse(self.bluez.blocked)

    def test_restore_retries_bluez_initialization(self):
        self.guard.prepare()
        self.bluez.find_failures = 2
        self.guard.restore()
        self.assertIsNone(self.state.read())

    def test_bounded_live_test_restores(self):
        self.guard.test()
        self.assertEqual(self.bluez.calls, [True, False])
        self.assertIsNone(self.state.read())

    def test_live_test_refuses_pending_state(self):
        self.guard.prepare()
        with self.assertRaises(RuntimeError):
            self.guard.test()
        self.assertTrue(self.bluez.blocked)

    def test_detach_during_test_still_restores(self):
        def sleep(_):
            self.present = False
        self.guard.sleep = sleep
        with self.assertRaises(RuntimeError):
            self.guard.test()
        self.assertFalse(self.bluez.blocked)
        self.assertIsNone(self.state.read())

    def test_invalid_address_rejected(self):
        self.config.write_text("not-a-device")
        with self.assertRaises(ValueError):
            self.guard.prepare()
        self.assertEqual(self.bluez.calls, [])

    def test_invalid_state_preserved(self):
        self.state.path.write_text(json.dumps({"version": 9}))
        with self.assertRaises(ValueError):
            self.guard.restore()
        self.assertTrue(self.state.path.exists())
        self.assertEqual(self.bluez.calls, [])

    def test_state_file_private(self):
        self.guard.prepare()
        self.assertEqual(self.state.path.stat().st_mode & 0o777, 0o600)


class IdentityTests(unittest.TestCase):
    def test_addresses_normalized(self):
        self.assertEqual(module.address(KEYBOARD.lower()), KEYBOARD)

    def test_no_wired_devices_is_detached(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertFalse(module.attached(Path(directory)))


class BluezTests(unittest.TestCase):
    def setUp(self):
        self.adapter_path = "/org/bluez/hci0"
        self.device_path = self.adapter_path + "/dev_AA_BB_CC_DD_EE_01"
        self.objects = {
            self.adapter_path: {module.ADAPTER: {"Address": ADAPTER}},
            self.device_path: {module.DEVICE: {
                "Address": KEYBOARD, "Adapter": self.adapter_path,
                "Modalias": "usb:v045Ep0C7Ad0101", "Paired": True,
            }},
        }
        self.jobs = []
        manager = SimpleNamespace(GetManagedObjects=lambda **_: self.objects,
                                  ListJobs=lambda **_: self.jobs)
        self.bluez = module.Bluez.__new__(module.Bluez)
        self.bluez.bus = SimpleNamespace(get_object=lambda *_: manager)
        self.bluez.dbus = SimpleNamespace(Interface=lambda obj, _: obj)

    def test_exact_keyboard_found(self):
        self.assertEqual(self.bluez.find(KEYBOARD), (self.device_path, ADAPTER))

    def test_different_device_rejected(self):
        with self.assertRaises(RuntimeError):
            self.bluez.find("00:11:22:33:44:55")

    def test_wrong_vendor_or_product_rejected(self):
        self.objects[self.device_path][module.DEVICE]["Modalias"] = "usb:v045Ep0001d0101"
        with self.assertRaises(ValueError):
            self.bluez.find(KEYBOARD)

    def test_unpaired_device_rejected(self):
        self.objects[self.device_path][module.DEVICE]["Paired"] = False
        with self.assertRaises(ValueError):
            self.bluez.find(KEYBOARD)

    def test_wrong_adapter_rejected_on_restore(self):
        with self.assertRaises(RuntimeError):
            self.bluez.find(KEYBOARD, "00:11:22:33:44:55")

    def test_ambiguous_device_rejected(self):
        self.objects[self.device_path + "_duplicate"] = self.objects[self.device_path]
        with self.assertRaises(RuntimeError):
            self.bluez.find(KEYBOARD)

    def test_poweroff_target_start_detected(self):
        self.jobs = [(1, "poweroff.target", "start", "waiting", "/job", "/unit")]
        self.assertTrue(self.bluez.poweroff_pending())

    def test_poweroff_service_start_detected(self):
        self.jobs = [(1, "systemd-poweroff.service", "start", "waiting", "/job", "/unit")]
        self.assertTrue(self.bluez.poweroff_pending())

    def test_reboot_suspend_and_manual_stop_excluded(self):
        for name, action in (("reboot.target", "start"), ("suspend.target", "start"),
                             ("bluetooth.service", "stop"), ("poweroff.target", "stop")):
            self.jobs = [(1, name, action, "waiting", "/job", "/unit")]
            self.assertFalse(self.bluez.poweroff_pending())


if __name__ == "__main__":
    unittest.main()
