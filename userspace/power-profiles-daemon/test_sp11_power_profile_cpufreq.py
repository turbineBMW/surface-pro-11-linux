#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 turbinebmw
# SPDX-License-Identifier: MIT
"""Hardware-independent tests for the SP11 cpufreq profile companion."""

from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import io
from pathlib import Path
import tempfile
import unittest
from unittest import mock


COMPANION_PATH = (
    Path(__file__).resolve().parents[2]
    / "rootfs/usr/local/libexec/sp11-power-profile-cpufreq"
)
companion_loader = SourceFileLoader("sp11_power_profile_cpufreq", str(COMPANION_PATH))
companion_spec = spec_from_loader("sp11_power_profile_cpufreq", companion_loader)
if companion_spec is None or companion_spec.loader is None:
    raise RuntimeError(f"could not load companion module from {COMPANION_PATH}")
companion = module_from_spec(companion_spec)
companion_spec.loader.exec_module(companion)


class ProfileMappingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.cpufreq_root = self.root / "cpufreq"
        self.cpufreq_root.mkdir()
        self.profile_path = self.root / "profile"
        self.profile_path.write_text("balanced\n", encoding="ascii")

        patches = (
            mock.patch("sys.stdout", new=io.StringIO()),
            mock.patch.object(companion, "CPUFREQ_ROOT", self.cpufreq_root),
            mock.patch.object(companion, "PROFILE_PATH", self.profile_path),
            mock.patch.object(companion, "POWER_SAVER_TARGET_KHZ", 1_920_000),
            mock.patch.object(companion, "BALANCED_TARGET_KHZ", 2_515_200),
        )
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)

    def add_policy(
        self,
        number: int,
        *,
        hardware_min: int = 710_400,
        hardware_max: int = 3_417_600,
        scaling_min: int = 710_400,
        scaling_max: int = 3_417_600,
        available: tuple[int, ...] = (
            710_400,
            1_670_400,
            1_920_000,
            2_515_200,
            3_417_600,
        ),
    ) -> Path:
        policy = self.cpufreq_root / f"policy{number}"
        policy.mkdir()
        values = {
            "cpuinfo_min_freq": hardware_min,
            "cpuinfo_max_freq": hardware_max,
            "scaling_min_freq": scaling_min,
            "scaling_max_freq": scaling_max,
        }
        for name, value in values.items():
            (policy / name).write_text(f"{value}\n", encoding="ascii")
        if available:
            (policy / "scaling_available_frequencies").write_text(
                " ".join(str(value) for value in available) + "\n",
                encoding="ascii",
            )
        return policy

    def maximum(self, policy: Path) -> int:
        return int((policy / "scaling_max_freq").read_text(encoding="ascii"))

    def test_three_tiers_apply_to_every_policy(self) -> None:
        policies = [self.add_policy(number) for number in (0, 4, 8)]

        companion.apply("power-saver")
        self.assertEqual([self.maximum(policy) for policy in policies], [1_920_000] * 3)

        companion.apply("balanced")
        self.assertEqual([self.maximum(policy) for policy in policies], [2_515_200] * 3)

        companion.apply("performance")
        self.assertEqual([self.maximum(policy) for policy in policies], [3_417_600] * 3)

    def test_kernel_profile_names_cover_resume_path(self) -> None:
        policy = self.add_policy(0)
        self.profile_path.write_text("low-power\n", encoding="ascii")
        companion.apply()
        self.assertEqual(self.maximum(policy), 1_920_000)

        self.profile_path.write_text("balanced-performance\n", encoding="ascii")
        companion.apply()
        self.assertEqual(self.maximum(policy), 2_515_200)

    def test_candidate_and_unsupported_targets_round_down(self) -> None:
        policy = self.add_policy(
            0,
            available=(710_400, 1_670_400, 1_804_800, 2_419_200, 3_417_600),
        )
        companion.apply("power-saver")
        self.assertEqual(self.maximum(policy), 1_804_800)
        companion.apply("balanced")
        self.assertEqual(self.maximum(policy), 2_419_200)

        with mock.patch.object(companion, "POWER_SAVER_TARGET_KHZ", 1_670_400):
            companion.apply("power-saver")
        self.assertEqual(self.maximum(policy), 1_670_400)

    def test_unknown_profile_fails_without_writing(self) -> None:
        policy = self.add_policy(0)
        with self.assertRaisesRegex(RuntimeError, "unsupported power profile"):
            companion.apply("unexpected")
        self.assertEqual(self.maximum(policy), 3_417_600)

    def test_preflight_prevents_partial_policy_changes(self) -> None:
        first = self.add_policy(0)
        second = self.add_policy(4, scaling_min=2_515_200)
        with self.assertRaisesRegex(RuntimeError, "scaling_min_freq"):
            companion.apply("power-saver")
        self.assertEqual(self.maximum(first), 3_417_600)
        self.assertEqual(self.maximum(second), 3_417_600)

    def test_missing_frequency_table_clamps_to_hardware_bounds(self) -> None:
        policy = self.add_policy(0, hardware_min=2_100_000, available=())
        companion.apply("power-saver")
        self.assertEqual(self.maximum(policy), 2_100_000)

    def test_restore_returns_hardware_maximum(self) -> None:
        policy = self.add_policy(0, scaling_max=1_670_400)
        companion.restore()
        self.assertEqual(self.maximum(policy), 3_417_600)

    def test_lower_aggregate_limit_still_submits_the_requested_ceiling(self) -> None:
        first = self.add_policy(0)
        second = self.add_policy(4)
        original_read = companion.read_text

        def thermal_readback(path: Path) -> str:
            if path == first / "scaling_max_freq":
                return "1670400"
            return original_read(path)

        with mock.patch.object(companion, "read_text", side_effect=thermal_readback):
            companion.apply("balanced")
        # The file models our request, while read_text models the aggregate.
        self.assertEqual(self.maximum(first), 2_515_200)
        self.assertEqual(self.maximum(second), 2_515_200)

    def test_equal_aggregate_limit_does_not_skip_a_hidden_request(self) -> None:
        policy = self.add_policy(0, scaling_max=3_417_600)
        with mock.patch.object(companion, "read_text", return_value="2515200"):
            companion.write_and_verify(policy / "scaling_max_freq", 2_515_200)
        self.assertEqual(self.maximum(policy), 2_515_200)

    def test_async_limit_settles_without_repeated_writes(self) -> None:
        policy = self.add_policy(0)
        with (
            mock.patch.object(companion, "read_text", side_effect=["3417600", "1920000"]),
            mock.patch.object(companion.time, "sleep") as sleep,
            mock.patch.object(Path, "open", mock.mock_open()) as opened,
        ):
            companion.write_and_verify(policy / "scaling_max_freq", 1_920_000)
        self.assertEqual(opened.call_count, 1)
        self.assertEqual(sleep.call_count, 1)

    def test_higher_or_invalid_readback_fails(self) -> None:
        policy = self.add_policy(0)
        for actual in ("3417600", "0", "-1"):
            with (
                self.subTest(actual=actual),
                mock.patch.object(companion, "read_text", return_value=actual),
                mock.patch.object(companion.time, "sleep"),
                self.assertRaises(RuntimeError),
            ):
                companion.write_and_verify(policy / "scaling_max_freq", 1_920_000)

    def test_write_time_failure_rolls_back_and_leaves_later_policy_untouched(self) -> None:
        first, second, third = [self.add_policy(i) for i in (0, 4, 8)]
        original_write = companion.write_and_verify

        def fail_second(path: Path, value: int) -> None:
            if path.parent == second and value == 1_920_000:
                raise OSError("injected failure")
            original_write(path, value)

        with mock.patch.object(companion, "write_and_verify", side_effect=fail_second) as write:
            with self.assertRaisesRegex(OSError, "injected failure"):
                companion.apply("power-saver")
        self.assertEqual([self.maximum(p) for p in (first, second, third)], [3_417_600] * 3)
        self.assertFalse(any(call.args[0].parent == third for call in write.call_args_list))

    def test_failed_policy_is_rolled_back_even_after_a_successful_write(self) -> None:
        first, second = [self.add_policy(i) for i in (0, 4)]
        original_write = companion.write_and_verify

        def fail_readback(path: Path, value: int) -> None:
            original_write(path, value)
            if path.parent == second and value == 1_920_000:
                raise OSError("readback disappeared")

        with mock.patch.object(companion, "write_and_verify", side_effect=fail_readback):
            with self.assertRaisesRegex(OSError, "readback disappeared"):
                companion.apply("power-saver")
        self.assertEqual([self.maximum(p) for p in (first, second)], [3_417_600] * 2)

    def test_rollback_continues_after_one_policy_cannot_be_restored(self) -> None:
        first, second = [self.add_policy(i) for i in (0, 4)]
        original_write = companion.write_and_verify

        def fail_second(path: Path, value: int) -> None:
            if path.parent == second:
                raise OSError("policy unavailable")
            original_write(path, value)

        with mock.patch.object(companion, "write_and_verify", side_effect=fail_second):
            with self.assertRaisesRegex(RuntimeError, "rollback incomplete: policy4"):
                companion.apply("power-saver")
        self.assertEqual(self.maximum(first), 3_417_600)

    def test_snapshot_failure_does_not_write_any_policy(self) -> None:
        self.add_policy(0)
        second = self.add_policy(4)
        (second / "scaling_max_freq").unlink()
        with mock.patch.object(companion, "write_and_verify") as write:
            with self.assertRaises(FileNotFoundError):
                companion.apply("power-saver")
        write.assert_not_called()

    def test_restore_attempts_remaining_policies_after_failure(self) -> None:
        first, second = [self.add_policy(i, scaling_max=1_920_000) for i in (0, 4)]
        original_write = companion.write_and_verify

        def fail_first(path: Path, value: int) -> None:
            if path.parent == first:
                raise OSError("policy unavailable")
            original_write(path, value)

        with mock.patch.object(companion, "write_and_verify", side_effect=fail_first):
            with self.assertRaisesRegex(RuntimeError, "restore incomplete: policy0"):
                companion.restore()
        self.assertEqual(self.maximum(second), 3_417_600)

    def test_service_failure_cleanup_preserves_rollback_limits(self) -> None:
        for result in ("success", "exit-code", "signal", "timeout", ""):
            with (
                self.subTest(result=result),
                mock.patch.dict(companion.os.environ, {"SERVICE_RESULT": result}),
                mock.patch.object(companion.sys, "argv", ["helper", "--restore-after-stop"]),
                mock.patch.object(companion, "restore") as restore,
            ):
                self.assertEqual(companion.main(), 0)
                self.assertEqual(restore.call_count, int(result == "success"))

    def test_watcher_failure_preserves_rollback_but_intentional_stop_restores(self) -> None:
        fake_modules = {
            name: mock.MagicMock()
            for name in ("dbus", "dbus.mainloop", "dbus.mainloop.glib", "gi", "gi.repository")
        }
        loop = fake_modules["gi.repository"].GLib.MainLoop.return_value
        with (
            mock.patch.dict(companion.sys.modules, fake_modules),
            mock.patch.object(companion.signal, "signal"),
            mock.patch.object(companion, "restore") as restore,
            mock.patch.object(companion, "apply", side_effect=OSError("startup failure")),
        ):
            with self.assertRaisesRegex(OSError, "startup failure"):
                companion.watch()
            restore.assert_not_called()
        loop.run.side_effect = lambda: companion.request_stop(15, None)
        with (
            mock.patch.dict(companion.sys.modules, fake_modules),
            mock.patch.object(companion.signal, "signal"),
            mock.patch.object(companion, "restore") as restore,
            mock.patch.object(companion, "apply"),
        ):
            companion.watch()
            restore.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
