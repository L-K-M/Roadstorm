#!/usr/bin/env python3
"""Roadstorm Racer! asset manifest validator - command-line entry point.

Ownership: tools/asset_manifest/** (PLAN.md M0 provenance manifest tooling,
job 6058a51e-ae48-4329-8fb0-52c3c36eddad).

Thin wrapper around ``manifest_validator`` so the check can be run without
importing anything:

    python3 tools/asset_manifest/validate_manifest.py assets/manifest.json
    python3 tools/asset_manifest/validate_manifest.py --root . --check-hashes

Exit codes: 0 = no errors, 1 = validation errors, 2 = the manifest could not
be read or the command line was wrong. The same convention as
tools/toolchain/verify.sh and tools/ci/ci.sh.

Original project code under the Unlicense.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from manifest_validator import main  # noqa: E402  (path set up above)

if __name__ == "__main__":
    sys.exit(main())
