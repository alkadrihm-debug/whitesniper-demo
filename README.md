# whitesniper-demo

A public demonstration of the **WhiteSniper GitHub Action**. On each pull request, the Action:

- scans the change and its base;
- verifies the change against the base: it rechecks every finding with its original detector and runs the build;
- publishes the results as one pull-request comment, updated in place, and a check run with annotations on the exact lines;
- uploads SARIF to code scanning;
- attaches the reports and the evidence as an artifact, signed keylessly with Sigstore.

WhiteSniper is private until its release. This repository therefore carries two copies:

- a copy of its Action, in `.github/actions/whitesniper`;
- its packed command-line tool, in `vendor/whitesniper`.

## The seeded problems

The code on `main` contains deliberate problems. The workflow does not install Ruff, Gitleaks, Opengrep, OSV-Scanner, or Pyright, so the Action lists them under "Engines that did not run" and does not report their findings. The Ruff finding below appears only where Ruff is installed.

| File | Problem | Detector |
|---|---|---|
| `AGENTS.md` | A hidden right-to-left override character in an instruction file for AI agents | hidden-unicode (critical) |
| `.mcp.json` | An MCP server launched from an unpinned package | WS-ASC-005 (high) |
| `.github/workflows/ci.yml` | An action pinned to a tag, not a commit SHA | WS-ASC-009 (high) |
| `.github/workflows/ci.yml` | No `permissions:` block | WS-ASC-010 (medium) |
| `src/math.ts` | A type error | TypeScript TS2322 (high) |
| `src/server.ts` | `fetch()` without a timeout | WS-STD-003 (medium) |
| `src/app.py` | `subprocess` with `shell=True` on an argument | Ruff S602 (high), where Ruff is installed |

Four repository-hygiene findings are accepted in `whitesniper.baseline.json`: a missing lockfile, tests, `SECURITY.md`, and `LICENSE`. That is how a repository adopts WhiteSniper without fixing everything first. Baseline findings are shown in the comment, but they do not fail the gate and are not verification targets.

## The demo pull request

The pull request fixes the seeded problems in two pushes.

1. **Push 1** fixes `AGENTS.md`, `.mcp.json`, and `src/server.ts`. The verification **fails**, because the other targeted findings are still present and the build (`tsc`) fails on `src/math.ts`. The Action posts its comment and annotates the remaining findings.
2. **Push 2** fixes `.github/workflows/ci.yml`, `src/math.ts`, and `src/app.py`. The verification passes (**verified**), and the gate passes. The Action **updates the same comment**.

## Running it

The workflow is `.github/workflows/whitesniper.yml`. It runs on pull requests only when GitHub Actions is enabled for this repository; Actions minutes are free for public repositories.

GitHub skips workflows for a pull request whose head commit message contains `[skip ci]`.

## Workflow security

- Every third-party action is pinned to a full commit SHA.
- The job has only the permissions it needs, and the checkout does not keep its token.
- The Action installs the packed tool with `npm install --ignore-scripts` into the runner's temporary directory, so nothing from the registry runs at install time.
- The GitHub token reaches only the publishing step.

`vendor/whitesniper/SHA256SUMS` lists the tarballs' checksums.

## Updating the packed tool

From a WhiteSniper checkout:

```sh
pnpm build
for pkg in contracts core runtime mcp github cli; do
  pnpm --filter "@whitesniper/${pkg}" pack --pack-destination <this-repo>/vendor/whitesniper
done
(cd <this-repo>/vendor/whitesniper && sha256sum *.tgz > SHA256SUMS)
```

Also copy `action.yml` and `action/*.sh` into `.github/actions/whitesniper/`.
