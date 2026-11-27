#!/usr/bin/env python3
# Roadstorm Racer! - export package inventory, component checksums and
# pack-content policy checks.
# Ownership: tools/export_smoke/** (PLAN.md "How agents execute the plan").
#
# WHY THIS EXISTS
#   Review findings E3 and E4 (review/implementation/
#   m0-checkpoint-opus-recheck-4803d848-c82b-4902-97d7-feee789a5b7b.md):
#     E3 - the export result hashed only the main file. The Windows and Linux
#          presets write a separate sidecar .pck (embed_pck is false), and for
#          Linux the main binary is the untouched pinned stock template, so its
#          digest identifies no game content at all.
#     E4 - with export_filter="all_resources" and an empty exclude filter, the
#          packages contained development-only tooling: tools/**, fixtures/**,
#          schemas/** and assets/manifest.json.
#   This tool closes both: it enumerates EVERY produced package component and
#   checksums it (including the .pck, embedded or sidecar), and it reads the
#   actual res:// tree inside the .pck to prove that no development-only path
#   was packaged and that every required runtime resource still is.
#
# WHAT IT VERIFIES
#   * every component of the produced package (the distributed archive/executable
#     and, for macOS, every file inside the .app bundle) is present, non-empty
#     and recorded with its size and SHA-256;
#   * the .pck directory parses, the file table is self-consistent, and every
#     entry's stored MD-5 matches the bytes stored for it in the pack;
#   * no development-only path (tools/, fixtures/, schemas/, docs/, plan/,
#     review/, work/, .github/, tests/, *.py, *.sh, assets/manifest.json) is
#     inside the package;
#   * the required runtime resources are still inside the package, so the
#     exclude filter did not drop a runtime dependency;
#   * optionally (--snapshot) that every entry whose path also exists in the
#     frozen candidate is byte-identical to it.
#
# WHAT IT DOES NOT VERIFY
#   * that the package launches on its target OS. Windows and Linux are
#     cross-exports with no host here; only the macOS package is launched, by
#     tools/export_smoke/launch_macos_app.sh, and only headless (or with a
#     bounded windowed probe when that is asked for);
#   * the code signature, notarization or Developer ID identity: the macOS
#     package is ad-hoc signed and UNNOTARIZED (no credentials exist);
#   * gameplay, final M0 content, or release notices (Unlicense, CC0, engine and
#     dependency notices are M9 packaging work - Godot only packs recognised
#     resource types, so licenses/ and provenance/ are not in the pack today);
#   * that the excluded development tooling still works, or that the game's
#     logic is correct. It checks package CONTENT, not behaviour.
#
# Usage:
#   pack_inventory.py list --pck <file.pck> [--format text|json]
#   pack_inventory.py check --platform macOS|Windows|Linux --main <file>
#                         [--pck <file.pck>] [--snapshot <dir>]
#                         [--report <file>] [--sums <file>] [--json <file>]
#                         [--format text|json]
#
# Exit codes: 0 = every check passed, 1 = a check failed,
#             2 = the tool could not run.
# Original project code under the Unlicense.

import argparse
import fnmatch
import hashlib
import json
import os
import struct
import sys
import tempfile
import zipfile

PCK_MAGIC = b"GDPC"
# Godot 4.7 PCK header: magic, format version, engine major/minor/patch,
# pack flags, file_base, one reserved u32, then the directory offset as u64.
# The file table is at the END of the pack and starts with a u32 file count.
HEADER_FIXED = 112

# Development-only content that must never reach a runtime package (E4).
DEV_ONLY_PATTERNS = (
    "tools/*",
    "fixtures/*",
    "schemas/*",
    "docs/*",
    "plan/*",
    "review/*",
    "work/*",
    ".github/*",
    "tests/*",
    "*.py",
    "*.sh",
    # Asset registry maintained by tools/asset_manifest; the game never reads it.
    "assets/manifest.json",
)

