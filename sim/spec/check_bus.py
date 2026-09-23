#!/usr/bin/env python3
"""Structural and source-locator checks for the Chapter 7/8 bus manifests."""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SIGNALS_PATH = ROOT / "sim/spec/bus_signals.json"
SCENARIOS_PATH = ROOT / "sim/spec/bus_scenarios.json"
ENCODINGS_PATH = ROOT / "sim/spec/bus_encodings.json"
sys.path.insert(0, str(ROOT / "sim/tools"))
import bus_decode  # noqa: E402


def load(path: Path) -> dict:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def pages(source: dict) -> list[int]:
    if "pdf_page" in source:
        return [source["pdf_page"]]
    return source.get("pdf_pages", [])


def validate_read_burst_ta_drtry(doc: dict) -> dict[str, int]:
    """Validate the bounded Figure 8-13 transcription and its fidelity limits."""
    diagram = next(item for item in doc["diagram_inventory"] if item["figure"] == "8-13")
    assert diagram == {
        "figure": "8-13",
        "title": "Read Burst with TA Wait States and DRTRY",
        "pdf_page": 337,
        "printed_page": "8-29",
        "status": "cycle_transcribed",
        "scenario_id": "READ_BURST_TA_WAIT_DRTRY",
    }
    scenario = next(item for item in doc["scenarios"] if item["id"] == diagram["scenario_id"])
    assert scenario["status"] == "cycle_table"
    assert scenario["topics"] == ["read", "burst", "TA", "DRTRY", "wait_state", "data_tenure"]
    assert scenario["source"] == {
        "sections": ["8.4.4.1", "8.4.4.2", "7.2.6.1", "7.2.6.3", "7.2.7.1", "7.2.8.1", "7.2.8.2"],
        "figure": "8-13",
        "pdf_pages": [336, 337],
        "printed_pages": ["8-28", "8-29"],
        "visually_checked": True,
    }
    assert scenario["mode"] == {
        "data_bus_bits": 64,
        "data_bus_basis": "surrounding Section 8.4.4.1 four-beat normal-burst context; Figure 8-13 itself does not print a bus width",
        "operation": "read_burst",
        "drtry": "normal late-cancel mode; no-DRTRY startup mode is excluded",
        "program_transaction_beats": 4,
    }

    roles = scenario["signal_roles"]
    assert list(roles) == ["TS", "qualified_DBG", "DBB", "data", "TA", "DRTRY"]
    assert roles["TS"]["physical_polarity"] == "active_low"
    assert roles["qualified_DBG"]["physical_polarity"] == "derived_internal_active_low_condition_as_drawn"
    assert "internal qualified condition" in roles["qualified_DBG"]["driver"]
    assert roles["DBB"]["driver"] == "603e while it owns this read data tenure"
    assert roles["data"]["driver"] == "responding slave during this read"
    assert roles["data"]["physical_polarity"] == "encoded_not_asserted_or_negated"
    for signal in ("TA", "DRTRY"):
        assert roles[signal]["physical_polarity"] == "active_low"
        assert roles[signal]["driver"].startswith("responding slave")
        assert "rising SYSCLK edge" in roles[signal]["sampling"]
    assert "preceding bus clock" in roles["DRTRY"]["sampling"]

    labels = [row["cycle"] for row in scenario["cycles"]]
    assert labels == [
        "qualified DBG",
        "Figure 8-13 bus clock 3",
        "Figure 8-13 bus clock 4",
        "provisional TA",
        "provisional TA + 1",
        "replacement TA while DRTRY asserted",
        "DRTRY negation",
    ]
    cycle3, cycle4 = scenario["cycles"][1:3]
    assert cycle3["at_edge"] == [
        "The figure does not label the data value or identify the beat sampled at this edge."
    ]
    assert cycle3["after_edge"] == [
        "TA is logically negated during labeled bus clock cycle 3, inserting a wait so the data pipeline does not advance."
    ]
    assert cycle4["at_edge"] == [
        "The pending second beat remains selected after the cycle-3 wait."
    ]
    assert cycle4["after_edge"] == [
        "The responder reasserts TA during labeled bus clock cycle 4 and the data pipeline resumes."
    ]
    assert scenario["cycles"][4]["at_edge"] == ["603e samples DRTRY asserted."]
    assert "preceding bus clock is invalidated" in scenario["cycles"][4]["after_edge"][0]
    assert "while DRTRY remains asserted" in scenario["cycles"][5]["at_edge"][0]
    assert "preceding clock becomes valid" in scenario["cycles"][6]["after_edge"][0]

    assert len(scenario["preconditions"]) == 4
    assert any("TEA remains negated" in item for item in scenario["preconditions"])
    assert len(scenario["assertions"]) == 6
    assert any("cycle 3" in item and "cycle 4" in item for item in scenario["assertions"])
    assert len(scenario["unresolved"]) == 4
    assert any("does not print data values or ordinal labels" in item for item in scenario["unresolved"])
    assert any("no TEA waveform row" in item for item in scenario["unresolved"])
    assert any("intra-cycle transitions" in item for item in scenario["unresolved"])
    return {"signal_roles": len(roles), "cycle_rows": len(labels), "unresolved": len(scenario["unresolved"])}


