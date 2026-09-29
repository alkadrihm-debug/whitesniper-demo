#!/usr/bin/env bash
# Fails the job when the scan's gate failed or the verification failed (action.yml). An
# inconclusive verification is reported, not failed: something could not be checked.
set -euo pipefail

if [ "${WS_GATE:-}" != "passed" ]; then
  echo "::error title=WhiteSniper::The gate failed: new findings at or above the fail-on level, or an engine failed."
  exit 1
fi
case "${WS_OUTCOME:-}" in
  failed)
    echo "::error title=WhiteSniper::Verification failed: see the comment, the check run, or the evidence artifact."
    exit 1
    ;;
  inconclusive)
    echo "::warning title=WhiteSniper::Verification was inconclusive: something could not be checked."
    ;;
esac
