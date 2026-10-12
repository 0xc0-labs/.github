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
  plugin-version.yml       reusable: fail a PR that changes a Claude Code plugin without bumping its version, or whose marketplace entry declares another
  ansible.yml              reusable: the affected playbooks, in parallel; on a PR, the caller's ansible-lint, then --check; for real, once approved
  kustomize-validate.yml   reusable: render each Kustomize component as Argo CD does, and validate it
  pin-check.yml            reusable: each environment's APP_VERSION is its image's newTag
  node-check.yml           reusable: lint, type-check, build and, when asked, test a Node app, with its mise.toml's node and pnpm
  container-image.yml      reusable: build an app's image; on main, push it to GHCR as sha-<7> and main
  release-candidate.yml    reusable: on a push to main, cut the next rc and open staging's PR in gitops
  release.yml              reusable: by hand, release the rc staging runs and open prod's PR in gitops
  package-release.yml      reusable: on a push to main, release a package of a monorepo to GitHub Packages
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
- A `moved`, `import` or `removed` block is removed in a later PR, once its
  apply is done and the plan shows no changes.

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
tagged `sha-<7>` and `main`, never `latest`. The image carries its commit:
the build passes `APP_COMMIT`, which the Dockerfile turns into an `ENV`.

`node-check` installs only `node` and `pnpm` from the repo's `mise.toml`,
at the versions there, checked against its `mise.lock`. A tool the repo
declares for people (a language server, Claude Code's plugins, a local object
store) is never downloaded by CI. Its `tools` input adds names to that list.
Its job asks for `packages: read`, to install a private `@0xc0-labs` package
(Shared packages, below), and a called workflow cannot get more than its
caller grants: every caller grants its `check` job `packages: read`, or the
run fails before it starts.

With `test: true`, `node-check` runs `pnpm test` after the build, on the same
runner. The tests bring up what they need themselves, and the workflow starts
no service: `payload`'s start their own PostgreSQL from mise, on a Unix socket
in a temporary directory, with nothing listening on the network. `tools`
carries what they need: `tools: conda:postgresql`.

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
   and sets it to merge itself once its checks pass. A failed run can be
   rerun: on the same commit it reuses its rc, skips what it finds published
   and matching, fails on what differs, and never opens again a staging PR
   that was closed or merged, so an old rc cannot roll staging back.
2. **A release** is `release`, run by hand (`workflow_dispatch`). It reads
   staging's pin on `gitops`' `main`, checks that the rc's tag names the
   pinned digest, and makes `vX.Y.Z` of it: a tag on the same commit, a
   GitHub Release with `git-cliff`'s changelog since the last release, the
   same digest tagged `vX.Y.Z`, and the package as `X.Y.Z`. Then it opens
   prod's PR in `gitops`, which never merges itself: merging it is prod's
   approval. Rolling back is reverting it. A failed run can be rerun, and
   finishes what the first left undone: the tag, the Release, the image's
   tag, the package and prod's PR are each skipped when they are there and
   match, and fail the run when they differ (the tag on another commit, the
   image's tag on another digest, the package with other contents, an open
   PR with another pin).

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
    permissions:
      contents: read
      packages: read
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
    inputs:
      rc:
        description: The rc to release, vX.Y.Z-rc.N. Empty, the rc staging runs.
        type: string
        default: ""

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
      rc: ${{ inputs.rc }}
