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
  # Sorted: GitHub returns them in this order, so any other shows a change on
  # every plan.
  selected_workflows = sort(var.workflows)
}
