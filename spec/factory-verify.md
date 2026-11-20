# factory-verify

Issue: 0xc0-labs/.github#205. Parent: 0xc0-labs/workspace#269.

## Spec

A reusable workflow, `.github/workflows/factory-verify.yml`, that is the whole
CI of a repo Matchmark's factory works in. It reads the repo's contract,
`.factory/repo.yaml`, and runs the commands it declares in the image it
declares. A repo's caller is `uses: …/factory-verify.yml@main` and nothing
else.

Constraints:

- Version 1 requires `version: 1`, `image` and `commands.test`. `services`,
  `ui` and `build` are refused when present. `paths` and `egress` are not this
  workflow's; only `resources.timeout` applies of `resources`.
- The contract is a file of the repo, written by an agent: every value of it
  is untrusted. A command reaches the shell through an environment variable
  and is never interpolated into a script; a value is never echoed into a
  workflow command.
- It runs on GitHub's own runners, never on the org's (inside the network),
  and is not added to `runner_group.workflows`. No secret, no input; the token
  reads contents only; the checkout keeps no credentials.

## Plan

Two jobs, because a job's `container.image` is decided before any of its
steps run:

1. `contract`: checkout, parse `.factory/repo.yaml` with `yq` and `jq`
   (preinstalled on GitHub's runners), refuse what version 1 cannot honour
   with an error naming the field, and publish `image`, the four commands and
   the timeout in minutes as job outputs.
2. `commands`: `container: image: <contract image>`, checkout, then `setup`,
   `lint`, `typecheck` (when declared) and `test`, each a step of its own,
   run from an environment variable, under `timeout-minutes` from the
   contract (default 30, at most 360, GitHub's own limit).

The caller's job is `verify`, so the pull request shows `verify / contract`
and `verify / commands`: the names the factory reads, listed in the README.

Verification: `actionlint`; a throwaway caller and fixture on the branch (a
passing and a failing contract), their runs linked in the PR, removed before
merge.

## Tasks

- [ ] `factory-verify.yml`
- [ ] README: table row, the caller, the contract, job names, semgrep beside
  it, why GitHub's runners
- [ ] actionlint clean
- [ ] throwaway caller and fixtures run from the branch, then removed
