#!/usr/bin/env bash
# Scans the head, and on pull requests the base, then verifies the change against the base
# (action.yml). The gate is decided later (gate.sh), after the results are published.
set -euo pipefail

out="$WS_DIR/out"
common=()
[ -n "${WS_TRUST_FLAG:-}" ] && common+=("$WS_TRUST_FLAG")
[ "${WS_OFFLINE:-false}" = "true" ] && common+=("--offline")
# Scans take the exclusions; verify reuses the ones recorded in the base report. Arrays that may be
# empty are expanded as ${a[@]+"${a[@]}"}: bash 3.2 (macOS) treats them as unset under set -u.
excludes=()
while IFS= read -r path; do
  [ -n "$path" ] && excludes+=("--exclude=$path")
done <<< "${WS_EXCLUDE:-}"

# Exit codes: 0 passed, 1 gate failed; anything else is a usage or internal error.
run_ws() {
  set +e
  node "$WS" "$@"
  local code=$?
  set -e
  if [ "$code" -gt 1 ]; then
    echo "::error title=WhiteSniper::whitesniper $1 failed (exit $code)."
    exit "$code"
  fi
  return 0
}

run_ws scan --root . ${common[@]+"${common[@]}"} ${excludes[@]+"${excludes[@]}"} --fail-on "${WS_FAIL_ON:-high}" --quiet \
  --json "$out/report.json" --sarif "$out/report.sarif" --markdown "$out/report.md" --html "$out/report.html"
gate="$(node -e 'console.log(require(process.argv[1]).gate.passed ? "passed" : "failed")' "$out/report.json")"
echo "gate=$gate" >> "$GITHUB_OUTPUT"

outcome=""
signed=unsigned
base="${WS_BASE_SHA:-}"
if [ -n "$base" ]; then
  if ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
    git fetch --no-tags --depth=1 origin "$base" >/dev/null 2>&1 || true
  fi
  if ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
    echo "::warning title=WhiteSniper::The base commit is not available, so the change was not verified. Check out with fetch-depth: 0."
  elif ! git diff --quiet HEAD --; then
    echo "::warning title=WhiteSniper::Tracked files were changed before WhiteSniper ran, so the base could not be checked out and the change was not verified."
  else
    # The base is scanned in place, with the dependencies and build outputs this job installed,
    # so differences between the two scans come from the change, not from the environment.
    head="$(git rev-parse HEAD)"
    trap 'git -c advice.detachedHead=false checkout --quiet --detach "$head"' EXIT
    git -c advice.detachedHead=false checkout --quiet --detach "$base"
    run_ws scan --root . ${common[@]+"${common[@]}"} ${excludes[@]+"${excludes[@]}"} --fail-on none --quiet --json "$out/base.json"
    git -c advice.detachedHead=false checkout --quiet --detach "$head"
    trap - EXIT

    verify_args=(verify --report "$out/base.json" --root . ${common[@]+"${common[@]}"} --fail-on "${WS_FAIL_ON:-high}"
      --evidence-dir "$out/evidence" --json "$out/verify.json" --quiet)
    while IFS= read -r command; do
      [ -n "$command" ] && verify_args+=("--build=$command")
    done <<< "${WS_BUILD:-}"
    while IFS= read -r command; do
      [ -n "$command" ] && verify_args+=("--test=$command")
    done <<< "${WS_TEST:-}"
    bundle="$out/change-evidence.sigstore.json"
    rm -f "$out/verify.json" "$bundle"
    if [ "${WS_SIGN:-none}" = "keyless" ]; then
      verify_args+=(--bundle "$bundle" --keyless)
    fi
    set +e
    node "$WS" "${verify_args[@]}"
    code=$?
    set -e
    if [ "$code" -gt 1 ]; then
      # verify writes its report before it signs, so a report without a bundle means only the
      # signing failed (Sigstore unreachable or refusing): publish the results unsigned.
      if [ "${WS_SIGN:-none}" = "keyless" ] && [ -f "$out/verify.json" ] && [ ! -f "$bundle" ]; then
        echo "::warning title=WhiteSniper::Keyless signing failed, so the evidence is not signed. The verification itself completed."
      else
        echo "::error title=WhiteSniper::whitesniper verify failed (exit $code)."
        exit "$code"
      fi
    fi
    [ -f "$bundle" ] && signed=keyless
    outcome="$(node -e 'console.log(require(process.argv[1]).verification.outcome)' "$out/verify.json")"
  fi
fi
{
  echo "outcome=$outcome"
  echo "signed=$signed"
} >> "$GITHUB_OUTPUT"