def validate_single_read_delays(doc: dict) -> dict[str, int]:
    """Validate the bounded Figure 8-17 data-delay transcription."""
    diagram = next(item for item in doc["diagram_inventory"] if item["figure"] == "8-17")
    assert diagram == {
        "figure": "8-17",
        "title": "Single-Beat Reads Showing Data-Delay Controls",
        "pdf_page": 342,
        "printed_page": "8-34",
        "status": "cycle_transcribed",
        "scenario_id": "READ_SINGLE_DATA_DELAYS",
    }
    scenario = next(item for item in doc["scenarios"] if item["id"] == diagram["scenario_id"])
    assert scenario["status"] == "cycle_table"
    assert scenario["topics"] == [
        "read", "single_beat", "pipelining", "DBG", "TA", "DRTRY", "wait_state", "data_tenure"
    ]
    assert scenario["source"] == {
        "sections": ["8.5", "7.2.6.1", "7.2.6.3", "7.2.7.1", "7.2.8.1", "7.2.8.2"],
        "figure": "8-17",
        "pdf_pages": [292, 293, 295, 297, 298, 342],
        "printed_pages": ["7-16", "7-17", "7-19", "7-21", "7-22", "8-34"],
        "visually_checked": True,
    }
    assert scenario["mode"] == {
        "data_bus_bits": 64,
        "data_bus_basis": "Figure 8-17 explicitly labels D[0-63]",
        "operation": "three pipelined single-beat reads",
        "burst": "TBST is drawn negated for each address tenure",
        "drtry": "normal late-cancel mode; no-DRTRY startup mode is excluded",
    }

    roles = scenario["signal_roles"]
    assert list(roles) == ["DBG", "DBB", "data", "TA", "DRTRY"]
    assert roles["DBG"]["driver"] == "external data-bus arbiter"
    assert "qualified only while DBB, DRTRY" in roles["DBG"]["sampling"]
    assert roles["DBB"]["driver"] == "603e while it owns each depicted read data tenure"
    assert roles["data"]["driver"] == "responding slave during each read"
    assert "Bad and In are source labels" in roles["data"]["sampling"]
    assert roles["data"]["physical_polarity"] == "encoded_not_asserted_or_negated"
    for signal in ("DBG", "DBB", "TA", "DRTRY"):
        assert roles[signal]["physical_polarity"] == "active_low"
    for signal in ("DBG", "TA", "DRTRY"):
        assert "rising SYSCLK edge" in roles[signal]["sampling"]

    labels = [row["cycle"] for row in scenario["cycles"]]
    assert labels == [
        "Figure 8-17 clock 3",
        "Figure 8-17 clock 4",
        "Figure 8-17 clock 6 (second access)",
        "Figure 8-17 clock 11 (third access)",
        "first sampling edge after clock-11 DRTRY assertion",
    ]
    clock3, clock4, clock6, clock11, post11 = scenario["cycles"]
    assert "not used to assign a TA value" in clock3["at_edge"][0]
    assert "TA remains logically negated" in clock3["after_edge"][0]
    assert "first stated wait cycle" in clock3["after_edge"][0]
    assert "remains pending" in clock4["at_edge"][0]
    assert "second stated wait cycle" in clock4["after_edge"][0]
    assert clock6["modality"] == "counterfactual_source_statement"
    assert "does not state" in clock6["at_edge"][0]
    assert "could have been asserted" in clock6["after_edge"][0]
    assert "not a required assertion" in clock6["after_edge"][0]
    assert clock11["transition_relation"] == "asserts_during_labeled_cycle"
    assert "after the left rising boundary" in clock11["at_edge"][0]
    assert "during labeled clock cycle 11" in clock11["after_edge"][0]
    assert "polygon is labeled Bad" in clock11["after_edge"][0]
    assert "following the depicted within-cycle transition" in post11["at_edge"][0]
    assert "no architectural destination or rollback" in post11["after_edge"][0]

    assert len(scenario["preconditions"]) == 5
    assert any("not being another load" in item for item in scenario["preconditions"])
    assert any("ARTRY and TEA remain negated" in item for item in scenario["preconditions"])
    assert len(scenario["assertions"]) == 7
    assert any("explicitly counterfactual" in item for item in scenario["assertions"])
    assert any("not at clock 11's left boundary" in item for item in scenario["assertions"])
    assert any("does not by itself specify" in item for item in scenario["assertions"])
    assert len(scenario["unresolved"]) == 5
    assert any("not inferred from within-cycle waveform transitions" in item for item in scenario["unresolved"])
    assert any("not a complete waveform or BFM contract" in item for item in scenario["unresolved"])
    return {"signal_roles": len(roles), "cycle_rows": len(labels), "unresolved": len(scenario["unresolved"])}


