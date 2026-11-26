output "id" {
  description = "Team ID, as an environment's reviewers take it."
  value       = github_team.main.id
}

output "slug" {
  description = "Team slug."
  value       = github_team.main.slug
}
