# terraform-google-talent-network

Terraform module for deploying the talent-network ecosystem on GCP.

## Conventions

### Naming
- Use **hyphens** (`-`) in all resource names, never underscores
- Bucket names: `${var.project_id}-<service>-db` (e.g., `${var.project_id}-search-mcp-db`)
- Secret IDs: `<service>-<purpose>` (e.g., `search-mcp-google-client-id`, `pyry-bot-token`)

### Security
- All storage buckets must have `public_access_prevention = "enforced"`
- Secrets must use regional replication (`user_managed` with specific regions), not `auto` (which replicates globally, including outside EU)
- Cloud Run services should use a dedicated runtime service account with minimal permissions, not the Terraform deployer account

### Provider Versions
- Google provider: `~> 7.0`
- Keep providers reasonably up to date; module is still v0.x so breaking changes are acceptable

### Variables
- Prefer explicit input variables over hardcoded values
- Allow customization of resource names, Cloud Run settings, etc. via variables
- Use sensible defaults that work for most partners

## Workflow

1. Create a feature branch from main for all changes
2. Each logical fix should be a separate commit with conventional commit format
3. Test with `terraform validate` and `terraform fmt -check` before committing
