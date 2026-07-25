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


if __name__ == "__main__":
    unittest.main()
