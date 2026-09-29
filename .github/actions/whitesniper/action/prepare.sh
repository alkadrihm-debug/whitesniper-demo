#!/usr/bin/env bash
# Resolves the WhiteSniper CLI and the run's choices for the WhiteSniper Action (action.yml).
# Inputs arrive only as environment variables, never interpolated into this script.
set -euo pipefail

dir="${RUNNER_TEMP:?}/whitesniper"
mkdir -p "$dir/out"

sources=0
[ -n "${WS_VERSION:-}" ] && sources=$((sources + 1))
[ -n "${WS_PACKAGES_DIR:-}" ] && sources=$((sources + 1))
[ -n "${WS_CLI_PATH:-}" ] && sources=$((sources + 1))
if [ "$sources" -ne 1 ]; then
  echo "::error title=WhiteSniper::Set exactly one of the inputs version, packages-dir, or cli-path."
  exit 1
fi

if [ -n "${WS_CLI_PATH:-}" ]; then
  # Physical paths on both sides (macOS runners reach temp directories through a symlink).
  bin="$(cd "$(dirname "$WS_CLI_PATH")" && pwd -P)/$(basename "$WS_CLI_PATH")"
  # On pull requests the base is checked out in place, which would change a CLI inside the tree.
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ "${WS_EVENT_NAME:-}" == pull_request* ]] && [ -n "$top" ] && [[ "$bin" == "$top"/* ]]; then
    echo "::error title=WhiteSniper::cli-path must be outside the repository on pull requests (the base is checked out in place). Use packages-dir or version."
    exit 1
  fi
else
  prefix="$dir/cli"
  mkdir -p "$prefix"
  if [ -n "${WS_VERSION:-}" ]; then
    if ! [[ "$WS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]]; then
      echo "::error title=WhiteSniper::version must be an exact version such as 1.2.3."
      exit 1
    fi
    # --ignore-scripts: nothing from the registry runs at install time.
    npm install --prefix "$prefix" --no-audit --no-fund --ignore-scripts "@whitesniper/cli@${WS_VERSION}"
  else
    shopt -s nullglob
    tarballs=("$WS_PACKAGES_DIR"/*.tgz)
    if [ "${#tarballs[@]}" -eq 0 ]; then
      echo "::error title=WhiteSniper::packages-dir has no .tgz files."
      exit 1
    fi
    npm install --prefix "$prefix" --no-audit --no-fund --ignore-scripts "${tarballs[@]}"
  fi
  bin="$prefix/node_modules/@whitesniper/cli/dist/bin.js"
fi
if [ ! -f "$bin" ]; then
  echo "::error title=WhiteSniper::The WhiteSniper CLI was not found at $bin."
  exit 1
fi
node "$bin" --version

# Trust: code from a fork is someone else's, so engines that run repository code stay off.
fork=false
if [[ "${WS_EVENT_NAME:-}" == pull_request* ]] && [ "${WS_HEAD_REPOSITORY:-}" != "${WS_REPOSITORY:-}" ]; then
  fork=true
fi
case "${WS_TRUST:-auto}" in
  auto) if [ "$fork" = true ]; then trust_flag="--untrusted"; else trust_flag=""; fi ;;
  trusted) trust_flag="" ;;
  untrusted) trust_flag="--untrusted" ;;
  *) echo "::error title=WhiteSniper::trust must be auto, trusted, or untrusted."; exit 1 ;;
esac
if [ -z "$trust_flag" ] && git config --get-regexp '^http\..*\.extraheader$' >/dev/null 2>&1; then
  echo "::warning title=WhiteSniper::actions/checkout left its token in .git/config, and engines that run repository code are on. Set persist-credentials: false on the checkout step."
fi

public=false
[ "${WS_REPOSITORY_PRIVATE:-}" = "false" ] && public=true

case "${WS_SIGN:-auto}" in
  auto) if [ "$public" = true ] && [ "$fork" = false ]; then sign=keyless; else sign=none; fi ;;
  keyless)
    sign=keyless
    if [ "$public" != true ]; then
      echo "::notice title=WhiteSniper::Signing keylessly on a private repository: Sigstore's public transparency log permanently records this repository and workflow."
    fi
    ;;
  none) sign=none ;;
  *) echo "::error title=WhiteSniper::sign must be auto, keyless, or none."; exit 1 ;;
esac
# A fork's workflow gets no OIDC token, so it cannot sign keylessly.
if [ "$fork" = true ] && [ "$sign" = keyless ]; then
  echo "::notice title=WhiteSniper::The evidence of a pull request from a fork is not signed: its workflow gets no OIDC token."
  sign=none
fi
# Keyless signing needs the job's OIDC token (permissions: id-token: write).
if [ "$sign" = keyless ] && [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; then
  if [ "${WS_SIGN:-auto}" = keyless ]; then
    echo "::error title=WhiteSniper::sign: keyless needs permissions: id-token: write on the job."
    exit 1
  fi
  echo "::notice title=WhiteSniper::The evidence is not signed: grant permissions: id-token: write to sign it keylessly."
  sign=none
fi

# A fork's read-only token cannot upload to code scanning.
case "${WS_UPLOAD_SARIF:-auto}" in
  auto) if [ "$public" = true ] && [ "$fork" = false ]; then upload_sarif=true; else upload_sarif=false; fi ;;
  true | false) upload_sarif="$WS_UPLOAD_SARIF" ;;
  *) echo "::error title=WhiteSniper::upload-sarif must be auto, true, or false."; exit 1 ;;
esac

{
  echo "dir=$dir"
  echo "ws=$bin"
  echo "trust-flag=$trust_flag"
  echo "sign=$sign"
  echo "upload-sarif=$upload_sarif"
} >> "$GITHUB_OUTPUT"
