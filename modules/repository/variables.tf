variable "name" {
  description = "Repository name."
  type        = string
}

variable "description" {
  description = "One-line description shown on GitHub."
  type        = string
}

variable "visibility" {
  description = "public or private. On the Free plan, rulesets only apply to public repos."
  type        = string
  default     = "public"

  validation {
    condition     = contains(["public", "private"], var.visibility)
    error_message = "visibility must be public or private."
  }
}

variable "topics" {
  description = "Repository topics."
  type        = list(string)
  default     = []
}

variable "ruleset_enforcement" {
  description = "active, or disabled only while bootstrapping a repo whose history has not been pushed yet."
  type        = string
  default     = "active"

  validation {
    condition     = contains(["active", "disabled"], var.ruleset_enforcement)
    error_message = "ruleset_enforcement must be active or disabled."
  }
}

variable "required_status_checks" {
  description = "Check contexts that must pass before merging. Only list checks that run on every PR, or PRs that skip them can never merge."
  type        = list(string)
  default     = []
}

variable "production_environment_reviewers" {
  description = "GitHub user IDs who must approve every apply from this repo. Empty: the repo gets no production environment."
  type        = list(number)
  default     = []
}

variable "allow_auto_merge" {
  description = "Let a PR be set to merge itself once its required checks pass. Only where a bot opens PRs that need no human review."
  type        = bool
  default     = false
}

variable "auto_init" {
  description = "Create the repo with an initial commit on main. Only for a brand-new repo with no history elsewhere: set at creation, it never changes afterwards."
  type        = bool
  default     = false
}

variable "merge_queue" {
  description = "Require merging through a merge queue. Only once the repo's callers of every required check trigger on merge_group, or no PR can merge: README, A repo with a merge queue. Needs required_status_checks and a public repo."
  type        = bool
  default     = false
}