def validate_single_write_delays(doc: dict) -> dict[str, int]:
    """Validate the bounded Figure 8-18 data-delay transcription."""
    diagram = next(item for item in doc["diagram_inventory"] if item["figure"] == "8-18")
    assert diagram == {
        "figure": "8-18",
        "title": "Single-Beat Writes Showing Data Delay Controls",
        "pdf_page": 343,
        "printed_page": "8-35",
        "status": "cycle_transcribed",
        "scenario_id": "WRITE_SINGLE_DATA_DELAYS",
    }
    scenario = next(item for item in doc["scenarios"] if item["id"] == diagram["scenario_id"])
    assert scenario["status"] == "cycle_table"
    assert scenario["topics"] == [
        "write", "single_beat", "pipelining", "DBG", "TA", "DRTRY", "wait_state", "data_tenure"
    ]
    assert scenario["source"] == {
        "sections": ["8.5", "8.4.4.1", "7.2.6.1", "7.2.6.3", "7.2.7.1", "7.2.8.1", "7.2.8.2"],
        "figure": "8-18",
        "pdf_pages": [292, 293, 295, 297, 298, 336, 343],
        "printed_pages": ["7-16", "7-17", "7-19", "7-21", "7-22", "8-28", "8-35"],
        "visually_checked": True,
    }
    assert scenario["mode"] == {
        "data_bus_bits": 64,
        "data_bus_basis": "Figure 8-18 explicitly labels D[0-63]",
        "operation": "three pipelined single-beat writes",
        "transaction_type": "TT is labeled SBW and TBST is drawn negated for each address tenure",
        "drtry": "ignored for write completion; Figure 8-18 draws DRTRY negated",
    }

    roles = scenario["signal_roles"]
    assert list(roles) == ["DBG", "DBB", "data", "TA", "DRTRY"]
    assert roles["DBG"]["driver"] == "external data-bus arbiter"
    assert "qualified only while DBB, DRTRY" in roles["DBG"]["sampling"]
    assert roles["DBB"]["driver"] == "603e while it owns each depicted write data tenure"
    assert roles["data"]["driver"] == "603e during each write data tenure"
    assert "Out is a source direction label" in roles["data"]["sampling"]
    assert roles["data"]["physical_polarity"] == "encoded_not_asserted_or_negated"
    assert roles["DRTRY"]["driver"] == "responding slave for reads only"
    assert "does not use DRTRY" in roles["DRTRY"]["sampling"]
    assert "still prevents a qualified DBG" in roles["DRTRY"]["sampling"]
    for signal in ("DBG", "DBB", "TA", "DRTRY"):
        assert roles[signal]["physical_polarity"] == "active_low"
    for signal in ("DBG", "TA"):
        assert "rising SYSCLK edge" in roles[signal]["sampling"]

    labels = [row["cycle"] for row in scenario["cycles"]]
    assert labels == [
        "Figure 8-18 clock 3",
        "Figure 8-18 clock 4",
        "Figure 8-18 clock 6 (second access)",
        "second-access qualified DBG after clock 6",
        "last-access qualified DBG (relative)",
        "last-access TA (relative)",
    ]
    clock3, clock4, clock6, post6, last_dbg, last_ta = scenario["cycles"]
    assert "not used to assign a TA value" in clock3["at_edge"][0]
    assert "TA is held logically negated" in clock3["after_edge"][0]
    assert "first stated wait cycle" in clock3["after_edge"][0]
    assert "remains pending" in clock4["at_edge"][0]
    assert "same write beat remains pending" in clock4["after_edge"][0]
    assert clock6["transition_relation"] == "DBG_held_negated_during_labeled_cycle"
    assert "not used to assign a DBG value" in clock6["at_edge"][0]
    assert "delaying the start" in clock6["after_edge"][0]
    assert "assigns no numeric figure clock" in post6["at_edge"][0]
    assert "begins driving the second single write beat" in post6["after_edge"][0]
    assert "source describes this last access as not delayed" in last_dbg["after_edge"][0]
    assert "DRTRY has no write-completion role" in last_ta["after_edge"][0]

    assert len(scenario["preconditions"]) == 4
    assert any("three processor address tenures labeled SBW" in item for item in scenario["preconditions"])
    assert any("ARTRY and TEA remain negated" in item for item in scenario["preconditions"])
    assert len(scenario["assertions"]) == 8
    assert any("does not define a general absolute latency" in item for item in scenario["assertions"])
    assert any("DRTRY is valid only for reads" in item for item in scenario["assertions"])
    assert any("preceding read can still block a qualified DBG" in item for item in scenario["assertions"])
    assert len(scenario["unresolved"]) == 6
    assert any("not inferred from within-cycle waveform transitions" in item for item in scenario["unresolved"])
    assert any("no absolute grant-to-TA latency" in item for item in scenario["unresolved"])
    assert any("not a complete waveform or BFM contract" in item for item in scenario["unresolved"])
    return {"signal_roles": len(roles), "cycle_rows": len(labels), "unresolved": len(scenario["unresolved"])}


