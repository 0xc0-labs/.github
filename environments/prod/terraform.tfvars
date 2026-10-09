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
    description     = "ArgoCD manifests for the cluster"
    topics          = ["argocd", "0xc0"]
    required_checks = ["issue / check"]
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
    required_checks = ["issue / check"]
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
}

# Only the repos whose CI needs the network.
runner_group = {
  name         = "0xc0"
  repositories = [".github", "infrastructure", "vault"]
  workflows = [
    "0xc0-labs/.github/.github/workflows/ansible.yml@refs/heads/main",
    "0xc0-labs/.github/.github/workflows/packer.yml@refs/heads/main",
    "0xc0-labs/.github/.github/workflows/tofu-plan.yml@refs/heads/main",
    "0xc0-labs/.github/.github/workflows/tofu-apply.yml@refs/heads/main",
  ]
}
