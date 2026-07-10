# Security Model

This document describes the security architecture and IAM configuration for the talent-network module.

## Public Cloud Run Services

All Cloud Run services are deployed with `allUsers` as an invoker. This is intentional:

| Service | Why Public | Authentication |
|---------|-----------|----------------|
| **mcp-agileday** | MCP protocol endpoint for AI clients | API key via `X-API-Key` header |
| **Pyry** | Slack webhook endpoint | Slack signing secret verification |
| **mcp-talent-network** | MCP protocol endpoint for federation | API key via `X-API-Key` header |
| **Minna** | Slack webhook endpoint | Slack signing secret verification |
| **Topi** | Slack webhook endpoint | Slack signing secret verification |

**Why not use IAM for Cloud Run?**

- Slack webhooks require unauthenticated HTTPS endpoints — Slack doesn't support GCP IAM tokens
- MCP clients (Claude Desktop, Cursor, etc.) use API keys, not IAM

**How requests are authenticated:**

1. **Slack bots (Pyry, Minna, Topi):** Every request is verified against the Slack signing secret before processing. Invalid signatures are rejected with 401.

2. **MCP servers (mcp-agileday, mcp-talent-network):** API key authentication via `X-API-Key` header, validated against the secret stored in Secret Manager.

## Secret Management

Secrets are stored in Google Secret Manager and mounted as environment variables at runtime. Cloud Run's service account has `secretmanager.secretAccessor` role.

**Regional replication:** All secrets use `user_managed` replication with the configured `var.region` as the single replica location. This ensures secrets stay within the EU (when using EU regions) and are not automatically replicated globally.

| Secret | Purpose | Who Sets It |
|--------|---------|-------------|
| `ai-talent-search-mcp-api-key` | API key for mcp-agileday | Auto-generated |
| `pyry-bot-token` | Slack bot token | User (Phase 5) |
| `pyry-slack-signing-secret` | Slack request verification | User (Phase 5) |
| `ai-talent-network-mcp-api-key` | API key for federation node | Auto-generated |
| `partner-secret` | Shared secret for anonymous candidate IDs | Auto-generated |

**Auto-generated secrets** use `random_password` with 64 characters, no special characters. API keys rotate when the corresponding `image_tag` changes (via `keepers`). The `partner-secret` is stable and never rotates automatically — this ensures anonymous candidate IDs remain consistent across deployments.

## Anonymous Candidate IDs

When consultants appear in cross-company search results, their identities are protected using deterministic anonymous IDs. Both `mcp-agileday` and `mcp-talent-network` share a `PARTNER_SECRET` environment variable that's used to generate consistent HMAC-SHA256 hashes of candidate identifiers.

This ensures:
- The same consultant always gets the same anonymous ID within a partner's federation
- Anonymous IDs cannot be reversed to reveal the original consultant identity
- Partners can correlate results across searches without exposing consultant names

## Data Storage

Each partner's data stays in their own GCP project:

| Bucket | Contents | Access |
|--------|----------|--------|
| `{project}-search-mcp-db` | Consultant profiles, embeddings, search index | Service account only |
| `{project}-talent-network-db` | Anonymized consultant data for federation | Service account only |

Buckets have:
- Uniform bucket-level access (no ACLs)
- Public access prevention enforced
- Versioning enabled
- Service account has `storage.objectAdmin`

## Federation Privacy

When a partner joins the Minna federation:

1. Their `mcp-talent-network` node exposes **anonymized** search results
2. Minna queries all partner nodes and aggregates results
3. Full consultant details are only visible within the partner's own Slack (via Pyry)
4. Cross-company searches show skills/experience but not names or contact info
5. Anonymous candidate IDs are generated using HMAC-SHA256 with the shared `partner-secret`

Rakettitiede does not have access to partner consultant databases — only the anonymized results that partners choose to expose.

## IAM Roles

### Runtime Service Account (created by module)

The module creates a `talent-network-runtime` service account with minimal permissions for Cloud Run services:

| Role | Purpose |
|------|---------|
| `roles/secretmanager.secretAccessor` | Read secrets at runtime |
| `roles/aiplatform.user` | Access Vertex AI for embeddings/LLM |
| `roles/storage.objectAdmin` | Read/write data buckets (scoped per bucket) |

This minimizes blast radius — if a Cloud Run service is compromised, the attacker only has read access to secrets and data buckets, not admin access to create/delete resources.

### Terraform Deployer (optional, provided by user)

You can run Terraform as yourself via `gcloud auth application-default login`, or create a dedicated service account for CI/CD pipelines:

| Role | Purpose |
|------|---------|
| `roles/run.admin` | Deploy and manage Cloud Run services |
| `roles/storage.admin` | Create and manage GCS buckets |
| `roles/secretmanager.admin` | Create and manage secrets |
| `roles/iam.serviceAccountAdmin` | Create runtime service account |
| `roles/iam.serviceAccountUser` | Deploy Cloud Run with runtime SA |
| `roles/serviceusage.serviceUsageConsumer` | Enable GCP APIs |
| `roles/resourcemanager.projectIamAdmin` | Manage project IAM bindings |

Note: `roles/artifactregistry.admin` is **not** required — images are pulled from Rakettitiede's registry, and Cloud Run Service Agent access is granted during partner onboarding (Phase 2).

## Recommendations

1. **Rotate API keys periodically** by updating `image_tags` (triggers new random password)
2. **Monitor Cloud Run logs** for authentication failures
3. **Use VPC Service Controls** if you need to restrict data egress