# Runtime resources the M0 shell needs. This is a FLOOR, not a full list:
# update it when the project's runtime resources change, otherwise the check
# fails loudly instead of silently shipping a package that cannot boot.
REQUIRED_RUNTIME = (
    "project.binary",
    "scenes/boot.tscn.remap",
    "scenes/game.tscn.remap",
    "scenes/main_menu.tscn.remap",
    "src/boot/boot.gdc",
    "src/boot/game.gdc",
    "src/boot/main_menu.gdc",
    ".godot/global_script_class_cache.cfg",
    ".godot/uid_cache.bin",
)
REQUIRED_RUNTIME_PREFIXES = (
    ".godot/exported/",
)

# Pack entries the engine derives at export time. They have no source file at
# the same path in the frozen candidate, or they are regenerated caches whose
# content legitimately changes when the exclude filter removes tooling, so they
# are not compared byte-for-byte against the candidate.
ENGINE_GENERATED_EXACT = (
    "project.binary",
    ".godot/global_script_class_cache.cfg",
    ".godot/uid_cache.bin",
)


def is_engine_generated(path):
    if path in ENGINE_GENERATED_EXACT:
        return True
    return path.endswith(".remap") or path.endswith(".gdc")

NOT_VERIFIED = (
    "launch on the target OS (Windows and Linux are cross-exports with no host here;",
    "  only the macOS package is launched, by tools/export_smoke/launch_macos_app.sh)",
    "the code signature chain, notarization or Developer ID identity (the macOS",
    "  package is ad-hoc signed and UNNOTARIZED - no credentials exist)",
    "gameplay, final M0 content, or release notices (Unlicense, CC0, engine and",
    "  dependency notices are M9 work; Godot packs only recognised resource types,",
    "  so licenses/ and provenance/ are not inside the pack today)",
    "that the excluded development tooling still works, or that the game logic is",
    "  correct: this checks package CONTENT, not behaviour",
)


def die(code, message):
    sys.stderr.write("pack-inventory FAIL: %s\n" % message)
    sys.exit(code)


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


# --------------------------------------------------------------------------
# PCK parsing
# --------------------------------------------------------------------------

class PckError(Exception):
    pass


def parse_pck(data):
    """Parse a Godot 4.7 PCK. Returns a dict describing header and entries.

    Entry layout (verified against a Godot 4.7.2 export):
        u32 path_length, path bytes (NUL padded), u64 offset, u64 size,
        16-byte MD-5, u32 tail (0).
    The directory is preceded by a u32 file count and is located by the u64
    directory offset in the header; offsets are relative to file_base when the
    PACK_REL_FILEBASE flag (2) is set.
    """
    if len(data) < HEADER_FIXED:
        raise PckError("file is only %d bytes; too small for a PCK header" % len(data))
    if data[0:4] != PCK_MAGIC:
        raise PckError("bad magic %r; not a Godot PCK" % data[0:4])
    (fmt_version,) = struct.unpack_from("<I", data, 4)
    major, minor, patch = struct.unpack_from("<III", data, 8)
    (flags,) = struct.unpack_from("<I", data, 20)
    (file_base,) = struct.unpack_from("<I", data, 24)
    (dir_offset,) = struct.unpack_from("<Q", data, 32)
    if dir_offset + 4 > len(data):
        raise PckError("directory offset %d is past the end of the file" % dir_offset)
    (count,) = struct.unpack_from("<I", data, dir_offset)

    entries = []
    pos = dir_offset + 4
    for index in range(count):
        if pos + 4 > len(data):
            raise PckError("truncated file table at entry %d" % index)
        (path_len,) = struct.unpack_from("<I", data, pos)
        if path_len == 0 or path_len > 4096:
            raise PckError("implausible path length %d at entry %d" % (path_len, index))
        raw_path = data[pos + 4:pos + 4 + path_len]
        path = raw_path.rstrip(b"\x00").decode("utf-8", "replace")
        q = pos + 4 + path_len
        if q + 36 > len(data):
            raise PckError("truncated entry %d (%s)" % (index, path))
        offset, size = struct.unpack_from("<QQ", data, q)
        md5 = data[q + 16:q + 32]
        (tail,) = struct.unpack_from("<I", data, q + 32)
        entries.append({
            "path": path,
            "offset": offset,
            "size": size,
            "md5": md5.hex(),
            "tail": tail,
        })
        pos = q + 36
    if pos != len(data):
        raise PckError("file table ends at %d but the file is %d bytes" % (pos, len(data)))
    return {
        "format_version": fmt_version,
        "engine": "%d.%d.%d" % (major, minor, patch),
        "flags": flags,
        "file_base": file_base,
        "dir_offset": dir_offset,
        "count": count,
        "entries": entries,
    }


