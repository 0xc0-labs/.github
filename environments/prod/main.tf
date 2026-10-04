module "repositories" {
  source   = "../../modules/repository"
  for_each = var.repositories

  name                = each.key
  description         = each.value.description
  topics              = each.value.topics
  visibility          = each.value.visibility
  auto_init           = each.value.auto_init
  ruleset_enforcement = var.bootstrap || each.value.bootstrap ? "disabled" : "active"

  required_status_checks = each.value.required_checks

  production_environment_reviewers = each.value.production_environment ? [var.operator_user_id] : []
}

module "runner_group" {
  source = "../../modules/runner-group"

  name           = var.runner_group.name
  repository_ids = [for repo in var.runner_group.repositories : module.repositories[repo].repo_id]
  workflows      = var.runner_group.workflows
}
