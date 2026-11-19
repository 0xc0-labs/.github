# release without an own image

Issue: 0xc0-labs/.github#201 (parent: workspace#252).

## Spec

An application whose images are all per-service, `ghcr.io/<repo>-<suffix>`,
with none named `ghcr.io/<repo>`, is released by `release` and
`release-candidate` and passes `pin-check`, under one version. Matchmark is
the first. An application with an image of its own behaves exactly as before:
`artistlabco.com` and `offby1.cc` run these workflows.

### Behaviour

- `release.yml` and `release-candidate.yml`: boolean input `own-image`,
  default `true`.
  - `true` or absent: the commands run are today's.
  - `false`: the `images` step does not start the list with the repo's own
    image, so `$IMAGES` is every `extra-images` entry and nothing else. Every
    later use of the list (digests, tags, pins, the checks on the pin file and
    on the PR) follows from it. An empty `extra-images` fails the run, in the
    `images` step, saying why.
  - In `release.yml`, with no staging, an image missing from the registry may
    be skipped only if it is not the repo's own. With `own-image: false` that
    exception covers every image: each one's prod digest is the fallback, as
    for a second image today.
- `pin-check.yml`: the images under `ghcr.io/<owner>/` in a pin are one
  application when their names are `<base>` and `<base>-<suffix>`, where
  `<base>` is the shortest name (today), or, when no name is that base, the
  longest common prefix of whole `-` words (`matchmark` for `matchmark-api` and
  `matchmark-stand-in-provider`). Each `newTag` is still `APP_VERSION`.
  - Fails: `matchmark-api` beside `offby1.cc`; names with no common word
    prefix.
  - Passes as today: one image alone; `<base>` with `<base>-<suffix>`.
- The bot's-PR checks hold unchanged: they blank every `newTag`, `digest` and
  `APP_VERSION` under `ghcr.io/<owner>/` and compare the rest, so they never
  depended on the base.

### Out of scope

`container-image.yml`, `kustomize-validate.yml`, any caller, a version per
image.

## Plan

1. `pin-check`: move the pins step's logic into
   `.github/actions/pin-check/pin-check.sh` (a function the composite action
   calls), with `test.sh` beside it, as `changes` and `component-paths` do.
   The workflow's `pins` step calls the action.
2. `release-candidate.yml`, `release.yml`: the `own-image` input, the `images`
   step, the failing empty `extra-images`, and (release) the registry
   exception.
3. README, Application repos: the caller of an application with no image of
   its own and no staging.
4. Checks: `test.sh` output, `actionlint` on the three workflows, and a diff
   read to confirm the `own-image: true` path's commands are unchanged.

## Tasks

- [x] pin-check script and its cases
- [x] pin-check workflow calls it
- [x] `own-image` in release-candidate
- [x] `own-image` in release
- [x] README
- [x] actionlint and tests green