def verify_pck(data, pck):
    """Verify every entry's MD-5 against the bytes stored for it.

    Returns (base_used, verified_count, failures). The base is chosen by
    trying the header's file_base and 0 and keeping whichever verifies more
    entries, so a future format tweak is reported instead of silently passing.
    """
    best = None
    for base in (pck["file_base"], 0):
        ok = 0
        failures = []
        for entry in pck["entries"]:
            start = entry["offset"] + base
            end = start + entry["size"]
            if start < 0 or end > len(data):
                failures.append((entry["path"], "stored bytes out of range"))
                continue
            if hashlib.md5(data[start:end]).hexdigest() == entry["md5"]:
                ok += 1
            else:
                failures.append((entry["path"], "MD-5 mismatch"))
        if best is None or ok > best[1]:
            best = (base, ok, failures)
        if ok == len(pck["entries"]):
            break
    base, ok, failures = best
    return base, ok, failures


def find_embedded_pck(data):
    """Return the offset of a trailing/embedded PCK in a binary, or None.

    Only used when no sidecar .pck exists (embed_pck style exports). Every
    "GDPC" occurrence is tried from the end; a candidate is accepted only when
    its file table walks to exactly the end of the file.
    """
    start = data.rfind(PCK_MAGIC)
    while start != -1:
        try:
            blob = data[start:]
            pck = parse_pck(blob)
            return start, pck
        except PckError:
            start = data.rfind(PCK_MAGIC, 0, start)
    return None, None


# --------------------------------------------------------------------------
# Package component enumeration
# --------------------------------------------------------------------------

def macos_components(zip_path, workdir):
    """Unpack a macOS export .zip and return (components, pck_bytes, app_name).

    components: list of dicts {name, path, bytes} for every file in the bundle.
    """
    try:
        archive = zipfile.ZipFile(zip_path)
    except zipfile.BadZipFile as exc:
        raise PckError("cannot read %s as a zip: %s" % (zip_path, exc))
    names = archive.namelist()
    apps = sorted({n.split("/")[0] for n in names if n.endswith(".app/") or ".app/" in n})
    if not apps:
        raise PckError("no .app bundle inside %s" % zip_path)
    app_name = apps[0]
    root = os.path.join(workdir, "extracted")
    archive.extractall(root)
    app_dir = os.path.join(root, app_name)
    if not os.path.isdir(app_dir):
        raise PckError(".app bundle %s not found after extraction" % app_name)
    components = []
    pck_bytes = None
    for dirpath, dirnames, filenames in os.walk(app_dir):
        dirnames.sort()
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root)
            with open(full, "rb") as fh:
                blob = fh.read()
            components.append({"name": rel, "bytes": len(blob), "sha256": sha256_bytes(blob)})
            if name.endswith(".pck") and pck_bytes is None:
                pck_bytes = blob
    components.sort(key=lambda c: c["name"])
    return components, pck_bytes, app_name


def template_identity(main_path, platform):
    """Best-effort: report whether the main binary is the pinned stock template.

    The Linux export copies the stock template verbatim, so its digest says
    nothing about the game content; the Windows export rewrites the
    executable. Knowing which is which keeps the report honest.
    """
    candidates = []
    ver = None
    for base in (os.path.join(os.path.expanduser("~"), "Library", "Application Support", "Godot", "export_templates"),
                 os.path.join(os.path.expanduser("~"), ".local", "share", "godot", "export_templates")):
        if os.path.isdir(base):
            versions = sorted(os.listdir(base))
            if versions:
                ver = versions[-1]
                candidates.append(os.path.join(base, ver))
    names = {
        "Linux": "linux_release.x86_64",
        "Windows": "windows_release_x86_64.exe",
    }
    if platform not in names or not candidates:
        return {"checked": False, "note": "no export template directory found; template identity not checked"}
    for directory in candidates:
        template = os.path.join(directory, names[platform])
        if os.path.isfile(template):
            same = sha256_file(template) == sha256_file(main_path)
            return {
                "checked": True,
                "template": template,
                "identical": same,
                "note": ("main binary is byte-identical to the pinned stock template; "
                         "its digest identifies no game content"
                         if same else
                         "main binary differs from the pinned stock template (engine export patched it)"),
            }
    return {"checked": False, "note": "template %s not found; template identity not checked" % names[platform]}


