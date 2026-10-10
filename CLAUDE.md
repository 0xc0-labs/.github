# .github — organization Terraform

Manages the `0xc0-labs` org with Terraform/OpenTofu, plus the reusable
workflows.

Cloned locally as `.github/`, matching the repo name.

That path is special to GitHub: it is where a repo declares its workflows,
CODEOWNERS and community health files. The workspace `.gitignore` must keep
ignoring this directory — without it, this repo's contents would be committed
into the workspace repo at exactly the path GitHub reads.

## Contents

- `modules/repository/` — the only way a repo is created. Squash-only, the
  default-branch ruleset and secret scanning are baked in there.
- `modules/runner-group/` — the org runner group for the self-hosted runners
  on the CI VMs, restricted to the repos and workflows that need them.
- `environments/prod/` — the root. Calls the repository module once per repo
  and the runner-group module once. The `production` Actions environment every
  apply waits on lives in the repository module, opted into per repo
  (`production_environment`). State key `0xc0/.github/prod.tfstate`.
- `.github/workflows/` — **every workflow with steps of its own lives here, as
  a reusable one**; the other repos only hold thin callers with their triggers
  and paths (operator decision, 2026-09-29). `tofu-plan` and `tofu-apply` plan
  and apply an OpenTofu root; `org-plan` and `org-apply` run them for this
  repo. `packer` validates a repo's Packer templates, and rebuilds the ones a
  push affects, one job per chain of clones, in parallel.
  `hook-tests` runs a repo's hook test cases. `plugin-version` fails a PR
  that changes a Claude Code plugin without bumping its version, or whose
  marketplace entry declares another one. `ansible` runs a repo's
  playbooks the change affects, each in its own job, in parallel: with
  `--check --diff` on a PR, for real on a push once approved.
  `kustomize-validate` renders each Kustomize component of a GitOps repo as
  Argo CD does, and validates it. `node-check` lints, type-checks and builds
  a Node app; `container-image` builds an app's image and, on `main`, pushes
  it to GHCR (`sha-<7>` and `main`, never `latest`). `pr-issue` fails a PR
  that links no issue; `issue` runs it for this repo. A reusable workflow that
  needs the network is listed in the runner group's `workflows`.

Layout and naming conventions are in `README.md`, section Conventions. The
bootstrap order is there too. Do not improvise it: the org's first apply runs
with `-var bootstrap=true`, or `main` cannot take its first push.

## Outside Terraform, deliberately

The org project board (Projects v2) is not supported by the GitHub provider,
so it is created and configured by hand. It is an exception, not drift.

GHCR packages are not either, nor the REST API. Both are set by hand, and
neither is drift:

- The org's **Package creation** setting (Settings → Packages): Public is
  enabled, so an application's image can be pulled by the cluster with no
  secret (operator decision, 2026-10-02).
- **Each package's visibility.** A package is always created private on its
  first push. After an application's first push to `main`, the operator makes
  it public from its Package settings, before gitops deploys it. A public
  package cannot go private again.

## Visibility

This repo is **public**, deliberately. The org profile README only shows from
a public `.github`.

The consequence is that the org Terraform and the reusable workflows are
readable by anyone. No secret value ever goes in here — only references.

## Hard rules

- Everything written is in English: files, file names, comments, commits,
  branches and PRs.
- Changes in this org are **rare and destructive**. No opportunistic changes:
  one PR, one intent.
- `infrastructure` and `.github`: `main` only, PR required, apply behind manual
  approval.
- Applications: a test environment only where the app needs one; then
  test→prod promotes the same digest, never a rebuild.
- No organization secret in cleartext in the code. Reference it, never the value.
- The self-hosted runners live on the two CI VMs, `vm-ci-01` (10.10.1.10) and
  `vm-ci-02` (10.10.1.20), ephemeral, two on each. Do not register others.
- Never run `tofu apply` or `destroy`. Here least of all.
- No work without an issue on the org project board. The PR links it
  (`Closes #N` / `Refs owner/repo#N`) or the `issue` check fails. See the
  workspace `CLAUDE.md`, section Tracking.
- Never keep a saved plan file: it contains the App private key in plaintext.
- OpenTofu is always written as modules, laid out as `modules/<name>/` and
  `environments/<env>/`. A root only calls modules; a resource sits in a root
  only when it belongs to no reusable concept.

## Before opening a PR

Run `scripts/tofu prod plan` and read it line by line. A repo or a permission
that exists on GitHub but not in Terraform shows up here as a diff, and that
is a finding, not a curiosity.

## Bootstrapping new repos

A new repo is created **from here**, with Terraform, not from the web UI. See
`README.md`, section Adding a repo.

The module creates no files in the repo. The `0xc0` Claude Code plugin is
installed per machine, from the workspace:

```
claude plugin install 0xc0@0xc0-labs --scope project
```

Enabling it in settings does not install it.
