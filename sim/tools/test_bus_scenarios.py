#!/usr/bin/env python3
"""Independent checks for bounded Figure 8-13 and 8-15 through 8-19 scenarios."""

from __future__ import annotations

import copy
import json
import subprocess
import sys
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SPEC_DIR = ROOT / "sim/spec"
sys.path.insert(0, str(SPEC_DIR))

import check_bus  # noqa: E402


class BusScenarioTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.path = ROOT / "sim/spec/bus_scenarios.json"
        cls.doc = json.loads(cls.path.read_text(encoding="utf-8"))
        cls.scenario = next(
            item for item in cls.doc["scenarios"]
            if item["id"] == "READ_BURST_TA_WAIT_DRTRY"
        )
        cls.single_delays = next(
            item for item in cls.doc["scenarios"]
            if item["id"] == "READ_SINGLE_DATA_DELAYS"
        )
        cls.write_delays = next(
            item for item in cls.doc["scenarios"]
            if item["id"] == "WRITE_SINGLE_DATA_DELAYS"
        )
        cls.burst_delays = next(
            item for item in cls.doc["scenarios"]
            if item["id"] == "BURST_DATA_DELAYS"
        )
        cls.fastest_reads = next(
            item for item in cls.doc["scenarios"]
            if item["id"] == "READ_SINGLE_FASTEST_PIPELINE"
        )

    def test_selected_figure_profile_and_counts(self) -> None:
        self.assertEqual(
            check_bus.validate_read_burst_ta_drtry(self.doc),
            {"signal_roles": 6, "cycle_rows": 7, "unresolved": 4},
        )
        diagram = next(item for item in self.doc["diagram_inventory"] if item["figure"] == "8-13")
        self.assertEqual(
            (diagram["pdf_page"], diagram["printed_page"], diagram["status"], diagram["scenario_id"]),
            (337, "8-29", "cycle_transcribed", "READ_BURST_TA_WAIT_DRTRY"),
        )
        self.assertEqual(
            [item["figure"] for item in self.doc["diagram_inventory"] if item["status"] == "inventory_only"],
            ["8-3", "8-4", "8-5", "8-16"],
        )

    def test_figure_8_17_profile_and_source_locators(self) -> None:
        self.assertEqual(
            check_bus.validate_single_read_delays(self.doc),
            {"signal_roles": 5, "cycle_rows": 5, "unresolved": 5},
        )
        source = self.single_delays["source"]
        self.assertEqual(source["figure"], "8-17")
        self.assertEqual(source["pdf_pages"][-1], 342)
        self.assertEqual(source["printed_pages"][-1], "8-34")
        self.assertEqual(self.single_delays["mode"]["data_bus_bits"], 64)
        self.assertIn("explicitly labels D[0-63]", self.single_delays["mode"]["data_bus_basis"])
        self.assertIn("TBST is drawn negated", self.single_delays["mode"]["burst"])

    def test_figure_8_17_hand_anchored_delay_observations(self) -> None:
        by_cycle = {item["cycle"]: item for item in self.single_delays["cycles"]}
        clock3 = by_cycle["Figure 8-17 clock 3"]
        clock4 = by_cycle["Figure 8-17 clock 4"]
        clock6 = by_cycle["Figure 8-17 clock 6 (second access)"]
        clock11 = by_cycle["Figure 8-17 clock 11 (third access)"]

        self.assertIn("TA remains logically negated", clock3["after_edge"][0])
        self.assertIn("first stated wait cycle", clock3["after_edge"][0])
        self.assertIn("TA remains logically negated", clock4["after_edge"][0])
        self.assertIn("second stated wait cycle", clock4["after_edge"][0])
        self.assertEqual(clock6["modality"], "counterfactual_source_statement")
        self.assertIn("could have been asserted", clock6["after_edge"][0])
        self.assertIn("not a required assertion", clock6["after_edge"][0])
        self.assertEqual(clock11["transition_relation"], "asserts_during_labeled_cycle")
        self.assertIn("polygon is labeled Bad", clock11["after_edge"][0])

    def test_figure_8_17_sampling_boundary_and_scope_are_explicit(self) -> None:
        clock11, following = self.single_delays["cycles"][-2:]
        self.assertIn("after the left rising boundary", clock11["at_edge"][0])
        self.assertIn("during labeled clock cycle 11", clock11["after_edge"][0])
        self.assertIn("following the depicted within-cycle transition", following["at_edge"][0])
        self.assertIn("no architectural destination or rollback", following["after_edge"][0])
        self.assertTrue(any("not being another load" in item for item in self.single_delays["preconditions"]))
        unresolved = " ".join(self.single_delays["unresolved"])
        self.assertIn("within-cycle waveform transitions", unresolved)
        self.assertIn("not a complete waveform or BFM contract", unresolved)

    def test_figure_8_18_profile_and_source_locators(self) -> None:
        self.assertEqual(
            check_bus.validate_single_write_delays(self.doc),
            {"signal_roles": 5, "cycle_rows": 6, "unresolved": 6},
        )
        source = self.write_delays["source"]
        self.assertEqual(source["figure"], "8-18")
        self.assertEqual(source["pdf_pages"][-1], 343)
        self.assertEqual(source["printed_pages"][-1], "8-35")
        mode = self.write_delays["mode"]
        self.assertEqual(mode["data_bus_bits"], 64)
        self.assertIn("explicitly labels D[0-63]", mode["data_bus_basis"])
        self.assertIn("TT is labeled SBW", mode["transaction_type"])
        self.assertIn("TBST is drawn negated", mode["transaction_type"])

    def test_figure_8_18_hand_anchored_delay_observations(self) -> None:
        by_cycle = {item["cycle"]: item for item in self.write_delays["cycles"]}
        clock3 = by_cycle["Figure 8-18 clock 3"]
        clock4 = by_cycle["Figure 8-18 clock 4"]
        clock6 = by_cycle["Figure 8-18 clock 6 (second access)"]
        final = by_cycle["last-access qualified DBG (relative)"]
        self.assertIn("TA is held logically negated", clock3["after_edge"][0])
        self.assertIn("first stated wait cycle", clock3["after_edge"][0])
        self.assertIn("TA is held logically negated", clock4["after_edge"][0])
        self.assertIn("second stated wait cycle", clock4["after_edge"][0])
        self.assertEqual(clock6["transition_relation"], "DBG_held_negated_during_labeled_cycle")
        self.assertIn("delaying the start", clock6["after_edge"][0])
        self.assertIn("last access as not delayed", final["after_edge"][0])

    def test_figure_8_18_write_roles_and_drtry_boundary(self) -> None:
        roles = self.write_delays["signal_roles"]
        self.assertEqual(roles["data"]["driver"], "603e during each write data tenure")
        self.assertEqual(roles["TA"]["driver"], "responding slave")
        self.assertEqual(roles["DRTRY"]["driver"], "responding slave for reads only")
        self.assertIn("does not use DRTRY", roles["DRTRY"]["sampling"])
        self.assertIn("still prevents a qualified DBG", roles["DRTRY"]["sampling"])
        assertions = " ".join(self.write_delays["assertions"])
        self.assertIn("does not accept, cancel, or complete a write beat", assertions)
        self.assertIn("preceding read can still block a qualified DBG", assertions)
        unresolved = " ".join(self.write_delays["unresolved"])
        self.assertIn("no absolute grant-to-TA latency", unresolved)
        self.assertIn("not a complete waveform or BFM contract", unresolved)

    def test_figure_8_19_profile_and_source_locators(self) -> None:
        self.assertEqual(
            check_bus.validate_burst_data_delays(self.doc),
            {"signal_roles": 8, "cycle_rows": 10, "unresolved": 7},
        )
        source = self.burst_delays["source"]
        self.assertEqual(source["figure"], "8-19")
        self.assertEqual(source["pdf_pages"][-1], 344)
        self.assertEqual(source["printed_pages"][-1], "8-36")
        mode = self.burst_delays["mode"]
        self.assertEqual(mode["data_bus_bits"], 64)
        self.assertEqual(
            mode["operation_order"],
            ["four-beat read burst", "four-beat write burst", "four-beat read burst"],
        )
        self.assertIn("Read, Write, Read", mode["transaction_labels"])
        self.assertIn("TBST is drawn asserted", mode["transaction_labels"])

    def test_figure_8_19_critical_term_and_address_order_are_bounded(self) -> None:
        by_cycle = {item["cycle"]: item for item in self.burst_delays["cycles"]}
        critical = by_cycle["source clock 0 / first read In 0"]
        first_done = by_cycle["first transfer completion (source-relative)"]
        third_address = by_cycle["third transfer address start (source-relative)"]
        self.assertEqual(critical["source_term"], "critical quad word")
        self.assertIn("does not map source clock 0", critical["at_edge"][0])
        self.assertIn("critical-double-word terminology remains unresolved", critical["after_edge"][0])
        self.assertIn("In 0, In 1, In 2, and In 3", first_done["at_edge"][0])
        self.assertIn("Only after the first transfer completes", third_address["at_edge"][0])
        unresolved = " ".join(self.burst_delays["unresolved"])
        self.assertIn("axis labeled 1 through 20", unresolved)
        self.assertIn("critical quad word", unresolved)
        self.assertIn("critical double word", unresolved)

    def test_figure_8_19_write_wait_and_read_retry_sequences(self) -> None:
        labels = [item["cycle"] for item in self.burst_delays["cycles"]]
        out2_wait = labels.index("write burst third beat Out 2 pending")
        out2_done = labels.index("write burst third beat Out 2 accepted")
        in2 = labels.index("final read third beat, first In 2")
        retry = labels.index("final read third beat + 1")
        replacement = labels.index("final read replacement In 2")
        confirmation = labels.index("final read DRTRY negation")
        in3 = labels.index("final read fourth beat In 3 (same or later edge)")
        self.assertEqual(out2_done, out2_wait + 1)
        self.assertEqual(retry, in2 + 1)
        self.assertEqual(replacement, retry + 1)
        self.assertEqual(confirmation, replacement + 1)
        self.assertEqual(in3, confirmation + 1)
        rows = self.burst_delays["cycles"]
        self.assertIn("negates TA", rows[out2_wait]["after_edge"][0])
        self.assertIn("Out 3", rows[out2_done]["after_edge"][0])
        self.assertIn("preceding In 2 is invalidated", rows[retry]["after_edge"][0])
        self.assertIn("replacement In 2", rows[confirmation]["after_edge"][0])
        self.assertIn("same sampling edge", rows[in3]["at_edge"][0])
        self.assertIn("no extra bubble is required", rows[in3]["at_edge"][0])
        self.assertNotIn("later samples", rows[in3]["at_edge"][0])
        roles = self.burst_delays["signal_roles"]
        self.assertEqual(
            roles["data"]["driver"],
            "responding slave for the first and final reads; 603e for the middle write",
        )

    def test_figure_8_15_profile_and_source_locators(self) -> None:
        self.assertEqual(
            check_bus.validate_fastest_single_reads(self.doc),
            {"signal_roles": 8, "cycle_rows": 5, "unresolved": 8},
        )
        source = self.fastest_reads["source"]
        self.assertEqual(source["figure"], "8-15")
        self.assertEqual(source["pdf_pages"][-1], 340)
        self.assertEqual(source["printed_pages"][-1], "8-32")
        mode = self.fastest_reads["mode"]
        self.assertEqual(mode["data_bus_bits"], 64)
        self.assertIn("Read", mode["transaction_labels"])
        self.assertIn("TBST is drawn negated", mode["transaction_labels"])
        self.assertIn("qualitative", mode["timing_scope"])
        self.assertIn("no numeric latency", mode["timing_scope"])

    def test_figure_8_15_latency_throughput_condition_is_not_strengthened(self) -> None:
        by_cycle = {item["cycle"]: item for item in self.fastest_reads["cycles"]}
        first = by_cycle["displayed fastest read 1"]
        second = by_cycle["displayed fastest read 2"]
        below = by_cycle["counterfactual data delay below third-address boundary"]
        boundary = by_cycle["counterfactual data delay reaches third-address boundary"]
        self.assertIn("no address-completion-before-data ordering is implied", first["at_edge"][0])
        self.assertIn("address and data tenure completion may overlap", second["at_edge"][0])
        self.assertEqual(below["modality"], "conditional_source_statement")
        self.assertIn("third address tenure can still proceed without delay", below["at_edge"][0])
        self.assertIn("latency increases", below["after_edge"][0])
        self.assertIn("throughput is not affected", below["after_edge"][0])
        self.assertEqual(boundary["modality"], "conditional_exception_to_unaffected_throughput")
        self.assertIn("third address tenure itself to be delayed", boundary["at_edge"][0])
        self.assertIn("statement no longer applies", boundary["after_edge"][0])
        self.assertIn("no amount of throughput change is specified", boundary["after_edge"][0])
        self.assertNotIn("throughput decreases", boundary["after_edge"][0])

    def test_figure_8_15_mode_roles_and_architectural_limit(self) -> None:
        mode = self.fastest_reads["mode"]
        self.assertIn("bounded profile selects normal", mode["drtry"])
        self.assertIn("selection is not inferred", mode["drtry"])
        self.assertIn("no-DRTRY startup mode is not covered", mode["drtry"])
        roles = self.fastest_reads["signal_roles"]
        self.assertEqual(roles["data"]["driver"], "responding slave during each depicted read")
        self.assertEqual(roles["DRTRY"]["driver"], "responding slave in the selected normal DRTRY profile")
        self.assertIn("one bus clock after TA", roles["DRTRY"]["sampling"])
        unresolved = " ".join(self.fastest_reads["unresolved"])
        self.assertIn("does not state numeric minimum latency", unresolved)
        self.assertIn("does not establish absolute architectural", unresolved)
        self.assertIn("not a complete waveform or BFM contract", unresolved)

    def test_hand_anchored_ta_pacing_observations(self) -> None:
        by_cycle = {item["cycle"]: item for item in self.scenario["cycles"]}
        cycle3 = by_cycle["Figure 8-13 bus clock 3"]
        cycle4 = by_cycle["Figure 8-13 bus clock 4"]
        self.assertIn("does not label the data value or identify the beat sampled", cycle3["at_edge"][0])
        self.assertIn("TA is logically negated", cycle3["after_edge"][0])
        self.assertIn("does not advance", cycle3["after_edge"][0])
        self.assertIn("remains selected", cycle4["at_edge"][0])
        self.assertIn("reasserts TA", cycle4["after_edge"][0])
        self.assertIn("pipeline resumes", cycle4["after_edge"][0])

    def test_drtry_relations_are_relative_and_read_only(self) -> None:
        labels = [item["cycle"] for item in self.scenario["cycles"]]
        provisional = labels.index("provisional TA")
        cancellation = labels.index("provisional TA + 1")
        replacement = labels.index("replacement TA while DRTRY asserted")
        confirmation = labels.index("DRTRY negation")
        self.assertEqual(cancellation, provisional + 1)
        self.assertLess(cancellation, replacement)
        self.assertEqual(confirmation, replacement + 1)
        self.assertEqual(self.scenario["mode"]["operation"], "read_burst")
        self.assertIn("normal late-cancel", self.scenario["mode"]["drtry"])
        self.assertTrue(any("read-only late cancellation" in item for item in self.scenario["assertions"]))

    def test_driver_sampling_and_polarity_are_not_inferred_from_wave_height(self) -> None:
        roles = self.scenario["signal_roles"]
        self.assertEqual(roles["qualified_DBG"]["physical_polarity"], "derived_internal_active_low_condition_as_drawn")
        self.assertEqual(roles["DBB"]["driver"], "603e while it owns this read data tenure")
        self.assertEqual(roles["data"]["driver"], "responding slave during this read")
        self.assertEqual(roles["data"]["physical_polarity"], "encoded_not_asserted_or_negated")
        for signal in ("TA", "DRTRY"):
            self.assertEqual(roles[signal]["physical_polarity"], "active_low")
            self.assertIn("rising SYSCLK edge", roles[signal]["sampling"])

    def test_mode_and_fidelity_limits_remain_explicit(self) -> None:
        self.assertEqual(self.scenario["mode"]["data_bus_bits"], 64)
        self.assertIn(
            "figure 8-13 itself does not print a bus width",
            self.scenario["mode"]["data_bus_basis"].lower(),
        )
        unresolved = " ".join(self.scenario["unresolved"])
        self.assertIn("does not print data values or ordinal labels", unresolved)
        self.assertIn("intra-cycle transitions", unresolved)
        self.assertIn("no TEA waveform row", unresolved)
        self.assertIn("Electrical propagation", unresolved)

    def test_targeted_metadata_mutations_are_rejected(self) -> None:
        def scenario(doc: dict) -> dict:
            return next(item for item in doc["scenarios"] if item["id"] == "READ_BURST_TA_WAIT_DRTRY")

        mutations = []
        for change in (
            lambda doc: next(item for item in doc["diagram_inventory"] if item["figure"] == "8-13").update({"pdf_page": 338}),
            lambda doc: scenario(doc)["source"].update({"printed_pages": ["8-29"]}),
            lambda doc: scenario(doc)["mode"].update({"data_bus_bits": 32}),
            lambda doc: scenario(doc)["signal_roles"]["TA"].update({"physical_polarity": "active_high"}),
            lambda doc: scenario(doc)["signal_roles"]["data"].update({"driver": "603e"}),
            lambda doc: scenario(doc)["cycles"][1]["after_edge"].__setitem__(0, "TA asserted; pipeline advances."),
            lambda doc: scenario(doc)["cycles"].__setitem__(4, scenario(doc)["cycles"][5]),
            lambda doc: scenario(doc)["unresolved"].clear(),
        ):
            changed = copy.deepcopy(self.doc)
            change(changed)
            mutations.append(changed)
        for index, changed in enumerate(mutations):
            with self.subTest(mutation=index):
                with self.assertRaises((AssertionError, StopIteration)):
                    check_bus.validate_read_burst_ta_drtry(changed)

    def test_figure_8_17_targeted_mutations_are_rejected(self) -> None:
        def scenario(doc: dict) -> dict:
            return next(item for item in doc["scenarios"] if item["id"] == "READ_SINGLE_DATA_DELAYS")

        mutations = []
        for change in (
            lambda doc: next(item for item in doc["diagram_inventory"] if item["figure"] == "8-17").update({"printed_page": "8-35"}),
            lambda doc: scenario(doc)["source"].update({"pdf_pages": [342]}),
            lambda doc: scenario(doc)["mode"].update({"data_bus_bits": 32}),
            lambda doc: scenario(doc)["signal_roles"]["DBG"].update({"driver": "603e"}),
            lambda doc: scenario(doc)["signal_roles"]["DRTRY"].update({"physical_polarity": "active_high"}),
            lambda doc: scenario(doc)["cycles"][2].update({"modality": "required_assertion"}),
            lambda doc: scenario(doc)["cycles"][3].update({"transition_relation": "asserted_at_left_edge"}),
            lambda doc: scenario(doc)["cycles"][4]["after_edge"].__setitem__(0, "Bad data was committed and rolled back."),
            lambda doc: scenario(doc)["unresolved"].clear(),
        ):
            changed = copy.deepcopy(self.doc)
            change(changed)
            mutations.append(changed)
        for index, changed in enumerate(mutations):
            with self.subTest(mutation=index):
                with self.assertRaises((AssertionError, StopIteration)):
                    check_bus.validate_single_read_delays(changed)

    def test_figure_8_18_targeted_mutations_are_rejected(self) -> None:
        def scenario(doc: dict) -> dict:
            return next(item for item in doc["scenarios"] if item["id"] == "WRITE_SINGLE_DATA_DELAYS")

        mutations = []
        for change in (
            lambda doc: next(item for item in doc["diagram_inventory"] if item["figure"] == "8-18").update({"pdf_page": 344}),
            lambda doc: scenario(doc)["source"].update({"printed_pages": ["8-35"]}),
            lambda doc: scenario(doc)["mode"].update({"data_bus_bits": 32}),
            lambda doc: scenario(doc)["signal_roles"]["data"].update({"driver": "responding slave"}),
            lambda doc: scenario(doc)["signal_roles"]["DRTRY"].update({"sampling": "DRTRY cancels the write."}),
            lambda doc: scenario(doc)["cycles"][0]["after_edge"].__setitem__(0, "TA acknowledges the beat in clock 3."),
            lambda doc: scenario(doc)["cycles"][2].update({"transition_relation": "DBG_asserted_at_left_edge"}),
            lambda doc: scenario(doc)["cycles"][4]["after_edge"].__setitem__(0, "All writes must complete with fixed latency."),
            lambda doc: scenario(doc)["unresolved"].clear(),
        ):
            changed = copy.deepcopy(self.doc)
            change(changed)
            mutations.append(changed)
        for index, changed in enumerate(mutations):
            with self.subTest(mutation=index):
                with self.assertRaises((AssertionError, StopIteration)):
                    check_bus.validate_single_write_delays(changed)

    def test_figure_8_19_targeted_mutations_are_rejected(self) -> None:
        def scenario(doc: dict) -> dict:
            return next(item for item in doc["scenarios"] if item["id"] == "BURST_DATA_DELAYS")

        mutations = []
        for change in (
            lambda doc: next(item for item in doc["diagram_inventory"] if item["figure"] == "8-19").update({"pdf_page": 345}),
            lambda doc: scenario(doc)["source"].update({"printed_pages": ["8-36"]}),
            lambda doc: scenario(doc)["mode"].update({"data_bus_bits": 32}),
            lambda doc: scenario(doc)["mode"]["operation_order"].__setitem__(1, "four-beat read burst"),
            lambda doc: scenario(doc)["signal_roles"]["data"].update({"driver": "603e for all transfers"}),
            lambda doc: scenario(doc)["cycles"][0].update({"source_term": "critical double word"}),
            lambda doc: scenario(doc)["cycles"][2]["at_edge"].__setitem__(0, "Third address may start before the first transfer completes."),
            lambda doc: scenario(doc)["cycles"][3]["after_edge"].__setitem__(0, "Negated TA advances to Out 3."),
            lambda doc: scenario(doc)["cycles"][6]["after_edge"].__setitem__(0, "DRTRY accepts the first In 2."),
            lambda doc: scenario(doc)["cycles"][9]["at_edge"].__setitem__(0, "603e must wait one extra edge before sampling In 3."),
            lambda doc: scenario(doc)["unresolved"].clear(),
        ):
            changed = copy.deepcopy(self.doc)
            change(changed)
            mutations.append(changed)
        for index, changed in enumerate(mutations):
            with self.subTest(mutation=index):
                with self.assertRaises((AssertionError, StopIteration)):
                    check_bus.validate_burst_data_delays(changed)

    def test_figure_8_15_targeted_mutations_are_rejected(self) -> None:
        def scenario(doc: dict) -> dict:
            return next(item for item in doc["scenarios"] if item["id"] == "READ_SINGLE_FASTEST_PIPELINE")

        mutations = []
        for change in (
            lambda doc: next(item for item in doc["diagram_inventory"] if item["figure"] == "8-15").update({"pdf_page": 341}),
            lambda doc: scenario(doc)["source"].update({"printed_pages": ["8-32"]}),
            lambda doc: scenario(doc)["mode"].update({"data_bus_bits": 32}),
            lambda doc: scenario(doc)["mode"].update({"timing_scope": "fixed three-cycle architectural latency"}),
            lambda doc: scenario(doc)["signal_roles"]["data"].update({"driver": "603e"}),
            lambda doc: scenario(doc)["cycles"][0]["at_edge"].__setitem__(0, "Address tenure must complete before the first data TA."),
            lambda doc: scenario(doc)["cycles"][3].update({"modality": "unconditional"}),
            lambda doc: scenario(doc)["cycles"][3]["after_edge"].__setitem__(0, "Data delay does not increase latency."),
            lambda doc: scenario(doc)["cycles"][4].update({"modality": "throughput_must_decrease"}),
            lambda doc: scenario(doc)["cycles"][4]["after_edge"].__setitem__(0, "Throughput always falls by half."),
            lambda doc: scenario(doc)["unresolved"].clear(),
        ):
            changed = copy.deepcopy(self.doc)
            change(changed)
            mutations.append(changed)
        for index, changed in enumerate(mutations):
            with self.subTest(mutation=index):
                with self.assertRaises((AssertionError, StopIteration)):
                    check_bus.validate_fastest_single_reads(changed)

    def test_full_checker_reports_updated_inventory_deterministically(self) -> None:
        command = [sys.executable, str(SPEC_DIR / "check_bus.py")]
        first = subprocess.run(command, cwd=ROOT, check=True, capture_output=True, text=True).stdout
        second = subprocess.run(command, cwd=ROOT, check=True, capture_output=True, text=True).stdout
        self.assertEqual(first, second)
        self.assertIn("23 figures (4 inventory-only)", first)
        self.assertIn("19 scenarios / 12 cycle tables", first)
        self.assertIn("Figure 8-13 7 rows", first)
        self.assertIn("Figure 8-15 5 rows", first)
        self.assertIn("Figure 8-17 5 rows", first)
        self.assertIn("Figure 8-18 6 rows", first)
        self.assertIn("Figure 8-19 10 rows", first)


if __name__ == "__main__":
    unittest.main(verbosity=2)
