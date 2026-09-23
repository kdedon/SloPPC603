import json
import tempfile
import unittest
from pathlib import Path

from parser import ParseError, build_manifest, parse_rows


class ParserTests(unittest.TestCase):
    def write(self, directory: Path, name: str, text: str) -> Path:
        path = directory / name
        path.write_text(text, encoding="utf-8")
        return path

    def test_ignores_comments_and_blanks(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = self.write(Path(temporary), "i.csv", "# comment\n\nADD,0x1,rD=0x2,rA=0x3,rB=0x4\n")
            rows = parse_rows(path, "integer")
            self.assertEqual(1, len(rows))
            self.assertEqual(("ADD", "0x1", "rD=0x2", "rA=0x3", "rB=0x4"), rows[0].fields)

    def test_preserves_disassembly_commas(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = self.write(Path(temporary), "d.csv", "0x10,0x20,foo,r3,r4\n")
            row = parse_rows(path, "disasm")[0]
            self.assertEqual(("0x10", "0x20", "foo", "r3", "r4"), row.fields)
            self.assertEqual("0x10,0x20,foo,r3,r4", row.raw_line)

    def test_preserves_float_tokens(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = self.write(Path(temporary), "f.csv", "FADD,0x1,frA=snan,frB=qnan,FPSCR=0x0,CR=0x0\n")
            self.assertEqual("frA=snan", parse_rows(path, "float")[0].fields[2])

    def test_rejects_malformed_rows(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = self.write(Path(temporary), "bad.csv", "ADD,0x1,rD=0x2\n")
            with self.assertRaises(ParseError):
                parse_rows(path, "integer")

    def test_rejects_bad_hex_duplicate_and_unknown_rounding(self):
        cases = {
            "bad_opcode.csv": ("ADD,0x100000000,rD=0x2,rA=0x3,rB=0x4\n", "integer"),
            "duplicate.csv": ("ADD,0x1,rD=0x2,rD=0x3,rA=0x4\n", "integer"),
            "bad_round.csv": ("FADD,0x1,round=BAD,frD=0x0,frA=0.0,FPSCR=0x0,CR=0x0\n", "float"),
            "bad_address.csv": ("0x100000000,0x1,addi\n", "disasm"),
        }
        with tempfile.TemporaryDirectory() as temporary:
            for name, (text, kind) in cases.items():
                with self.subTest(name=name):
                    with self.assertRaises(ParseError):
                        parse_rows(self.write(Path(temporary), name, text), kind)

    def test_model_metadata_is_closed_and_consistent(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.write(root, "ppcinttests.csv", "ADD,0x1,rD=0x2,rA=0x3,rB=0x4\n")
            self.write(root, "ppcfloattests.csv", "FADD,0x1,frA=snan,frB=qnan,FPSCR=0x0,CR=0x0\n")
            self.write(root, "ppcdisasmtest.csv", "0x10,0x20,foo\n")
            self.assertEqual("PID6", build_manifest(root, "MPC603E")["reference_model"]["pid"])
            with self.assertRaises(ValueError):
                build_manifest(root, "MPC602")

    def test_manifest_is_summary_only_and_deterministic(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.write(root, "ppcinttests.csv", "ADD,0x1,rD=0x2,rA=0x3,rB=0x4\n")
            self.write(root, "ppcfloattests.csv", "FADD,0x1,frA=snan,frB=qnan,FPSCR=0x0,CR=0x0\n")
            self.write(root, "ppcdisasmtest.csv", "0x10,0x20,foo,r3,r4\n")
            manifest = build_manifest(root)
            self.assertEqual("MPC603EV", manifest["reference_model"]["name"])
            self.assertEqual(1, manifest["vectors"]["integer"]["executable_rows"])
            rendered = json.dumps(manifest, indent=2, sort_keys=True)
            self.assertEqual(rendered, json.dumps(build_manifest(root), indent=2, sort_keys=True))
            self.assertNotIn("raw_line", rendered)
            self.assertNotIn('"fields"', rendered)


if __name__ == "__main__":
    unittest.main()