```

Leave `rc` empty: the release takes the rc staging runs. Name it only to
finish a release whose run failed after staging moved to a newer rc. A rerun
of the failed run reads staging again: it would release the newer rc, or fail
when that rc is of the same version, whose tag is on another commit. A new
run naming the failed one's rc finishes that release instead. A named rc must
exist, as an image tag and as a git tag, or the run fails.

GHCR creates every package private, and only the web UI can change that, so
a new public application takes one manual step. After the first push to
`main`, the operator opens the package (github.com/orgs/0xc0-labs/packages),
goes to Package settings and picks Change visibility → Public. Only then
does gitops pin its digest: until it is public the cluster cannot pull the
image, and the route answers 503. Later images of the same package are
public already, and a public package cannot go private again. A private
application's image stays private: the cluster pulls it with the read-only
token at `apps/shared/ghcr-pull` in Vault.

### Shared packages

Code two repos need alike lives once, in the private repo `packages`: a pnpm
workspace with one package per `packages/<name>`, each published as
`@0xc0-labs/<name>` to GitHub Packages, private, and pinned by each app that
uses it.

**The versioning scheme** (#108): each package has its own version,
Semantic Versioning computed by `git-cliff` from the Conventional Commits
that change its directory, whatever their scope. Since its last release, a
`feat` bumps the minor, a `!` the major (the minor while in 0.x), and any
other commit the patch, unless the repo's `cliff.toml` skips it. The first
release is 0.1.0. A release is three things, all named for the package:

- the tag `<name>-vX.Y.Z`, on the last commit that changed its directory;
- a GitHub Release of that tag, with the changelog since the one before;
- `@0xc0-labs/<name>@X.Y.Z` on GitHub Packages, under `latest`.

There are no prereleases. **Merged is published**: on every push to `main`,
after its checks, `package-release` runs once per package, and releases each
one whose directory has something new. The others are skipped. A failed run
can be rerun, and finishes what the first left undone. An app's issue that
waits on a package's change turns workable when that change merges, so its
version exists by the time the app's session starts. Apps pin versions, so a
release changes nothing an app runs until its pin moves.

What `packages` brings: a `cliff.toml`; `node`, `pnpm` and `git-cliff` in its
`mise.toml`; and in each package's `package.json`:

- `name`: `@0xc0-labs/<name>`, its directory's. The workflow fails otherwise.
- `repository`: `{"type": "git", "url": "git+https://github.com/0xc0-labs/packages.git", "directory": "packages/<name>"}`.
  GitHub Packages links the package to that repo, whose token publishes it.
- `version`: `0.0.0`. The tag holds the version, and the workflow sets it
  before it packs.
- `files`, what it publishes, and a `build` script when it compiles: the
  workflow runs it before packing, at the release's commit.
- No `workspace:` dependency on another package of the repo: it would be
  published with that one's committed `0.0.0`.

```yaml
# .github/workflows/ci.yml, of packages
on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  check:
    permissions:
      contents: read
      packages: read
    uses: 0xc0-labs/.github/.github/workflows/node-check.yml@main
    with:
      runs-on: '{"group": "0xc0", "labels": "0xc0"}'
      test: true
  release:
    needs: check
    if: github.event_name == 'push'
    permissions:
      contents: write
      packages: write
    strategy:
      fail-fast: false
      matrix:
        # Every package, added in the PR that creates it.
        package: [observability]
    uses: 0xc0-labs/.github/.github/workflows/package-release.yml@main
    with:
      directory: packages/${{ matrix.package }}
      runs-on: '{"group": "0xc0", "labels": "0xc0"}'
```

**Reading one, from an app.** No secret in any repo: each place gets a token
of its own.

1. **The app** commits a `.npmrc` with the scope's registry alone, which
   pnpm and Renovate read, and in `pnpm-workspace.yaml` exempts the org's
   packages from `minimumReleaseAge`: they are ours, and the version merged
   an hour ago is the one its issue waits on.

   ```
   @0xc0-labs:registry=https://npm.pkg.github.com
   ```

   ```yaml
   minimumReleaseAgeExclude:
     - '@0xc0-labs/*'
   ```

2. **Access**, by the operator, once per package and app, after the
   package's first release: github.com/orgs/0xc0-labs/packages, the package,
   Package settings, Manage Actions access, Add repository: the app, role
   Read. Neither the GitHub provider nor the REST API sets it, so it is by
   hand, like a package's visibility. Without it, the app's CI and image get
   a 403 or 404 for the package.

3. **CI**: `node-check` installs with the job's own token, which its caller
   grants `packages: read` (Application repos, above). Nothing else.

4. **The image**: `container-image` hands the build the secret `npmrc`, a
   user config with the job's token, which reads what its `packages: write`
   lets it. The Dockerfile mounts it on the install alone:

   ```dockerfile
   RUN --mount=type=secret,id=npmrc \
       NPM_CONFIG_USERCONFIG=/run/secrets/npmrc pnpm install --frozen-lockfile
   ```

   Never as a build arg, an `ENV` or a `COPY`: those land in a layer, or in
   the provenance. The mount is readable by root alone; a stage that runs as
   another user adds `uid=<its uid>` to it.

5. **A developer's machine, and a session's worktree**: pnpm takes the token
   from the user's config, outside every checkout, so a worktree under
   `.worktrees/` needs nothing of its own. A repo's `.npmrc` would put it in
   git, and a `mise.local.toml` is missing from a fresh worktree. Once per
   machine, gh's token gets the scope, and `~/.npmrc` a reference to it, not
   the token:

   ```sh
   gh auth refresh -h github.com -s read:packages
   ```

   ```
   //npm.pkg.github.com/:_authToken=${NODE_AUTH_TOKEN}
   ```

   Then the shell that installs exports
   `NODE_AUTH_TOKEN="$(gh auth token)"`. Exported from the operator's
   profile, with gh on its PATH there, it reaches every Claude Code
   session too, whose shell starts from that profile.

## Bootstrap

This repo creates every repo in the org, itself included, so the first run
cannot come from CI. The order matters:

1. **First apply, rulesets disabled.** With them active, `main` could not
   receive its initial push.
   `scripts/tofu prod apply -var bootstrap=true`
2. **Push the existing history** of every repo whose entry in
   `terraform.tfvars` has no `auto_init` to its new remote.
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

The module creates no files in the repo. Its `.claude/settings.json`, and
installing the `0xc0` plugin on each machine, are in `claude-config`'s
[Installing](https://github.com/0xc0-labs/claude-config#installing).

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
