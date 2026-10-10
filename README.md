# .github

Organization Terraform for `0xc0-labs`, and the reusable workflows every
repo calls.

What the org runs, and how, is in [`profile/README.md`](profile/README.md),
which GitHub shows on the organization page.

```
profile/README.md          the org page: what the project is
modules/repository/        every repo is created through this module
modules/runner-group/      the runner group for the self-hosted runners on the CI VMs
environments/prod/         root: calls the modules
scripts/tofu               runs tofu on an environment, secrets read from Vault into env
mise.toml                  pinned tool versions
.github/workflows/
  tofu-plan.yml            reusable: fmt, validate, plan, comment on the PR
  tofu-apply.yml           reusable: apply inside an approval-gated environment
  pr-issue.yml             reusable: fail a PR that links no issue
  packer.yml               reusable: validate Packer templates; rebuild the affected ones, a job per chain, once approved
  hook-tests.yml           reusable: run a repo's hook test cases
  plugin-version.yml       reusable: fail a PR that changes a Claude Code plugin without bumping its version
  ansible.yml              reusable: the affected playbooks, in parallel; --check on a PR; for real, once approved
  kustomize-validate.yml   reusable: render each Kustomize component as Argo CD does, and validate it
  node-check.yml           reusable: lint, type-check and build a Node app with its mise toolchain
  container-image.yml      reusable: build an app's image; on main, push it to GHCR as sha-<7> and main
  org-plan.yml             this repo: plan environments/prod on every PR
  org-apply.yml            this repo: apply it after merge, once approved
  issue.yml                this repo: run pr-issue on every PR
```

## Conventions

The layout follows Google's Terraform best practices, and is the same in every
repo that holds OpenTofu:

```
modules/<name>/            resources: main.tf, variables.tf, outputs.tf, README
environments/<env>/        root: backend.tf, main.tf, terraform.tfvars
```

- A root only calls modules. A resource sits in a root only when it belongs to
  no reusable concept.
- State key: `0xc0/<repo>/<environment>.tfstate`. Here,
  `0xc0/.github/prod.tfstate`.
- A resource that is the only one of its type is named `main`.
- Root values go in `terraform.tfvars`. Secrets come from the environment.
  `bootstrap` is the one exception: command line only, never committed.
- The inputs/outputs section of a module README is generated:
  `mise run docs`.

## Running it locally

Tools come from `mise.toml`. Secrets never touch disk: `scripts/tofu` reads
them from Vault into the environment for one command, over WARP, logged in
with `vault login -no-print`.

```
scripts/tofu prod init
scripts/tofu prod plan
```

## Using the reusable workflows from another repo

Every workflow with steps of its own lives here. A repo only holds thin
callers: the triggers and paths, then `uses:` one of these, `@main`.

```yaml
# Every reusable workflow asks for id-token: the job logs in to Vault with
# GitHub's OIDC token.
permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  plan:
    uses: 0xc0-labs/.github/.github/workflows/tofu-plan.yml@main
    with:
      working-directory: environments/prod
      vault-addr: https://vault.int.0xc0.cc
      vault-role: infrastructure
      vault-secrets: |
        ci/data/shared/rustfs access_key_id | AWS_ACCESS_KEY_ID ;
        ci/data/shared/rustfs secret_access_key | AWS_SECRET_ACCESS_KEY ;
```

No `runs-on` is needed: the job defaults to the self-hosted runners on
the CI VMs, and fork PRs go to `ubuntu-latest`. The runner group admits the
reusable workflows already, as they are on `main`, but only from the repos in
`runner_group.repositories`, in `environments/prod/terraform.tfvars`: the
caller's repo must be listed there.

**Secrets come from Vault, and no repo holds any** (operator decision,
2026-10-01). The job logs in with its GitHub OIDC token (JWT auth, through
`hashicorp/vault-action`), with the caller's `vault-addr` and `vault-role`.
It then reads `vault-secrets`, in vault-action's format: one
`<path> <key> | <ENV_VAR> ;` per secret. Each lands in the job's environment,
masked, under the name the code reads, and `VAULT_ADDR` and `VAULT_TOKEN` are
set for a root whose provider talks to Vault. No Vault credential and no
Actions secret is stored: Vault's role checks the token's repository and the
reusable workflow it runs (`job_workflow_ref`), and the policy names each path
the repo may read. `ansible` writes the CI SSH key from the variable that
`ssh-key-env` names.