# --------------------------------------------------------------------------
# Checks
# --------------------------------------------------------------------------

def is_dev_only(path):
    for pattern in DEV_ONLY_PATTERNS:
        if fnmatch.fnmatch(path, pattern):
            return pattern
    return None


def check_pack_contents(pck, snapshot):
    """Apply the E4 policy to the parsed pack. Returns a result dict."""
    dev_only = []
    paths = [entry["path"] for entry in pck["entries"]]
    required_missing = [r for r in REQUIRED_RUNTIME if r not in paths]
    for prefix in REQUIRED_RUNTIME_PREFIXES:
        if not any(p.startswith(prefix) for p in paths):
            required_missing.append(prefix + "*")
    for entry in pck["entries"]:
        pattern = is_dev_only(entry["path"])
        if pattern:
            dev_only.append({"path": entry["path"], "matched": pattern})

    source = {"compared": 0, "matched": 0, "engine_generated": 0, "absent": [], "mismatched": []}
    if snapshot:
        for entry in pck["entries"]:
            path = entry["path"]
            if is_engine_generated(path):
                source["engine_generated"] += 1
                continue
            candidate = os.path.join(snapshot, path)
            if not os.path.isfile(candidate):
                source["absent"].append(path)
                continue
            source["compared"] += 1
            with open(candidate, "rb") as fh:
                digest = hashlib.md5(fh.read()).hexdigest()
            if digest == entry["md5"]:
                source["matched"] += 1
            else:
                source["mismatched"].append(path)
    return {
        "dev_only": dev_only,
        "required_missing": required_missing,
        "source_match": source,
    }


def _shorten(items, limit=8):
    """Render a path list for a one-line problem message, truncated."""
    if len(items) <= limit:
        return ", ".join(items)
    return "%s, ... (%d total; see the report)" % (", ".join(items[:limit]), len(items))


def verdict_for(base_used, verified, failures, policy):
    problems = []
    if failures:
        problems.append("%d pack entr%s failed MD-5 verification: %s" % (
            len(failures), "y" if len(failures) == 1 else "ies", _shorten([f[0] for f in failures])))
    if policy["dev_only"]:
        problems.append("%d development-only path(s) are inside the package: %s" % (
            len(policy["dev_only"]), _shorten([d["path"] for d in policy["dev_only"]])))
    if policy["required_missing"]:
        problems.append("required runtime resource(s) missing: %s" % _shorten(policy["required_missing"]))
    if policy["source_match"]["mismatched"]:
        problems.append("%d entr%s differ from the frozen candidate: %s" % (
            len(policy["source_match"]["mismatched"]),
            "y" if len(policy["source_match"]["mismatched"]) == 1 else "ies",
            _shorten(policy["source_match"]["mismatched"])))
    if policy["source_match"]["absent"]:
        problems.append("%d pack entr%s are not in the frozen candidate: %s" % (
            len(policy["source_match"]["absent"]),
            "y is" if len(policy["source_match"]["absent"]) == 1 else "ies are",
            _shorten(policy["source_match"]["absent"])))
    return problems


# --------------------------------------------------------------------------
# Reporting
# --------------------------------------------------------------------------

def write_report(path, lines):
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")


