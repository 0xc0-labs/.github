variable "github_app_id" {
  description = "GitHub App ID used to manage the org. Comes from the environment, never from a tfvars file."
  type        = string
}

variable "github_app_installation_id" {
  description = "Installation ID of that App on the org. Comes from the environment."
  type        = string
}

variable "github_app_private_key" {
  description = "PEM contents of the App private key. Comes from the environment."
  type        = string
  sensitive   = true
}

variable "operator_user_id" {
  description = "GitHub user ID of the operator, who approves every apply."
  type        = number
}

# Deliberately set only on the command line (-var bootstrap=true), never in
# terraform.tfvars: committed, it would leave every ruleset disabled.
variable "bootstrap" {
  description = "True only for the org's very first apply, before any history is pushed: every ruleset is created disabled so each main can receive its initial push. A repo added later uses its own bootstrap in repositories instead."
  type        = bool
  default     = false
}

variable "repositories" {
  description = "Every repository in the org, keyed by name. Adding a repo is adding an entry here."
  type = map(object({
    description = string
    topics      = optional(list(string), [])
    # A private repo gets no ruleset: the Free plan applies them to public
    # repos only.
    visibility = optional(string, "public")
    # CI applies wait for the operator's approval.
    production_environment = optional(bool, false)
    # Brand new, no history: an initial commit lets its ruleset start active.
    auto_init = optional(bool, false)
    # A repo added with existing history: its ruleset alone is disabled while
    # that history is pushed. Remove it right after.
    bootstrap = optional(bool, false)
    # Only checks that report on every PR, once they have run: one that never
    # reports blocks every PR.
    required_checks = optional(list(string), [])
  }))

  validation {
    condition     = alltrue([for name in keys(var.repositories) : can(regex("^[A-Za-z0-9._-]{1,100}$", name))])
    error_message = "Repository names may only contain letters, digits, '.', '_' and '-', up to 100 characters."
  }

  validation {
    condition     = alltrue([for r in values(var.repositories) : length(trimspace(r.description)) > 0])
    error_message = "Every repository needs a non-empty description."
  }
}

variable "runner_group" {
  description = "The self-hosted runner group, and the managed repositories that may use it."
  type = object({
    name         = string
    repositories = list(string)
    workflows    = list(string)
  })

  validation {
    condition     = alltrue([for repo in var.runner_group.repositories : contains(keys(var.repositories), repo)])
    error_message = "The runner group lists a repository that is not managed here."
  }
}
