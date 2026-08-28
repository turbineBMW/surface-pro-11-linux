#!/usr/bin/env python3

import csv
import importlib.util
import os
import pathlib
import shutil
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).with_name("validate-external-firmware.py")
SPEC = importlib.util.spec_from_file_location("firmware_validator", SCRIPT)
VALIDATOR = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(VALIDATOR)


class FirmwareValidatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        candidates = [
            pathlib.Path("/run/media/turbinebmw/SP11FW"),
            pathlib.Path("/run/media/turbinebmw/SP11FW/SP11-FIRMWARE"),
        ]
        if os.environ.get("SP11_FIRMWARE_FIXTURE"):
            candidates.insert(0, pathlib.Path(os.environ["SP11_FIRMWARE_FIXTURE"]))
        cls.fixture = next(
            (
                candidate
                for candidate in candidates
                if (candidate / "SP11-FIRMWARE-MANIFEST.tsv").is_file()
            ),
            None,
        )
        if cls.fixture is None:
            raise unittest.SkipTest("SP11FW firmware fixture is not mounted")

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.pack = pathlib.Path(self.temporary.name) / "pack"
        shutil.copytree(self.fixture, self.pack)

    def tearDown(self):
        self.temporary.cleanup()

    def test_legacy_actual_hash_manifest_is_accepted(self):
        self.assertEqual(len(VALIDATOR.validate(self.pack)), 5)

    def test_modified_file_is_rejected(self):
        target = next((self.pack / "usr/lib/firmware").rglob("qcadsp8380.mbn"))
        with target.open("r+b") as output:
            output.seek(4096)
            output.write(b"broken")
        with self.assertRaisesRegex(VALIDATOR.InvalidPack, "hash mismatch"):
            VALIDATOR.validate(self.pack)

    def test_v2_mixed_dsp_packages_are_rejected(self):
        manifest = self.pack / "SP11-FIRMWARE-MANIFEST.tsv"
        with manifest.open(encoding="utf-8-sig", newline="") as source:
            old = list(csv.DictReader(source, delimiter="\t"))
        fields = [
            "manifest_version", "path", "bytes", "sha256", "component",
            "source_package", "selection", "candidate_names", "purpose",
        ]
        with manifest.open("w", encoding="utf-8", newline="") as output:
            writer = csv.DictWriter(output, fields, delimiter="\t")
            writer.writeheader()
            for row in old:
                component = "gpu"
                if "adsp" in row["path"]:
                    component = "adsp"
                elif "cdsp" in row["path"]:
                    component = "cdsp"
                package = f"{component}.inf_qualified"
                if row["path"].endswith("cdsp_dtb.mbn"):
                    package = "cdsp.inf_wrong"
                writer.writerow({
                    **row,
                    "manifest_version": "2",
                    "component": component,
                    "source_package": package,
                    "selection": "structural-review-required",
                })
        with self.assertRaisesRegex(VALIDATOR.InvalidPack, "different driver packages"):
            VALIDATOR.validate(self.pack)


if __name__ == "__main__":
    unittest.main()