def build_lines(platform, main_path, components, pck_info, policy, problems, base_used, template):
    lines = []
    add = lines.append
    add("# Roadstorm Racer! package inventory and component checksums")
    add("# tool: tools/export_smoke/lib/pack_inventory.py (E3: checksum every")
    add("#       component including the .pck; E4: no development-only content)")
    add("platform=%s" % platform)
    add("main=%s" % os.path.basename(main_path))
    add("")
    add("## Components (every produced package component)")
    for comp in components:
        add("component=%s bytes=%d sha256=%s" % (comp["name"], comp["bytes"], comp["sha256"]))
    add("component_count=%d" % len(components))
    add("empty_components=%d" % sum(1 for c in components if c["bytes"] == 0))
    add("")
    if template.get("checked"):
        add("## Main binary vs pinned export template")
        add("template=%s" % template["template"])
        add("identical_to_template=%s" % ("yes" if template["identical"] else "no"))
        add("template_note=%s" % template["note"])
        add("")
    if pck_info is None:
        add("## Pack contents")
        add("pck=NONE FOUND (this package carries no resource pack)")
        add("")
    else:
        pck = pck_info["pck"]
        entries = pck_info["entries"]
        add("## Pack contents (the res:// tree inside the .pck)")
        add("pck=%s" % pck_info["name"])
        add("pck_bytes=%d" % pck_info["bytes"])
        add("pck_sha256=%s" % pck_info["sha256"])
        add("pck_format_version=%d" % pck["format_version"])
        add("pck_engine=%s" % pck["engine"])
        add("pck_flags=%d" % pck["flags"])
        add("pck_file_base=%d" % pck["file_base"])
        add("pck_offset_base_used=%d" % base_used)
        add("pck_entries=%d" % pck["count"])
        add("pck_md5_verified=%d" % pck_info["verified"])
        add("pck_md5_failed=%d" % len(pck_info["failures"]))
        for path, reason in pck_info["failures"]:
            add("pck_md5_failure=%s (%s)" % (path, reason))
        add("")
        for entry in pck["entries"]:
            add("entry=%s bytes=%d md5=%s" % (entry["path"], entry["size"], entry["md5"]))
        add("")
        add("## Policy checks (E4)")
        add("dev_only_present=%d" % len(policy["dev_only"]))
        for item in policy["dev_only"]:
            add("dev_only_path=%s (matched %s)" % (item["path"], item["matched"]))
        add("required_runtime_missing=%d" % len(policy["required_missing"]))
        for item in policy["required_missing"]:
            add("required_runtime_missing_path=%s" % item)
        match = policy["source_match"]
        if match["compared"] or match["engine_generated"] or match["absent"]:
            add("frozen_candidate_entries_compared=%d" % match["compared"])
            add("frozen_candidate_entries_identical=%d" % match["matched"])
            add("frozen_candidate_entries_engine_generated=%d (derived at export: .remap/.gdc/project.binary/.godot caches)"
                % match["engine_generated"])
            add("frozen_candidate_entries_not_in_candidate=%d" % len(match["absent"]))
            for path in match["absent"]:
                add("frozen_candidate_missing_path=%s" % path)
            add("frozen_candidate_entries_different=%d" % len(match["mismatched"]))
            for path in match["mismatched"]:
                add("frozen_candidate_different_path=%s" % path)
        add("")
    add("## What this verifies")
    add("every produced package component is present, non-empty and checksummed")
    add("(SHA-256, size), including the .pck - embedded or sidecar")
    add("the .pck file table parses, is self-consistent and every entry's MD-5")
    add("matches the bytes stored for it in the pack")
    add("no development-only path (tools/, fixtures/, schemas/, docs/, plan/,")
    add("review/, work/, .github/, tests/, *.py, *.sh, assets/manifest.json)")
    add("is inside the package")
    add("the required runtime resources are still inside the package, so the")
    add("exclude filter did not drop a runtime dependency")
    add("")
    add("## What this does NOT verify")
    for line in NOT_VERIFIED:
        add(line)
    add("")
    add("## Verdict")
    add("verdict=%s" % ("FAIL" if problems else "PASS"))
    for problem in problems:
        add("problem=%s" % problem)
    return lines


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------