def validate_burst_data_delays(doc: dict) -> dict[str, int]:
    """Validate the bounded Figure 8-19 mixed-burst transcription."""
    diagram = next(item for item in doc["diagram_inventory"] if item["figure"] == "8-19")
    assert diagram == {
        "figure": "8-19",
        "title": "Burst Transfers with Data Delay Controls",
        "pdf_page": 344,
        "printed_page": "8-36",
        "status": "cycle_transcribed",
        "scenario_id": "BURST_DATA_DELAYS",
    }
    scenario = next(item for item in doc["scenarios"] if item["id"] == diagram["scenario_id"])
    assert scenario["status"] == "cycle_table"
    assert scenario["topics"] == [
        "read", "write", "burst", "pipelining", "address_tenure", "data_tenure", "TA", "DRTRY", "wait_state"
    ]
    assert scenario["source"] == {
        "sections": [
            "8.5", "8.4.3", "8.4.4", "8.4.4.1", "7.2.2.1", "7.2.3.1",
            "7.2.4.3", "7.2.6.1", "7.2.6.3", "7.2.7.1", "7.2.8.1", "7.2.8.2",
        ],
        "figure": "8-19",
        "pdf_pages": [282, 283, 289, 292, 293, 295, 297, 298, 332, 333, 335, 336, 344],
        "printed_pages": [
            "7-6", "7-7", "7-13", "7-16", "7-17", "7-19", "7-21", "7-22",
            "8-24", "8-25", "8-27", "8-28", "8-36",
        ],
        "visually_checked": True,
    }
    assert scenario["mode"] == {
        "data_bus_bits": 64,
        "data_bus_basis": "Figure 8-19 explicitly labels D[0-63]",
        "operation_order": ["four-beat read burst", "four-beat write burst", "four-beat read burst"],
        "transaction_labels": "TT is labeled Read, Write, Read and TBST is drawn asserted for all three address tenures",
        "drtry": "normal late-cancel mode; the final read's DRTRY assertion excludes no-DRTRY startup mode",
    }

    roles = scenario["signal_roles"]
    assert list(roles) == ["TS", "address", "TBST", "DBG", "DBB", "data", "TA", "DRTRY"]
    assert roles["TS"]["driver"] == "603e while it is the address-bus master"
    assert roles["address"]["driver"] == "603e during each depicted address tenure"
    assert "third-address ordering constraint" in roles["address"]["sampling"]
    assert roles["TBST"]["driver"] == "603e during each depicted address tenure"
    assert "cache-line burst indication" in roles["TBST"]["sampling"]
    assert roles["DBG"]["driver"] == "external data-bus arbiter"
    assert "qualified only while DBB, DRTRY" in roles["DBG"]["sampling"]
    assert roles["DBB"]["driver"] == "603e while it owns each depicted data tenure"
    assert roles["data"]["driver"] == "responding slave for the first and final reads; 603e for the middle write"
    assert roles["data"]["physical_polarity"] == "encoded_not_asserted_or_negated"
    assert roles["TA"]["driver"] == "responding slave"
    assert roles["DRTRY"]["driver"] == "responding slave for reads only"
    for signal in ("TS", "TBST", "DBG", "DBB", "TA", "DRTRY"):
        assert roles[signal]["physical_polarity"] == "active_low"
    for signal in ("DBG", "TA", "DRTRY"):
        assert "rising SYSCLK edge" in roles[signal]["sampling"]

    labels = [row["cycle"] for row in scenario["cycles"]]
    assert labels == [
        "source clock 0 / first read In 0",
        "first transfer completion (source-relative)",
        "third transfer address start (source-relative)",
        "write burst third beat Out 2 pending",
        "write burst third beat Out 2 accepted",
        "final read third beat, first In 2",
        "final read third beat + 1",
        "final read replacement In 2",
        "final read DRTRY negation",
        "final read fourth beat In 3 (same or later edge)",
    ]
    critical, first_done, third_address, out2_wait, out2_ta, in2, retry, replacement, confirm, in3 = scenario["cycles"]
    assert critical["source_term"] == "critical quad word"
    assert "does not map source clock 0" in critical["at_edge"][0]
    assert "critical-double-word terminology remains unresolved" in critical["after_edge"][0]
    assert "four labeled beats In 0, In 1, In 2, and In 3" in first_done["at_edge"][0]
    assert "Only after the first transfer completes" in third_address["at_edge"][0]
    assert "no numeric figure edge is assigned" in third_address["after_edge"][0]
    assert "third labeled beat, Out 2" in out2_wait["at_edge"][0]
    assert "negates TA" in out2_wait["after_edge"][0]
    assert "samples TA asserted for Out 2" in out2_ta["at_edge"][0]
    assert "advances to its fourth labeled beat, Out 3" in out2_ta["after_edge"][0]
    assert "first presentation" in in2["at_edge"][0]
    assert "following DRTRY sample" in in2["after_edge"][0]
    assert "one bus clock after the first In 2 TA" in retry["at_edge"][0]
    assert "preceding In 2 is invalidated" in retry["after_edge"][0]
    assert "repeated In 2 with TA" in replacement["at_edge"][0]
    assert "prepares to negate DRTRY" in replacement["after_edge"][0]
    assert confirm["at_edge"] == ["603e samples DRTRY negated."]
    assert "replacement In 2" in confirm["after_edge"][0]
    assert "same sampling edge" in in3["at_edge"][0]
    assert "no extra bubble is required" in in3["at_edge"][0]

    assert len(scenario["preconditions"]) == 5
    assert any("ordered read, write, read" in item for item in scenario["preconditions"])
    assert any("ARTRY and TEA remain negated" in item for item in scenario["preconditions"])
    assert len(scenario["assertions"]) == 10
    assert any("critical double word" in item and "preserves" in item for item in scenario["assertions"])
    assert any("cannot begin before the first transfer completes" in item for item in scenario["assertions"])
    assert any("presented twice" in item for item in scenario["assertions"])
    assert any("may coincide with DRTRY negation" in item and "extra bubble" in item for item in scenario["assertions"])
    assert len(scenario["unresolved"]) == 7
    assert any("critical quad word" in item and "critical double word" in item for item in scenario["unresolved"])
    assert any("axis labeled 1 through 20" in item for item in scenario["unresolved"])
    assert any("not a complete waveform or BFM contract" in item for item in scenario["unresolved"])
    return {"signal_roles": len(roles), "cycle_rows": len(labels), "unresolved": len(scenario["unresolved"])}


