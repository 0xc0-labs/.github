locals {
  # GitHub returns the workflows sorted, a file's stem before any longer name
  # it starts: release.yml, then release-candidate.yml. A plain sort puts
  # them the other way round ('-' before '.'), and any order but GitHub's
  # shows a change on every plan. So the sort key moves the extension's dot
  # below every name character.
  workflows_by_key = { for w in var.workflows : replace(w, "/\\.(ya?ml)@/", " .$1@") => w }
}

resource "github_actions_runner_group" "main" {
  name       = var.name
  visibility = "selected"

  selected_repository_ids = var.repository_ids

  # Most of the org's repos are public. The group admits them, and the
  # workflows keep fork PRs off the self-hosted runners.
  allows_public_repositories = true

  # Only these workflows get a runner: a job a PR or a fork writes for itself
  # does not, whatever it asks for in runs-on.
  restricted_to_workflows = true
  # In GitHub's order (local.workflows_by_key).
  selected_workflows = [for k in sort(keys(local.workflows_by_key)) : local.workflows_by_key[k]]
}
