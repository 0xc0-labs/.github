output "repositories" {
  description = "SSH clone URL of every managed repository."
  value       = { for k, r in module.repositories : k => r.ssh_clone_url }
}

output "runner_group" {
  description = "Name of the self-hosted runner group, for the runners on the CI VMs."
  value       = module.runner_group.name
}

output "cluster_runner_group" {
  description = "Name of the runner group for the runners that live in the cluster."
  value       = module.cluster_runner_group.name
}
