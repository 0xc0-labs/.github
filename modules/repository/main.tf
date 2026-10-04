resource "github_repository" "main" {
  name         = var.name
  description  = var.description
  visibility   = var.visibility
  topics       = var.topics
  has_issues   = true
  has_projects = true
  has_wiki     = false

  allow_squash_merge          = true
  allow_merge_commit          = false
  allow_rebase_merge          = false
  squash_merge_commit_title   = "PR_TITLE"
  squash_merge_commit_message = "PR_BODY"
  delete_branch_on_merge      = true

  auto_init = var.auto_init

  archive_on_destroy = true

  dynamic "security_and_analysis" {
    for_each = var.visibility == "public" ? [1] : []
    content {
      secret_scanning {
        status = "enabled"
      }
      secret_scanning_push_protection {
        status = "enabled"
      }
    }
  }
}

resource "github_repository_vulnerability_alerts" "main" {
  repository = github_repository.main.name
  enabled    = true
}

# The Free plan applies rulesets to public repos only.
resource "github_repository_ruleset" "main" {
  count = var.visibility == "public" ? 1 : 0

  name        = "default-branch"
  repository  = github_repository.main.name
  target      = "branch"
  enforcement = var.ruleset_enforcement

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true

    # Single operator: a PR is required, but nobody else can approve it.
    pull_request {
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = true
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_review_thread_resolution = true
      allowed_merge_methods             = ["squash"]
    }

    dynamic "required_status_checks" {
      for_each = length(var.required_status_checks) > 0 ? [1] : []
      content {
        strict_required_status_checks_policy = true

        dynamic "required_check" {
          for_each = var.required_status_checks
          content {
            context = required_check.value
          }
        }
      }
    }
  }
}

# The reviewer's approval is the human launching the apply.
resource "github_repository_environment" "main" {
  count = length(var.production_environment_reviewers) > 0 ? 1 : 0

  repository  = github_repository.main.name
  environment = "production"

  reviewers {
    users = var.production_environment_reviewers
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "main" {
  count = length(var.production_environment_reviewers) > 0 ? 1 : 0

  repository     = github_repository.main.name
  environment    = github_repository_environment.main[0].environment
  branch_pattern = "main"
}

moved {
  from = github_repository_ruleset.main
  to   = github_repository_ruleset.main[0]
}