A repo whose applies run from CI needs `production_environment = true` in
`environments/prod/terraform.tfvars`: that creates the approval-gated
environment the apply workflow waits on.

An application repo checks its code and builds its image on GitHub's runners,
with no Vault and no secret: `container-image` pushes to GHCR with the job's
own `GITHUB_TOKEN`, only from `main`. Trunk-based, so every commit there is a
deployable image, tagged `sha-<7>` and `main`; gitops pins the digest from the
job's summary.

GHCR creates every package private, and only the web UI can change that, so
a new application takes one manual step. After the first push to `main`, the
operator opens the package (github.com/orgs/0xc0-labs/packages), goes to
Package settings and picks Change visibility → Public. Only then does gitops
pin its digest: until it is public the cluster cannot pull the image, and the
route answers 503. Later images of the same package are public already.

```yaml
on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read
  packages: write

jobs:
  check:
    uses: 0xc0-labs/.github/.github/workflows/node-check.yml@main
  image:
    needs: check
    uses: 0xc0-labs/.github/.github/workflows/container-image.yml@main
```

## Bootstrap

This repo creates every repo in the org, itself included, so the first run
cannot come from CI. The order matters:

1. **First apply, rulesets disabled.** With them active, `main` could not
   receive its initial push.
   `scripts/tofu prod apply -var bootstrap=true`
2. **Push the existing history** of the five local repos to their new remotes.
3. **Its secrets come from Vault** (`ci/github/org-app`, `ci/shared/rustfs`),
   read by `scripts/tofu` with the operator's token. With Vault down, restore
   it first (`vault` repo, README); in the meantime the operator can export
   the `TF_VAR_github_app_*` and `AWS_*` variables by hand, and `scripts/tofu`
   reads only what is unset.
4. **Second apply, rulesets active.** `scripts/tofu prod apply`
   From here on, every change goes through a PR and `org-apply`.

## Adding a repo

An entry in `repositories`, in `environments/prod/terraform.tfvars`, and a PR.
How its `main` gets its first commit decides the rest:

- **Brand new, no history anywhere:** `auto_init = true`. GitHub creates it
  with an initial commit, and its ruleset is active from the start.
- **Existing history, pushed from a local repo:** `bootstrap = true`. Only its
  ruleset is created disabled. Push the history, then a second PR removes the
  flag, and the ruleset turns active. Every other repo stays protected
  throughout. If its CI needs secrets, it gets a `ci/<repo>/` path, a policy
  and a JWT role in the `vault` repo.

## Concurrency

Several PRs can plan, and several merges can apply, against the same state.

- **Plans**: one at a time per PR and root. A newer push replaces a plan that
  has not started; a running plan is never cancelled, because killing tofu
  mid-run can leave the lock behind.
- **Applies**: queued per root, oldest first, never cancelled once running. If
  a third merge arrives while one apply runs and another waits, the waiting one
  is dropped — `main` is linear, so the newest commit already contains it.
- **Every apply re-plans** against the live state. The plan posted on a PR is
  for review; it is never what gets applied.
- **Locks are waited for**, not failed on: 5 minutes for plans and local runs,
  10 for CI applies.
- **Stale PR plans** — PR B planned before PR A merged — are stopped by the
  ruleset requiring branches to be up to date.

## Secrets

In Vault, never in a repo, not even encrypted. Each repo's CI reads only what
its policy names, from the `ci/` engine: its own `ci/<repo>/*` and the
`ci/shared/*` secrets it is granted by name. Rotation is the operator's, by
hand in Vault. With the cluster or Vault down, the pipelines have no
credentials until Vault is restored from PBS and unsealed: the accepted risk
(`vault` repo, README).

## State

RustFS at `https://s3.0xc0.cc`, bucket `tfstate`, locked with a lockfile. It is
reachable only from inside the network: from the CI VMs, or over WARP for local
runs. Every root in the org has its own key; roots never share a state.
