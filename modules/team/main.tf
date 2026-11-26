resource "github_team" "main" {
  name        = var.name
  description = var.description
  privacy     = "closed"
}

resource "github_team_membership" "main" {
  for_each = var.members

  team_id  = github_team.main.id
  username = each.key
  role     = each.value
}
