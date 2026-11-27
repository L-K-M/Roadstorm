#!/usr/bin/env python3
"""Focused pack-entry path-validation regressions for lib/pack_inventory.py.

Reproduces the Sol finding that a synthetic ``../sentinel`` PCK entry matched
a sibling snapshot file and passed policy. Every entry path must be a
canonical, safe res://-relative spelling BEFORE the dev-only policy runs or a
snapshot path is joined; malformed entries fail closed with a clear reason and
never count as a source match.

Run:  python3 tools/export_smoke/tests/test_pack_inventory.py
Exit: 0 = every assertion passed, 1 = at least one failed.
Original project code under the Unlicense.
"""

import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
LIB_DIR = os.path.join(TESTS_DIR, "..")
PACK_INVENTORY = os.path.join(LIB_DIR, "lib", "pack_inventory.py")

with open(PACK_INVENTORY, "rb") as _fh:
    _module = {"__name__": "pack_inventory_test_subject"}
    exec(compile(_fh.read(), PACK_INVENTORY, "exec"), _module)
inspect_resource_path = _module["inspect_resource_path"]
canonical_resource_path = _module["canonical_resource_path"]
check_pack_contents = _module["check_pack_contents"]
PckError = _module["PckError"]


def build_pck(entries):
    """Build a minimal Godot 4 PCK. entries: list of (raw_path_bytes, payload).

    Path bytes are stored verbatim (including any NULs), so malformed names can
    be exercised through the real parser.
    """
    header_size = 112
    payload = bytearray()
    directory = bytearray()
    offsets = []
    for raw_path, data in entries:
        offsets.append(header_size + len(payload))
        payload += data
    directory += struct.pack("<I", len(entries))
    for (raw_path, data), offset in zip(entries, offsets):
        md5 = hashlib.md5(data).digest()
        directory += struct.pack("<I", len(raw_path)) + raw_path
        directory += struct.pack("<QQ", offset, len(data)) + md5 + struct.pack("<I", 0)
    header = struct.pack(
        "<4sIIIIIIIQ",
        b"GDPC",
        2,        # format version
        4, 7, 2,  # engine version
        0,        # flags
        0,        # file base
        0,        # reserved
        header_size + len(payload),
    )
    header += b"\x00" * (header_size - len(header))
    return bytes(header) + bytes(payload) + bytes(directory)


class PackPathValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        parent = os.environ.get("PACK_INV_TEST_WORK") or os.environ.get("TMPDIR")
        if parent and not os.path.isdir(parent):
            os.makedirs(parent, exist_ok=True)
        cls.work = tempfile.mkdtemp(prefix="pack-inv-tests.", dir=parent or None)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.work, ignore_errors=True)

    def setUp(self):
        self.case_dir = tempfile.mkdtemp(prefix="case.", dir=self.work)
        self.addCleanup(shutil.rmtree, self.case_dir, ignore_errors=True)

    def _write(self, name, data):
        path = os.path.join(self.case_dir, name)
        with open(path, "wb") as fh:
            fh.write(data)
        return path

    def _run_list(self, pck_path):
        return subprocess.run(
            [sys.executable, PACK_INVENTORY, "list", "--pck", pck_path],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )

    # -- positive: legitimate pinned-style entries are accepted --------------

    LEGIT = (
        "project.binary",
        "scenes/boot.tscn.remap",
        "scenes/game.tscn.remap",
        "scenes/main_menu.tscn.remap",
        "src/boot/boot.gdc",
        "src/boot/game.gdc",
        "src/boot/main_menu.gdc",
        ".godot/global_script_class_cache.cfg",
        ".godot/uid_cache.bin",
        ".godot/exported/main.scn",
        "assets/art/car.png",
    )

    def test_legitimate_entries_parse_and_pass_path_validation(self):
        entries = [(name.encode("utf-8"), ("payload:" + name).encode("utf-8"))
                   for name in self.LEGIT]
        pck_path = self._write("legit.pck", build_pck(entries))
        result = self._run_list(pck_path)
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in self.LEGIT:
            self.assertIn("entry=%s " % name, result.stdout)
        pck = _module["parse_pck"](open(pck_path, "rb").read())
        policy = check_pack_contents(pck, None)
        self.assertEqual(policy["invalid_paths"], [])
        self.assertEqual(policy["source_match"]["compared"], 0)

    # -- negative: each unsafe spelling is rejected with a diagnostic --------

    BAD_PATHS = {
        "../sentinel": "dot component",
        "a/../../b": "dot component",
        "/etc/passwd": "absolute or scheme-qualified",
        "res://scenes/x.tscn": "absolute or scheme-qualified",
        "C:/windows/x": "drive-qualified",
        "a\\b.tscn": "backslash",
        "./scenes/x.tscn": "dot component",
        "scenes//x.tscn": "empty component",
        "scenes/x.tscn/": "empty component",
        "scenes/\x01x.tscn": "control characters",
        "assets/a.png:stream": "colon",
        "assets/foo.": "trailing dot or space",
        "assets/foo ": "trailing dot or space",
        "CON": "reserved device name",
        "con.png": "reserved device name",
        "LPT9.tar": "reserved device name",
    }

    def test_each_unsafe_spelling_fails_closed(self):
        for bad, needle in self.BAD_PATHS.items():
            with self.subTest(path=bad):
                raw = bad.encode("utf-8")
                pck_path = self._write("bad.pck", build_pck([(raw, b"data")]))
                result = self._run_list(pck_path)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("pack-inventory FAIL:", result.stderr)
                self.assertIn(needle, result.stderr)

    def test_check_command_fails_on_parent_entry(self):
        """The end-to-end `check` command, not just `list`, must fail closed."""
        payload = b"sibling sentinel bytes"
        sibling_dir = os.path.join(self.case_dir, "snap-parent")
        snap = os.path.join(sibling_dir, "snapshot")
        os.makedirs(snap)
        with open(os.path.join(sibling_dir, "sentinel"), "wb") as fh:
            fh.write(payload)
        main = os.path.join(self.case_dir, "dummy-main")
        with open(main, "wb") as fh:
            fh.write(b"not a real binary\n")
        bad_pck = self._write(
            "check-bad.pck",
            build_pck([(b"../sentinel", payload)]),
        )
        result = subprocess.run(
            [sys.executable, PACK_INVENTORY, "check", "--platform", "Linux",
             "--main", main, "--pck", bad_pck, "--snapshot", snap],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("pack-inventory FAIL:", result.stderr)
        self.assertIn("dot component", result.stderr)

    def test_nul_and_non_utf8_paths_fail_closed(self):
        cases = {
            b"good\x00bad": "embedded NUL",
            b"\xff\xfe": "not valid UTF-8",
        }
        for raw, needle in cases.items():
            with self.subTest(raw=raw):
                pck_path = self._write("bad-raw.pck", build_pck([(raw, b"data")]))
                result = self._run_list(pck_path)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(needle, result.stderr)

    def test_empty_and_dot_paths_are_rejected_by_validator(self):
        for raw, needle in ((b"", "empty"), (b".", "dot component"),
                            (b"..", "dot component"),
                            (b"...", "trailing dot or space")):
            path, problem = inspect_resource_path(raw, 3)
            self.assertIsNone(path)
            self.assertIn(needle, problem)

    # -- the original escape repro: policy/source match must not happen -------

    def test_parent_entry_cannot_match_sibling_or_feed_policy(self):
        sibling_dir = os.path.join(self.work, "snap-parent")
        snap = os.path.join(sibling_dir, "snapshot")
        os.makedirs(snap)
        payload = b"sibling sentinel bytes"
        with open(os.path.join(sibling_dir, "sentinel"), "wb") as fh:
            fh.write(payload)
        self.addCleanup(shutil.rmtree, sibling_dir, ignore_errors=True)

        pck = {"entries": [{
            "path": "../sentinel",
            "offset": 0,
            "size": len(payload),
            "md5": hashlib.md5(payload).hexdigest(),
        }]}
        policy = check_pack_contents(pck, snap)
        self.assertIn("invalid_paths", policy)  # required by verdict_for
        self.assertEqual(len(policy["invalid_paths"]), 1)
        self.assertIn("../sentinel", policy["invalid_paths"][0]["path"])
        self.assertEqual(policy["source_match"]["compared"], 0)
        self.assertEqual(policy["source_match"]["matched"], 0)
        self.assertEqual(policy["dev_only"], [])
        verdict = _module["verdict_for"](0, 1, [], policy)
        self.assertTrue(any("unsafe/non-canonical" in p for p in verdict), verdict)

    def test_godot_prefixed_entries_remain_valid(self):
        for name in (".godot/global_script_class_cache.cfg",
                     ".godot/uid_cache.bin",
                     ".godot/exported/main.scn"):
            path, problem = inspect_resource_path(name, 0)
            self.assertIsNone(problem, (name, problem))
            self.assertEqual(path, name)

    def test_malformed_entry_does_not_satisfy_required_runtime(self):
        pck = {"entries": [{"path": "../project.binary", "offset": 0,
                            "size": 1, "md5": "0" * 32}]}
        policy = check_pack_contents(pck, None)
        self.assertIn("project.binary", policy["required_missing"])
        self.assertEqual(policy["invalid_paths"][0]["path"], "../project.binary")


class InventoryOutputReservationTests(unittest.TestCase):
    """--report/--json are create-only; --sums keeps its append contract."""

    @classmethod
    def setUpClass(cls):
        parent = os.environ.get("PACK_INV_TEST_WORK") or os.environ.get("TMPDIR")
        if parent and not os.path.isdir(parent):
            os.makedirs(parent, exist_ok=True)
        cls.work = tempfile.mkdtemp(prefix="pack-inv-out.", dir=parent or None)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.work, ignore_errors=True)

    def setUp(self):
        self.case_dir = tempfile.mkdtemp(prefix="case.", dir=self.work)
        self.addCleanup(shutil.rmtree, self.case_dir, ignore_errors=True)
        self.main = os.path.join(self.case_dir, "main.bin")
        with open(self.main, "wb") as fh:
            fh.write(b"dummy main\n")
        self.pck = os.path.join(self.case_dir, "good.pck")
        entries = [(n.encode("utf-8"), ("payload:" + n).encode("utf-8"))
                   for n in PackPathValidationTests.LEGIT]
        with open(self.pck, "wb") as fh:
            fh.write(build_pck(entries))

    def _run(self, report=None, json_out=None, sums=None):
        cmd = [sys.executable, PACK_INVENTORY, "check", "--platform", "Linux",
               "--main", self.main, "--pck", self.pck]
        if report is not None:
            cmd += ["--report", report]
        if json_out is not None:
            cmd += ["--json", json_out]
        if sums is not None:
            cmd += ["--sums", sums]
        return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True)

    def test_existing_report_fails_without_changing_bytes(self):
        report = os.path.join(self.case_dir, "report.txt")
        with open(report, "wb") as fh:
            fh.write(b"existing-report-bytes\n")
        json_out = os.path.join(self.case_dir, "out.json")
        result = self._run(report=report, json_out=json_out)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("cannot create output exclusively", result.stderr)
        with open(report, "rb") as fh:
            self.assertEqual(fh.read(), b"existing-report-bytes\n")
        self.assertFalse(os.path.exists(json_out), "second output must not appear after refusal")

    def test_existing_json_fails_without_changing_bytes(self):
        report = os.path.join(self.case_dir, "report.txt")
        json_out = os.path.join(self.case_dir, "out.json")
        with open(json_out, "wb") as fh:
            fh.write(b'{"existing":"json"}\n')
        result = self._run(report=report, json_out=json_out)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("cannot create output exclusively", result.stderr)
        with open(json_out, "rb") as fh:
            self.assertEqual(fh.read(), b'{"existing":"json"}\n')

    def test_symlink_report_is_never_followed(self):
        target = os.path.join(self.case_dir, "target.txt")
        with open(target, "wb") as fh:
            fh.write(b"target-bytes\n")
        link = os.path.join(self.case_dir, "report-link.txt")
        os.symlink(target, link)
        result = self._run(report=link)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertTrue(os.path.islink(link), "symlink itself must remain")
        with open(target, "rb") as fh:
            self.assertEqual(fh.read(), b"target-bytes\n")

    def test_dangling_symlink_report_is_refused(self):
        link = os.path.join(self.case_dir, "dangling.txt")
        os.symlink(os.path.join(self.case_dir, "nowhere"), link)
        result = self._run(report=link)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertTrue(os.path.islink(link))
        self.assertFalse(os.path.exists(os.path.join(self.case_dir, "nowhere")))

    def test_directory_report_is_refused(self):
        dirpath = os.path.join(self.case_dir, "report-dir")
        os.makedirs(dirpath)
        result = self._run(report=dirpath)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertTrue(os.path.isdir(dirpath))

    def test_same_name_collision_reserves_nothing_written(self):
        both = os.path.join(self.case_dir, "same-output.txt")
        result = self._run(report=both, json_out=both)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("cannot create output exclusively", result.stderr)
        # The first reservation is left empty; no verdict/report content leaks.
        self.assertTrue(os.path.exists(both))
        self.assertEqual(os.path.getsize(both), 0)

    def test_fresh_outputs_are_created_and_sums_still_appends(self):
        report = os.path.join(self.case_dir, "report.txt")
        json_out = os.path.join(self.case_dir, "out.json")
        sums = os.path.join(self.case_dir, "SHA256SUMS.txt")
        with open(sums, "wb") as fh:
            fh.write(b"pre-existing-line\n")
        result = self._run(report=report, json_out=json_out, sums=sums)
        self.assertNotEqual(result.returncode, 2, result.stderr)
        with open(report, encoding="utf-8") as fh:
            self.assertIn("# Roadstorm Racer! package inventory", fh.read())
        with open(json_out, encoding="utf-8") as fh:
            payload = json.load(fh)
        self.assertIn(payload["verdict"], ("PASS", "FAIL"))
        with open(sums, encoding="utf-8") as fh:
            sums_text = fh.read()
        self.assertTrue(sums_text.startswith("pre-existing-line\n"), "append contract")
        self.assertIn("\n", sums_text[len("pre-existing-line\n"):])


if __name__ == "__main__":
    unittest.main(verbosity=2)