def cmd_list(args):
    with open(args.pck, "rb") as fh:
        data = fh.read()
    try:
        pck = parse_pck(data)
    except PckError as exc:
        die(1, "%s: %s" % (args.pck, exc))
    base, verified, failures = verify_pck(data, pck)
    payload = {
        "file": args.pck,
        "bytes": len(data),
        "sha256": sha256_bytes(data),
        "format_version": pck["format_version"],
        "engine": pck["engine"],
        "flags": pck["flags"],
        "file_base": pck["file_base"],
        "offset_base_used": base,
        "entries": pck["count"],
        "md5_verified": verified,
        "md5_failed": len(failures),
        "paths": [e["path"] for e in pck["entries"]],
    }
    if args.format == "json":
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        print("file=%s bytes=%d sha256=%s" % (args.pck, len(data), payload["sha256"]))
        print("format_version=%d engine=%s flags=%d file_base=%d entries=%d"
              % (pck["format_version"], pck["engine"], pck["flags"], pck["file_base"], pck["count"]))
        print("md5_verified=%d md5_failed=%d (offset base %d)" % (verified, len(failures), base))
        for entry in pck["entries"]:
            print("entry=%s bytes=%d md5=%s" % (entry["path"], entry["size"], entry["md5"]))
    return 0 if not failures else 1


def cmd_check(args):
    if not os.path.isfile(args.main):
        die(2, "package not found: %s" % args.main)
    platform = args.platform
    if platform not in ("macOS", "Windows", "Linux"):
        die(2, "unknown platform %r (expected macOS, Windows or Linux)" % platform)

    components = []
    pck_bytes = None
    pck_name = None
    app_name = None
    workdir = None
    try:
        if platform == "macOS":
            workdir = tempfile.mkdtemp(prefix="rs-packinv.")
            components, pck_bytes, app_name = macos_components(args.main, workdir)
            embedded = [c["name"] for c in components if c["name"].endswith(".pck")]
            pck_name = ("%s (embedded in the .app bundle)" % embedded[0]) if embedded else "<none>"
            # The distributed archive itself is a component too.
            components.insert(0, {
                "name": os.path.basename(args.main),
                "bytes": os.path.getsize(args.main),
                "sha256": sha256_file(args.main),
            })
        else:
            main_bytes = os.path.getsize(args.main)
            components.append({
                "name": os.path.basename(args.main),
                "bytes": main_bytes,
                "sha256": sha256_file(args.main),
            })
            sidecar = args.pck
            if sidecar is None:
                guess = os.path.splitext(args.main)[0] + ".pck"
                if os.path.isfile(guess):
                    sidecar = guess
            if sidecar and os.path.isfile(sidecar):
                with open(sidecar, "rb") as fh:
                    pck_bytes = fh.read()
                pck_name = os.path.basename(sidecar)
                components.append({
                    "name": pck_name,
                    "bytes": len(pck_bytes),
                    "sha256": sha256_bytes(pck_bytes),
                })
            else:
                # embed_pck style: the pack is appended to the executable.
                with open(args.main, "rb") as fh:
                    data = fh.read()
                offset, _pck = find_embedded_pck(data)
                if offset is not None:
                    pck_bytes = data[offset:]
                    pck_name = "%s+%d (embedded pack appended to the executable)" % (
                        os.path.basename(args.main), offset)
    finally:
        if workdir and os.path.isdir(workdir):
            import shutil
            shutil.rmtree(workdir, ignore_errors=True)

    empty = [c["name"] for c in components if c["bytes"] == 0]
    if empty:
        die(1, "empty package component(s): %s" % ", ".join(empty))

    pck_info = None
    problems = []
    base_used = 0
    if pck_bytes is None:
        problems.append("no .pck found in the %s package" % platform)
    else:
        try:
            pck = parse_pck(pck_bytes)
        except PckError as exc:
            die(1, "cannot parse the .pck: %s" % exc)
        base_used, verified, failures = verify_pck(pck_bytes, pck)
        pck_info = {
            "pck": pck,
            "entries": [e["path"] for e in pck["entries"]],
            "name": pck_name,
            "bytes": len(pck_bytes),
            "sha256": sha256_bytes(pck_bytes),
            "verified": verified,
            "failures": failures,
        }
        policy = check_pack_contents(pck, args.snapshot)
        problems.extend(verdict_for(base_used, verified, failures, policy))
    if pck_info is None:
        policy = {"dev_only": [], "required_missing": [],
                  "source_match": {"compared": 0, "matched": 0, "engine_generated": 0,
                                   "absent": [], "mismatched": []}}

    template = {"checked": False, "note": "not applicable to this platform"}
    if platform in ("Linux", "Windows"):
        template = template_identity(args.main, platform)

    lines = build_lines(platform, args.main, components, pck_info, policy, problems, base_used, template)

    if args.report:
        write_report(args.report, lines)
    if args.sums:
        with open(args.sums, "a") as fh:
            for comp in components:
                fh.write("%s  %s\n" % (comp["sha256"], comp["name"]))
    if args.json:
        with open(args.json, "w") as fh:
            json.dump({
                "platform": platform,
                "main": os.path.basename(args.main),
                "app": app_name,
                "components": components,
                "pck": None if pck_info is None else {
                    "name": pck_info["name"],
                    "bytes": pck_info["bytes"],
                    "sha256": pck_info["sha256"],
                    "entries": pck_info["pck"]["count"],
                    "md5_verified": pck_info["verified"],
                    "md5_failed": len(pck_info["failures"]),
                    "paths": pck_info["entries"],
                },
                "policy": {
                    "dev_only": policy["dev_only"],
                    "required_missing": policy["required_missing"],
                    "source_match": policy["source_match"],
                },
                "template": template,
                "problems": problems,
                "verdict": "FAIL" if problems else "PASS",
            }, fh, indent=2, sort_keys=True)

    if args.format == "json":
        print(json.dumps({"verdict": "FAIL" if problems else "PASS", "problems": problems}, indent=2))
    elif args.quiet:
        # One-line summary for the shell runner; the full report is in --report.
        if problems:
            print("package_inventory=FAIL problems=%d report=%s" % (len(problems), args.report or "-"))
            for problem in problems:
                sys.stderr.write("pack-inventory FAIL: %s\n" % problem)
        else:
            print("package_inventory=PASS components=%d pack_entries=%d md5_verified=%d report=%s" % (
                len(components),
                0 if pck_info is None else pck_info["pck"]["count"],
                0 if pck_info is None else pck_info["verified"],
                args.report or "-"))
    else:
        for line in lines:
            print(line)
        if problems:
            for problem in problems:
                sys.stderr.write("pack-inventory FAIL: %s\n" % problem)
            return 1
        print("pack-inventory: PASS (%d components, %d pack entries, %d MD-5 verified)"
              % (len(components), 0 if pck_info is None else pck_info["pck"]["count"],
                 0 if pck_info is None else pck_info["verified"]))
    return 1 if problems else 0


