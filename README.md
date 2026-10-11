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
  pr-issue.yml             reusable: fail a PR that links no issue, unless one of the org's Apps opened it
  packer.yml               reusable: validate Packer templates; rebuild the affected ones, a job per chain, once approved
  hook-tests.yml           reusable: run a repo's hook test cases
  plugin-version.yml       reusable: fail a PR that changes a Claude Code plugin without bumping its version
  ansible.yml              reusable: the affected playbooks, in parallel; --check on a PR; for real, once approved
  kustomize-validate.yml   reusable: render each Kustomize component as Argo CD does, and validate it
  pin-check.yml            reusable: each environment's APP_VERSION is its image's newTag
  node-check.yml           reusable: lint, type-check and build a Node app with its mise toolchain
  container-image.yml      reusable: build an app's image; on main, push it to GHCR as sha-<7> and main
  release-candidate.yml    reusable: on a push to main, cut the next rc and open staging's PR in gitops
  release.yml              reusable: by hand, release the rc staging runs and open prod's PR in gitops
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

### Application repos

An application checks its code with `node-check` and builds its image with
`container-image`, which pushes to GHCR with the job's own `GITHUB_TOKEN`,
only from `main`. Trunk-based, so every commit there is a deployable image,
tagged `sha-<7>` and `main`. The image carries its commit: the build passes
`APP_COMMIT`, which the Dockerfile turns into an `ENV`.

Where they run depends on the repo:

- **A public repo** (`offby1.cc`) runs both on GitHub's runners, the
  default, with no Vault and no secret. Its build caches in GitHub's cache.
- **A private repo** (`payload`, `artistlabco.com`) runs its whole CI on
  the self-hosted runners: `runs-on: '{"group": "0xc0", "labels": "0xc0"}'`,
  and its repo in `runner_group.repositories`. The image is built by the
  instance's rootless BuildKit, which starts empty for every job, so the
  layer cache lives in GHCR beside the image (`:buildcache`), written by
  `main`'s builds alone. Only its rc and release jobs log in to Vault; its
  checks and its image never get `id-token: write`.

Either way the build carries a `mode=max` provenance and an SBOM, from a
scanner image pinned by digest.

The delivery, for an application with staging (`gitops`' `apps/<app>/staging/`
and `apps/<app>/prod/`, each with its pin):

1. **Every push to `main`**, after the image, `release-candidate` cuts
   `vX.Y.Z-rc.N`: the version `git-cliff` computes from the Conventional
   Commits since the last release (`feat` a minor, `fix` a patch, `!` a
   major, a minor while in 0.x; the first is 0.1.0), N one past the last rc of
   that version. It tags the commit and the image's digest with it, never
   rebuilding the image, and publishes the npm package, when there is one,
   as `X.Y.Z-rc.N` under the `rc` dist-tag. Then it opens a PR in `gitops`
   that changes only staging's pin, closes the older staging PRs still open,
   and sets it to merge itself once its checks pass.
2. **A release** is `release`, run by hand (`workflow_dispatch`). It reads
   staging's pin on `gitops`' `main`, checks that the rc's tag names the
   pinned digest, and makes `vX.Y.Z` of it: a tag on the same commit, a
   GitHub Release with `git-cliff`'s changelog since the last release, the
   same digest tagged `vX.Y.Z`, and the package as `X.Y.Z`. It fails if that
   release exists. Then it opens prod's PR in `gitops`, which never merges
   itself: merging it is prod's approval. Rolling back is reverting it.

Both PRs are opened by the `0xc0-labs-promoter` App, whose key never leaves
Vault: the job logs in with the JWT role named after its repo (bound to
`main` and to `release*.yml`), reads `ci/shared/github-promoter-app`, has
Transit sign the App's JWT, and exchanges it for a token narrowed to
`gitops`, contents and pull requests. The `issue` check lets the App's PRs
through with no linked issue. A pin edit keeps the rest of the file as it is:
`yq` sets the values, and only those lines change.

What an application brings: a `cliff.toml`; `git-cliff` and `crane` in its
`mise.toml`, and `node` when it publishes a package, which goes out as
committed, with no install and no lifecycle scripts; its JWT role in the
`vault` repo; its repo in the runner group; and `gitops`' pins, an `images:`
entry for `ghcr.io/0xc0-labs/<repo>` and `APP_VERSION` in a `release`
ConfigMap. `gitops`' `pin-check` keeps those two equal.

`pin-check` also keeps the org's bots to pins. A PR opened by
`0xc0-labs-promoter[bot]` or `0xc0-labs-renovate[bot]` fails it when it
changes anything but one environment's pin: the application's image
`newTag` and `digest`, and `APP_VERSION`, in a single
`apps/<app>/<env>/kustomization.yaml`. Any other file, or any other line of
that file, fails, named in the error. A human's PR is not limited. The check
reads the PR's author from the event and its diff from the API, before
anything from the PR's branch is checked out, and runs from `.github@main`:
the PR cannot change the rule it is checked by. Once `pin / check` is
required in `gitops`, a staging promotion that reaches past its pin cannot
merge itself.

```yaml
# .github/workflows/ci.yml, of a private application
on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  check:
    uses: 0xc0-labs/.github/.github/workflows/node-check.yml@main
    with:
      runs-on: '{"group": "0xc0", "labels": "0xc0"}'
  image:
    needs: check
    permissions:
      contents: read
      packages: write
    uses: 0xc0-labs/.github/.github/workflows/container-image.yml@main
    with:
      runs-on: '{"group": "0xc0", "labels": "0xc0"}'
  rc:
    needs: image
    if: github.event_name == 'push'
    permissions:
      contents: write
      packages: write
      id-token: write
    uses: 0xc0-labs/.github/.github/workflows/release-candidate.yml@main
    with:
      app: payload
      npm-package: packages/payload-types
```

```yaml
# .github/workflows/release.yml
on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  release:
    permissions:
      contents: write
      packages: write
      id-token: write
    uses: 0xc0-labs/.github/.github/workflows/release.yml@main
    with:
      app: payload
      npm-package: packages/payload-types
```

GHCR creates every package private, and only the web UI can change that, so
a new public application takes one manual step. After the first push to
`main`, the operator opens the package (github.com/orgs/0xc0-labs/packages),
goes to Package settings and picks Change visibility → Public. Only then
does gitops pin its digest: until it is public the cluster cannot pull the
image, and the route answers 503. Later images of the same package are
public already. A private application's image stays private: the cluster
pulls it with the read-only token at `apps/shared/ghcr-pull` in Vault.

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
