# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Report-source precedence and conservative all-corner timing acceptance."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("fit_summary", ROOT / "quartus/fit_summary.py")
SUMMARY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SUMMARY)
CORNERS = ("Slow 1100mV 100C", "Slow 1100mV -40C", "Fast 1100mV 100C", "Fast 1100mV -40C")
REVISION = "fixture"


class FitSummaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.output = self.directory / "summary.json"
        self.write(f"{REVISION}.fit.summary", "Top-level Entity Name : fixture_top\nDevice : 5CSEBA6U23I7\nLogic utilization (in ALMs) : 100 / 41,910\n")

    def write(self, name, text):
        (self.directory / name).write_text(text)

    def diagnostic(self):
        self.write("setup.txt", "Report Timing: Worst case slack is 7.000\n")
        self.write("hold.txt", "Report Timing: Worst case slack is 0.500\n")
        self.write("clocks.txt", "; core_clk ; Base ; 20.000 ; 50.0 MHz ;\n")

    def standard(self, setup=-0.75, hold=-0.125, summary=True, corners=CORNERS):
        rows, tables = [], []
        for where in corners:
            for analysis, value in (("Setup", setup), ("Hold", hold)):
                rows.append(f"Type : {where} Model {analysis} 'core_clk'\nSlack : {value:.3f}\n")
                tables.append(f"; {where} Model {analysis} Summary ;\n; Clock ; Slack ;\n; core_clk ; {value:.3f} ;\n\n")
        if summary:
            self.write(f"{REVISION}.sta.summary", "\n".join(rows))
        self.write(f"{REVISION}.sta.rpt", "; core_clk ; Base ; 15.151515 ; 66.0 MHz ;\n\n" + "".join(tables))

    def run_summary(self, target=False):
        argv = ["fit_summary.py", "--name", "fixture", "--dir", str(self.directory),
                "--revision", REVISION, "--out", str(self.output), "--core-mhz", "66"]
        if target:
            argv += ["--target-period", "15.151515"]
        with patch("sys.argv", argv), patch.object(SUMMARY, "git", return_value=""), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            status = SUMMARY.main()
        data = json.loads(self.output.read_text()) if self.output.exists() else None
        return status, data

    def test_all_corner_summary_overrides_optimistic_diagnostic(self):
        self.diagnostic()
        self.standard()
        self.write(f"{REVISION}.target-paths.tsv", "Slow 1100mV -40C\t-0.75\tlaunch\tlatch\n")
        status, data = self.run_summary(target=True)
        self.assertEqual(status, 0)
        self.assertEqual(data["schema"], 1)
        self.assertEqual(data["clocks_ns"], {"core_clk": 15.151515})
        self.assertEqual(data["core_mhz"], 66)
        self.assertEqual(data["slack"]["core_clk"]["setup"]["slow_-40c"], -0.75)
        self.assertEqual(data["slack"]["core_clk"]["hold"]["fast_-40c"], -0.125)
        self.assertFalse(data["timing_met"])
        self.assertIsNone(data["pass_50mhz"])
        self.assertEqual(data["target"]["mhz"], 66.0)
        self.assertEqual(data["target"]["period_ns"], 15.151515)
        self.assertFalse(data["target"]["met"])

    def test_standard_report_without_summary_preserves_hold_failure(self):
        self.diagnostic()
        self.standard(setup=0.5, hold=-0.125, summary=False)
        status, data = self.run_summary()
        self.assertEqual(status, 0)
        self.assertEqual(data["clocks_ns"]["core_clk"], 15.151515)
        self.assertEqual(set(data["slack"]["core_clk"]["hold"]),
                         {"slow_100c", "slow_-40c", "fast_100c", "fast_-40c"})
        self.assertFalse(data["timing_met"])

    def test_legacy_harness_only_keeps_original_schema_and_period(self):
        self.diagnostic()
        status, data = self.run_summary()
        self.assertEqual(status, 0)
        self.assertEqual(data["slack"], {"core_clk": {"setup": {"default": 7.0}, "hold": {"default": 0.5}}})
        self.assertEqual(data["clocks_ns"], {"core_clk": 20.0})
        self.assertTrue(data["timing_met"])
        self.assertTrue(data["pass_50mhz"])
        self.assertIsNone(data["target"])

    def test_invalid_or_incomplete_standard_never_falls_back(self):
        self.diagnostic()
        for malformed in ("", "unrecognized report\n", "Type : Slow 1100mV 100C Model Setup 'core_clk'\nSlack : N/A\n"):
            with self.subTest(report=malformed):
                self.write(f"{REVISION}.sta.rpt", malformed)
                status, data = self.run_summary()
                self.assertEqual(status, 1)
                self.assertIsNone(data)

    def test_applicable_corner_count_is_not_manufactured(self):
        self.standard(setup=0.5, hold=0.5, corners=CORNERS[:1])
        status, data = self.run_summary()
        self.assertEqual(status, 0)
        self.assertTrue(data["timing_met"])
        self.assertEqual(set(data["slack"]["core_clk"]["setup"]), {"slow_100c"})

    def test_missing_hold_corners_rejects_positive_setup(self):
        self.diagnostic()
        self.standard(setup=0.5, hold=0.5)
        path = self.directory / f"{REVISION}.sta.summary"
        path.write_text(path.read_text().replace("Model Hold", "Model Minimum Pulse Width"))
        status, data = self.run_summary()
        self.assertEqual(status, 1)
        self.assertIsNone(data)

    def test_optional_na_recovery_and_removal_are_not_numeric_slack(self):
        self.standard(setup=0.5, hold=0.5)
        path = self.directory / f"{REVISION}.sta.summary"
        path.write_text(path.read_text() + "Type : Slow 1100mV 100C Model Recovery 'core_clk'\nSlack : N/A\nType : Slow 1100mV 100C Model Removal 'core_clk'\nSlack : N/A\n")
        status, data = self.run_summary()
        self.assertEqual(status, 0)
        self.assertTrue(data["timing_met"])
        self.assertNotIn("recovery", data["slack"]["core_clk"])


if __name__ == "__main__":
    unittest.main()
