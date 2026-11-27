#!/usr/bin/env python3
"""Apply exactly one bounded textual mutation to DriveLab for negative control.

Used only by run_gearbox_mutant_control.sh. This helper is not part of the
validator and never runs against the real checkout.
"""

import argparse
import sys

ANCHORS = {
    "mirror_removed": (
        "\t\tvar published := gearbox.mirror_gear(committed)\n",
        "\t\tvar published: CarState = committed\n",
    ),
    "proposal_refused": (
        "\t\tvar proposal := gearbox.propose(committed, DT)\n",
        "\t\tvar proposal := gearbox.propose(committed, 0.0)\n",
    ),
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True)
    parser.add_argument("--mutation", required=True, choices=sorted(ANCHORS))
    args = parser.parse_args()
    anchor, replacement = ANCHORS[args.mutation]
    with open(args.target, "r", encoding="utf-8") as handle:
        source = handle.read()
    count = source.count(anchor)
    if count != 1:
        print("mutation anchor count=%d (expected 1)" % count, file=sys.stderr)
        return 1
    with open(args.target, "w", encoding="utf-8") as handle:
        handle.write(source.replace(anchor, replacement))
    return 0


if __name__ == "__main__":
    sys.exit(main())
