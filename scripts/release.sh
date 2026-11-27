#!/usr/bin/env bash
# Tags a Roadstorm source release through the shared lkm-release engine. The
# project is pre-release: publication packaging, notarization/platform evidence
# and final release destinations are M9 decisions in PLAN.md, so this stub is
# intentionally tag-only and no automated public release is claimed.
#
# Usage: scripts/release.sh X.Y.Z [--push]
# Shared engine: https://github.com/L-K-M/release-tool (this stub only sets config).
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

export RELEASE_APP_NAME="Roadstorm Racer!"
export RELEASE_KIND="tag-only"
export RELEASE_CI_NOTE="CI validates the tagged source. Public package publication remains a separate authorized M9 release decision."
export RELEASE_INVOKED_AS="scripts/release.sh"

BIN="${LKM_RELEASE_BIN:-lkm-release}"
command -v "$BIN" >/dev/null 2>&1 || {
  echo "error: lkm-release not found — clone https://github.com/L-K-M/release-tool and run ./install.sh" >&2
  exit 1
}
exec "$BIN" "$@"
