#!/usr/bin/env bash
# Publishes the results: job summary, the pull-request comment, and the check run (action.yml).
set -euo pipefail

out="$WS_DIR/out"
args=(github report --report "$out/report.json" --evidence-artifact "$WS_ARTIFACT" --signing "${WS_SIGNED:-unsigned}")
[ -f "$out/verify.json" ] && args+=(--verify "$out/verify.json")
[ "${WS_SARIF_UPLOADED:-false}" = "true" ] && args+=(--sarif-uploaded)
[ "${WS_COMMENT:-true}" = "true" ] || args+=(--no-comment)
[ "${WS_CHECK_RUN:-true}" = "true" ] || args+=(--no-check-run)
[ -n "${WS_COMMENT_AUTHOR:-}" ] && args+=(--comment-author "$WS_COMMENT_AUTHOR")
node "$WS" "${args[@]}"