def validate_fastest_single_reads(doc: dict) -> dict[str, int]:
    """Validate the bounded Figure 8-15 latency/throughput transcription."""
    diagram = next(item for item in doc["diagram_inventory"] if item["figure"] == "8-15")
    assert diagram == {
        "figure": "8-15",
        "title": "Fastest Single-Beat Reads",
        "pdf_page": 340,
        "printed_page": "8-32",
        "status": "cycle_transcribed",
        "scenario_id": "READ_SINGLE_FASTEST_PIPELINE",
    }
    scenario = next(item for item in doc["scenarios"] if item["id"] == diagram["scenario_id"])
    assert scenario["status"] == "cycle_table"
    assert scenario["topics"] == [
        "read", "single_beat", "pipelining", "address_tenure", "data_tenure", "latency", "throughput", "TA"
    ]
    assert scenario["source"] == {
        "sections": [
            "8.5", "8.2.2", "8.4.3", "8.4.4.1", "7.2.2.1", "7.2.3.1",
            "7.2.4.3", "7.2.6.1", "7.2.6.3", "7.2.7.1", "7.2.8.1", "7.2.8.2",
        ],
        "figure": "8-15",
        "pdf_pages": [282, 283, 289, 292, 293, 295, 297, 298, 316, 332, 334, 340],
        "printed_pages": [
            "7-6", "7-7", "7-13", "7-16", "7-17", "7-19", "7-21", "7-22",
            "8-8", "8-24", "8-26", "8-32",
        ],
        "visually_checked": True,
    }
    assert scenario["mode"] == {
        "data_bus_bits": 64,
        "data_bus_basis": "Figure 8-15 explicitly labels D[0-63]",
        "operation": "three pipelined single-beat reads",
        "transaction_labels": "TT is labeled Read and TBST is drawn negated for all three address tenures",
        "drtry": "bounded profile selects normal late-confirmation mode; this selection is not inferred from Figure 8-15's negated DRTRY trace, and no-DRTRY startup mode is not covered",
        "timing_scope": "qualitative fastest/minimum-latency/maximum-throughput example; no numeric latency or cadence is generalized",
    }

    roles = scenario["signal_roles"]
    assert list(roles) == ["TS", "address", "TBST", "DBG", "DBB", "data", "TA", "DRTRY"]
    assert roles["TS"]["driver"] == "603e while it is the address-bus master"
    assert roles["address"]["driver"] == "603e during each depicted address tenure"
    assert "throughput-boundary event" in roles["address"]["sampling"]
    assert roles["TBST"]["driver"] == "603e during each depicted address tenure"
    assert "negated TBST" in roles["TBST"]["sampling"]
    assert roles["DBG"]["driver"] == "external data-bus arbiter"
    assert "qualified only while DBB, DRTRY" in roles["DBG"]["sampling"]
    assert roles["DBB"]["driver"] == "603e while it owns each depicted read data tenure"
    assert roles["data"]["driver"] == "responding slave during each depicted read"
    assert "In is a source direction label" in roles["data"]["sampling"]
    assert roles["TA"]["driver"] == "responding slave"
    assert roles["DRTRY"]["driver"] == "responding slave in the selected normal DRTRY profile"
    assert "trace alone does not identify startup mode" in roles["DRTRY"]["sampling"]
    for signal in ("TS", "TBST", "DBG", "DBB", "TA", "DRTRY"):
        assert roles[signal]["physical_polarity"] == "active_low"
    for signal in ("DBG", "TA"):
        assert "rising SYSCLK edge" in roles[signal]["sampling"]

    labels = [row["cycle"] for row in scenario["cycles"]]
    assert labels == [
        "displayed fastest read 1",
        "displayed fastest read 2",
        "displayed fastest read 3",
        "counterfactual data delay below third-address boundary",
        "counterfactual data delay reaches third-address boundary",
    ]
    first, second, third, below, boundary = scenario["cycles"]
    assert "samples the first In data with TA" in first["at_edge"][0]
    assert "no address-completion-before-data ordering is implied" in first["at_edge"][0]
    assert "minimum-latency pattern" in first["after_edge"][0]
    assert "address and data tenure completion may overlap" in second["at_edge"][0]
    assert "without a source-described data wait" in second["after_edge"][0]
    assert "address tenure was not delayed by prior data latency" in third["at_edge"][0]
    assert "maximum-throughput example" in third["after_edge"][0]
    assert below["modality"] == "conditional_source_statement"
    assert "third address tenure can still proceed without delay" in below["at_edge"][0]
    assert "latency increases" in below["after_edge"][0]
    assert "overall throughput is not affected" in below["after_edge"][0]
    assert boundary["modality"] == "conditional_exception_to_unaffected_throughput"
    assert "causes the third address tenure itself to be delayed" in boundary["at_edge"][0]
    assert "unaffected-throughput statement no longer applies" in boundary["after_edge"][0]
    assert "no amount of throughput change is specified" in boundary["after_edge"][0]

    assert len(scenario["preconditions"]) == 6
    assert any("source-labeled fastest sequence" in item for item in scenario["preconditions"])
    assert any("bounded profile selects normal DRTRY mode" in item for item in scenario["preconditions"])
    assert any("ARTRY, DRTRY, and TEA remain negated" in item for item in scenario["preconditions"])
    assert len(scenario["assertions"]) == 11
    assert any("not numeric timing bounds" in item for item in scenario["assertions"])
    assert any("leaves the third address tenure undelayed" in item for item in scenario["assertions"])
    assert any("does not quantify the impact" in item for item in scenario["assertions"])
    assert any("do not require address completion before data acceptance" in item for item in scenario["assertions"])
    assert any("does not expose internal delivery timing" in item for item in scenario["assertions"])
    assert len(scenario["unresolved"]) == 8
    assert any("does not state numeric minimum latency" in item for item in scenario["unresolved"])
    assert any("trace alone does not distinguish normal from no-DRTRY" in item for item in scenario["unresolved"])
    assert any("does not establish absolute architectural" in item for item in scenario["unresolved"])
    assert any("not a complete waveform or BFM contract" in item for item in scenario["unresolved"])
    return {"signal_roles": len(roles), "cycle_rows": len(labels), "unresolved": len(scenario["unresolved"])}


