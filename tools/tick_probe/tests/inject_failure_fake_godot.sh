#!/bin/sh
# Test double for run_contract_tests.py: emits a well-formed contract report
# that reports failures while exiting 0. The runner must fail closed on the
# reported failure regardless of the child exit status.
#
# Usage: FAKE_CHECKS=<total> FAKE_FAILED=<count> inject_failure_fake_godot.sh
# Extra command-line arguments (the real Godot flags) are intentionally ignored.
checks=${FAKE_CHECKS:-77}
failed=${FAKE_FAILED:-1}
cat <<EOF
TEST_RESULT {"schema":"roadstorm.tick_probe.contract.v1","checks_total":${checks},"checks_failed":${failed},"failures":["injected reported failure"]}
TESTS_TOTAL=${checks} TESTS_FAILED=${failed}
EOF
exit 0
