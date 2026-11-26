variable "name" {
  description = "Team name. GitHub derives the slug from it, and other repos refer to the team by that slug."
  type        = string
}

variable "description" {
  description = "What the team is for."
  type        = string
}

variable "members" {
  description = "GitHub logins in the team, each with its role: member or maintainer. The list is authoritative: a login not here is removed from the team."
  type        = map(string)

  validation {
    condition     = alltrue([for role in values(var.members) : contains(["member", "maintainer"], role)])
    error_message = "A member's role is member or maintainer."
  }
}