signals_doc = load(SIGNALS_PATH)
scenarios_doc = load(SCENARIOS_PATH)
encodings_doc = load(ENCODINGS_PATH)
signals = signals_doc["signals"]
diagrams = scenarios_doc["diagram_inventory"]
scenarios = scenarios_doc["scenarios"]

expected_signal_ids = {
    "BR", "BG", "ABB", "TS", "A", "AP", "APE", "TT", "TBST", "TSIZ",
    "GBL", "CI", "WT", "CSE", "TC", "AACK", "ARTRY", "SYSCLK", "CLK_OUT",
    "PLL_CFG", "DBG", "DBWO", "DBB", "DH", "DL", "DP", "DPE", "DBDIS",
    "TA", "DRTRY", "TEA", "INT", "SMI", "MCP", "CKSTP_IN", "CKSTP_OUT",
    "HRESET", "SRESET", "RSRV", "QREQ", "QACK", "TBEN", "TLBISYNC", "TDI",
    "TDO", "TMS", "TCK", "TRST", "TEST", "VDD", "OVDD", "AVDD", "GND",
    "OGND",
}
active_low_ids = {
    "BR", "BG", "ABB", "TS", "APE", "TBST", "GBL", "CI", "WT", "AACK",
    "ARTRY", "DBG", "DBWO", "DBB", "DPE", "DBDIS", "TA", "DRTRY", "TEA",
    "INT", "SMI", "MCP", "CKSTP_IN", "CKSTP_OUT", "HRESET", "SRESET", "RSRV",
    "QREQ", "QACK", "TBEN", "TLBISYNC", "TRST",
}
required_topics = {
    "address_tenure", "data_tenure", "qualified_grant", "ARTRY", "DRTRY", "TEA",
    "burst", "32_bit", "DBWO", "snoop", "data_ordering",
}
expected_figure_pages = {
    "8-1": 311, "8-2": 313, "8-3": 314, "8-4": 318, "8-5": 319,
    "8-6": 320, "8-7": 330, "8-8": 331, "8-9": 334, "8-10": 335,
    "8-11": 335, "8-12": 336, "8-13": 337, "8-14": 339, "8-15": 340,
    "8-16": 341, "8-17": 342, "8-18": 343, "8-19": 344, "8-20": 345,
    "8-21": 347, "8-22": 347, "8-23": 352,
}
known_signal_pages = {
    "BR": 280, "BG": 281, "TS": 282, "A": 283, "AP": 284, "APE": 284,
    "AACK": 290, "ARTRY": 290, "DBG": 292, "DBWO": 292, "DBB": 292,
    "TA": 297, "DRTRY": 298, "TEA": 299, "HRESET": 301, "QACK": 302,
    "TLBISYNC": 303, "SYSCLK": 306, "PLL_CFG": 306, "VDD": 308,
}

