# .github — organization Terraform

The `0xc0-labs` org in OpenTofu, and the reusable workflows every repo calls.
`README.md` says what is where and how it is operated. The rules every repo
follows are in the workspace's `CLAUDE.md`; this file holds only this repo's.

## The `.github/` path

Cloned locally as `.github/`, matching the repo name.

That path is special to GitHub: it is where a repo declares its workflows,
CODEOWNERS and community health files. The workspace `.gitignore` must keep
ignoring this directory — without it, this repo's contents would be committed
into the workspace repo at exactly the path GitHub reads.

## Rules

- Changes in this org are **rare and destructive**. No opportunistic changes:
  one PR, one intent.
- A repo is created only from here, through `modules/repository/`, never from
  the web UI: squash-only, the default-branch ruleset and secret scanning are
  baked in there. `README.md`, section Adding a repo.
- The org's first apply runs with `-var bootstrap=true`, or `main` cannot take
  its first push. Do not improvise the order: `README.md`, section Bootstrap.
- Never keep a saved plan file: it contains the App private key in plaintext.
- Before opening a PR, run `scripts/tofu prod plan` and read it line by line.
  A repo or a permission that exists on GitHub but not in Terraform shows up
  as a diff, and that is a finding, not a curiosity.
- The self-hosted runners live on the two CI VMs, `vm-ci-01` (10.10.1.10) and
  `vm-ci-02` (10.10.1.20), ephemeral, two on each. Do not register others.
- A reusable workflow that needs the network, or that a private repo runs,
  is listed in the runner group's `workflows`.

## Outside Terraform, deliberately

The org project board (Projects v2) is not supported by the GitHub provider,
so it is created and configured by hand. It is an exception, not drift.

GHCR packages are not either, nor the REST API. Both are set by hand, and
neither is drift:

- The org's **Package creation** setting (Settings → Packages): Public is
  enabled, so an application's image can be pulled by the cluster with no
  secret (operator decision, 2026-10-02).
- **Each package's visibility**: `README.md`, section Application repos, its
  last paragraph.
- **Each npm package's Actions access**, the app repos that may read it:
  `README.md`, section Shared packages.

## Visibility

This repo is **public**, deliberately: the org profile README only shows from
a public `.github`. So the org's OpenTofu and the reusable workflows are
readable by anyone.
