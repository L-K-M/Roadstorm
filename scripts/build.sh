#!/usr/bin/env bash
# Validate and optionally smoke-export Roadstorm Racer!. This is a thin entry
# point over the project-owned tooling: tools/ci/ci.sh runs every engine check
# in isolated scratch copies, and tools/export_smoke/run_export_smoke.sh builds
# frozen desktop smoke packages without claiming target-platform verification.
#
# Usage: scripts/build.sh [--check] [--export] [--godot PATH]
#        [--launch-probe headless|full] [-- [ci.sh global options]]
set -euo pipefail

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  awk 'NR==1 && /^#!/ {next} /^#/ {sub(/^# ?/,""); print; next} {exit}' "$0"
  exit 0
fi

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
check=false
export_smoke=false
launch_probe=headless
godot_args=()
ci_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) check=true ;;
    --export) export_smoke=true ;;
    --godot)
      [[ $# -ge 2 ]] || { echo 'error: --godot needs a path' >&2; exit 2; }
      godot_args+=(--godot "$2"); shift ;;
    --launch-probe)
      [[ $# -ge 2 ]] || { echo 'error: --launch-probe needs headless or full' >&2; exit 2; }
      launch_probe="$2"; shift ;;
    --) shift; ci_args+=("$@"); break ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

if $check; then
  echo "tools/ci/ci.sh ${godot_args[*]} ${ci_args[*]} all"
  if $export_smoke; then
    echo "tools/export_smoke/run_export_smoke.sh --launch-probe $launch_probe"
  fi
  exit 0
fi

tools/ci/ci.sh "${godot_args[@]}" "${ci_args[@]}" all
if $export_smoke; then
  tools/export_smoke/run_export_smoke.sh --launch-probe "$launch_probe"
fi