ids = [signal["id"] for signal in signals]
assert len(ids) == len(set(ids)), "duplicate signal id"
assert set(ids) == expected_signal_ids, "Chapter 7/Figure 7-1 signal group mismatch"
assert sum(signal["width"] for signal in signals) == 170
assert all(isinstance(signal["width"], int) and signal["width"] > 0 for signal in signals)
assert {signal["id"] for signal in signals if signal["active_level"] == "low"} == active_low_ids

oe_classes = set(signals_doc["oe_classes"])
for signal in signals:
    assert signal["oe_class"] in oe_classes, f"unknown OE class: {signal['id']}"
    assert signal["source"].get("visual") is True, f"unverified polarity/direction: {signal['id']}"
    assert pages(signal["source"]), f"missing source page: {signal['id']}"
    assert all(277 <= page <= 354 for page in pages(signal["source"])), signal["id"]
    if signal["direction"] == "input":
        assert signal["oe_class"] == "none", f"input drives bus: {signal['id']}"
for signal_id, page in known_signal_pages.items():
    source = next(signal["source"] for signal in signals if signal["id"] == signal_id)
    assert page in pages(source), f"bad locator for {signal_id}"

figures = [diagram["figure"] for diagram in diagrams]
assert figures == [f"8-{number}" for number in range(1, 24)]
assert {diagram["figure"]: diagram["pdf_page"] for diagram in diagrams} == expected_figure_pages
status_counts = Counter(diagram["status"] for diagram in diagrams)
assert status_counts == {
    "context_only": 1,
    "notation_used": 1,
    "inventory_only": 4,
    "cycle_transcribed": 12,
    "rule_transcribed": 5,
}

