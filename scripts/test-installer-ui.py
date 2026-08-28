#!/usr/bin/env python3

"""Regression tests for the unprivileged interactive installer preview."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
import unittest
from unittest import mock
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
UI = SCRIPT_DIR / "sp11-installer-ui.py"
PLANNER_TESTS = SCRIPT_DIR / "test-install-plan.py"


def load_planner_tests() -> Any:
    specification = importlib.util.spec_from_file_location(
        "sp11_planner_tests", PLANNER_TESTS
    )
    if specification is None or specification.loader is None:
        raise RuntimeError("could not load planner test fixtures")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def load_ui() -> Any:
    specification = importlib.util.spec_from_file_location("sp11_ui", UI)
    if specification is None or specification.loader is None:
        raise RuntimeError("could not load installer UI")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


class InstallerUiTests(unittest.TestCase):
    def test_timezone_menu_selects_region_with_dst(self) -> None:
        ui = load_ui()
        with mock.patch("builtins.input", return_value="2"):
            self.assertEqual(ui.select_timezone(), "America/New_York")

    def test_timezone_menu_rejects_fixed_est_abbreviation(self) -> None:
        ui = load_ui()
        with mock.patch("builtins.input", return_value="EST"):
            with self.assertRaisesRegex(ui.UiError, "region-based timezone"):
                ui.select_timezone()

    def run_ui(
        self, responses: str, *, existing_output: bool = False
    ) -> tuple[subprocess.CompletedProcess[str], str | None]:
        fixtures = load_planner_tests()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            inventory = root / "inventory.json"
            output = root / "plan.json"
            inventory.write_text(
                json.dumps(fixtures.factory_inventory()),
                encoding="utf-8",
            )
            if existing_output:
                output.write_text("do not replace\n", encoding="utf-8")
            result = subprocess.run(
                [
                    str(UI),
                    "--inventory-json",
                    str(inventory),
                    "--output",
                    str(output),
                    "--no-final-prompt",
                ],
                input=responses,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )
            saved = output.read_text(encoding="utf-8") if output.exists() else None
            return result, saved

    def test_dual_boot_preview_saves_non_executable_plan(self) -> None:
        result, saved = self.run_ui("1\n1\nSAVE\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("planning preview", result.stdout)
        self.assertIn("No disk, partition", result.stdout)
        self.assertIn("Physical installation is not enabled", result.stdout)
        self.assertIsNotNone(saved)
        plan = json.loads(saved or "")
        self.assertEqual(plan["mode"], "dual-boot")
        self.assertFalse(plan["execution_eligible"])
        self.assertEqual(
            plan["executor_status"], "held-disposable-loop-only"
        )

    def test_wipe_preview_requires_exact_save_word(self) -> None:
        result, saved = self.run_ui("1\n2\nsave\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("plan was not saved", result.stderr)
        self.assertIsNone(saved)

    def test_existing_output_is_never_replaced(self) -> None:
        result, saved = self.run_ui(
            "1\n1\nSAVE\n", existing_output=True
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing to replace existing plan", result.stderr)
        self.assertEqual(saved, "do not replace\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
