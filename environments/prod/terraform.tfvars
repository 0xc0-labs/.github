operator_user_id = 94703619 # sergioaten

# Topics: 0xc0 on every repo, app on every application, plus one per tool
# the repo actually contains.
repositories = {
  ".github" = {
    description            = "Organization Terraform, reusable workflows and org-wide templates"
    topics                 = ["0xc0", "opentofu", "github-actions"]
    production_environment = true
    required_checks        = ["issue / check", "plan / tofu"]
  }
  "workspace" = {
    description = "Umbrella workspace: cross-repo rules, design and bootstrap"
    topics      = ["0xc0", "claude-code", "mise"]
  }
  "claude-config" = {
    description     = "Claude Code marketplace and the 0xc0 plugin"
    topics          = ["0xc0", "claude-code"]
    required_checks = ["issue / check"]
  }
  "infrastructure" = {
    description            = "Packer, OpenTofu and Ansible for the Proxmox node"
    topics                 = ["0xc0", "proxmox", "opentofu", "packer", "ansible"]
    production_environment = true
    required_checks        = ["issue / check", "plan / tofu"]
  }
  "gitops" = {
    description = "ArgoCD manifests for the cluster"
    topics      = ["argocd", "0xc0"]
    # validate.yml runs both of its jobs on every PR, with no paths filter.
    required_checks = ["issue / check", "validate / validate", "pin / check"]
    # Staging's promotion PRs merge themselves, once these pass; prod's never do.
    allow_auto_merge = true
    merge_queue      = true
  }
  "vault" = {
    description            = "OpenTofu configuration of the cluster's Vault"
    topics                 = ["0xc0", "opentofu", "vault"]
    auto_init              = true
    production_environment = true
    required_checks        = ["issue / check", "plan / tofu"]
  }
  "offby1.cc" = {
    description     = "Landing page for offby1.cc"
    topics          = ["0xc0", "app", "nextjs"]
    auto_init       = true
    required_checks = ["issue / check", "check / check", "image / image"]
  }
  "artistlabco.com" = {
    description = "Website for artistlabco.com"
    topics      = ["0xc0", "app"]
    visibility  = "private"
    auto_init   = true
  }
  "payload" = {
    description = "Payload CMS: multi-tenant backend for the frontends"
    topics      = ["0xc0", "app", "payload", "nextjs"]
    visibility  = "private"
    auto_init   = true
  }
  "packages" = {
    description = "Shared npm packages, @0xc0-labs/<name>, that every app pins"
    topics      = ["0xc0", "npm", "typescript"]
    visibility  = "private"
    auto_init   = true
  }
}

# The repos whose CI needs the network, and the applications' jobs that run
# here: their rc and release, which log in to Vault. Every other job, an
# application's or packages', runs on GitHub's runners (README); packages,
# and the workflows those jobs call, stay listed as the fallback should
# GitHub's free minutes run out (workspace#138).
runner_group = {
  name         = "0xc0"
  repositories = [".github", "infrastructure", "vault", "payload", "artistlabco.com", "packages", "offby1.cc"]
  workflows = [
    "0xc0-labs/.github/.github/workflows/ansible.yml@refs/heads/main",
    "0xc0-labs/.github/.github/workflows/packer.yml@refs/heads/main",
    "0xc0-labs/.github/.github/workflows/tofu-plan.yml@refs/heads/main",
    "0xc0-labs/.github/.github/workflows/tofu-apply.yml@refs/heads/main",
    "0xc0-labs/.github/.github/workflows/node-check.yml@refs/heads/main",
    "0xc0-labs/.github/.github/workflows/container-image.yml@refs/heads/main",
    "0xc0-labs/.github/.github/workflows/release-candidate.yml@refs/heads/main",
    "0xc0-labs/.github/.github/workflows/release.yml@refs/heads/main",
    "0xc0-labs/.github/.github/workflows/package-release.yml@refs/heads/main",
  ]
}