def main(argv):
    parser = argparse.ArgumentParser(description="Roadstorm export package inventory and checksums")
    sub = parser.add_subparsers(dest="command")

    p_list = sub.add_parser("list", help="list and verify the contents of a .pck")
    p_list.add_argument("--pck", required=True)
    p_list.add_argument("--format", choices=("text", "json"), default="text")
    p_list.set_defaults(func=cmd_list)

    p_check = sub.add_parser("check", help="checksum and policy-check a produced package")
    p_check.add_argument("--platform", required=True, choices=("macOS", "Windows", "Linux"))
    p_check.add_argument("--main", required=True, help="the produced package (zip/exe/binary)")
    p_check.add_argument("--pck", help="sidecar .pck (default: <main-without-ext>.pck)")
    p_check.add_argument("--snapshot", help="frozen candidate dir, to compare pack entries against")
    p_check.add_argument("--report")
    p_check.add_argument("--sums", help="append SHA256SUMS lines here")
    p_check.add_argument("--json")
    p_check.add_argument("--format", choices=("text", "json"), default="text")
    p_check.add_argument("--quiet", action="store_true",
                         help="print only the one-line summary; the full report goes to --report")
    p_check.set_defaults(func=cmd_check)

    args = parser.parse_args(argv)
    if not getattr(args, "func", None):
        parser.print_help()
        return 2
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