scenario_ids = [scenario["id"] for scenario in scenarios]
assert len(scenario_ids) == len(set(scenario_ids)) == 19
scenario_id_set = set(scenario_ids)
for diagram in diagrams:
    if "scenario_id" in diagram:
        assert diagram["scenario_id"] in scenario_id_set, diagram["figure"]

topics = {topic for scenario in scenarios for topic in scenario["topics"]}
assert required_topics <= topics, f"missing required topics: {required_topics - topics}"
cycle_scenarios = [scenario for scenario in scenarios if scenario["status"] == "cycle_table"]
assert len(cycle_scenarios) == 12
for scenario in cycle_scenarios:
    assert scenario["source"].get("visually_checked") is True, scenario["id"]
    assert len(scenario["cycles"]) >= 3, scenario["id"]
    for cycle in scenario["cycles"]:
        assert cycle["cycle"] and cycle["at_edge"] and cycle["after_edge"], scenario["id"]

source_checks = {
    "ADDR_MIN_64": ("8-6", 320),
    "ADDR_ARTRY_SNOOP": ("8-7", 330),
    "READ_SINGLE_NORMAL": ("8-9", 334),
    "WRITE_SINGLE_NORMAL": ("8-10", 335),
    "READ_DRTRY_CANCEL": ("8-12", 336),
    "READ_BURST_TA_WAIT_DRTRY": ("8-13", 337),
    "READ_SINGLE_FASTEST_PIPELINE": ("8-15", 340),
    "READ_SINGLE_DATA_DELAYS": ("8-17", 342),
    "WRITE_SINGLE_DATA_DELAYS": ("8-18", 343),
    "BURST_DATA_DELAYS": ("8-19", 344),
    "DBWO_ENVELOPED_WRITE": ("8-23", 352),
}
by_id = {scenario["id"]: scenario for scenario in scenarios}
for scenario_id, (figure, page) in source_checks.items():
    source = by_id[scenario_id]["source"]
    assert source["figure"] == figure and page in pages(source), scenario_id
assert by_id["READ_DRTRY_CANCEL"]["source"]["section"] == "8.4.4.1"
assert by_id["WRITE_BURST_TEA"]["source"]["sections"] == ["8.4.4.2", "8.5"]
figure_8_13_counts = validate_read_burst_ta_drtry(scenarios_doc)
figure_8_15_counts = validate_fastest_single_reads(scenarios_doc)
figure_8_17_counts = validate_single_read_delays(scenarios_doc)
figure_8_18_counts = validate_single_write_delays(scenarios_doc)
figure_8_19_counts = validate_burst_data_delays(scenarios_doc)

unresolved_ids = {item["id"] for item in scenarios_doc["unresolved_contract_items"]}
assert {"DIAGRAM_ROWS", "ENCODING_TABLES", "COLLISION_MATRIX", "ENDIAN_LANES",
        "PHYSICAL_TIMING", "CLOCK_FIDELITY", "TT_INPUT_WIDTH", "BFM_RTL"} <= unresolved_ids

encoding_counts = bus_decode.validate(encodings_doc)
assert {item["table"] for item in encodings_doc["tables_completed"]} == {"7-1", "7-2", "7-3", "7-5"}

print(
    "bus spec OK: "
    f"{len(signals)} groups / {sum(signal['width'] for signal in signals)} logical bits; "
    f"{len(diagrams)} figures ({status_counts['inventory_only']} inventory-only); "
    f"{len(scenarios)} scenarios / {len(cycle_scenarios)} cycle tables; "
    f"Figure 8-13 {figure_8_13_counts['cycle_rows']} rows; "
    f"Figure 8-15 {figure_8_15_counts['cycle_rows']} rows; "
    f"Figure 8-17 {figure_8_17_counts['cycle_rows']} rows; "
    f"Figure 8-18 {figure_8_18_counts['cycle_rows']} rows; "
    f"Figure 8-19 {figure_8_19_counts['cycle_rows']} rows; "
    f"{encoding_counts['tt_expanded_codes']} TT codes / "
    f"{encoding_counts['listed_size_combinations']} size combinations"
)
